locals {
  clone_warm_script = file("${path.module}/scripts/clone-warm.sh")

  # Run-command body: a preamble exporting the SSM Command parameters as DEVBOX_*
  # env vars (SSM substitutes the {{ }} placeholders), then the verbatim script
  # piped to bash via a quoted heredoc. aws:runShellScript runs under /bin/sh, so
  # the explicit bash guarantees the script's arrays/here-strings work; the quoted
  # delimiter keeps the script's own ${VAR}/$(...) literal (the child bash, which
  # inherits the exported env, evaluates them).
  clone_warm_run_command = concat(
    [
      "export DEVBOX_REPOS='{{ Repos }}'",
      "export DEVBOX_GH_KEY_PARAM='{{ GitHubAppKeyParam }}'",
      "export DEVBOX_GH_APP_ID='{{ GitHubAppId }}'",
      "export DEVBOX_GH_INSTALLATION_ID='{{ GitHubAppInstallationId }}'",
      "export DEVBOX_MOUNT='{{ MountPoint }}'",
      "bash <<'DEVBOX_CLONE_WARM_EOF'",
    ],
    [local.clone_warm_script],
    ["DEVBOX_CLONE_WARM_EOF"],
  )
}

################################################################################
# KMS key for the workspace snapshot
################################################################################

resource "aws_kms_key" "workspace" {
  description             = "Encryption key for devbox workspace data-volume snapshots"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-workspace"
  })
}

resource "aws_kms_alias" "workspace" {
  name          = "alias/${local.name_prefix}-workspace"
  target_key_id = aws_kms_key.workspace.key_id
}

################################################################################
# SSM parameter: latest workspace snapshot id
################################################################################

# Seeded with a placeholder; the build automation owns the value thereafter. The
# pool gates the data-volume block-device-mapping on a feature flag until the
# first real snapshot id is published (it can't attach "none").
resource "aws_ssm_parameter" "workspace_snapshot" {
  name  = var.ssm_parameter_path
  type  = "String"
  value = "none"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-workspace-snapshot-latest"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

################################################################################
# Clone/warm SSM Command document (run on the builder)
################################################################################

resource "aws_ssm_document" "clone_warm" {
  name            = "${local.name_prefix}-clone-warm-${substr(sha256(local.clone_warm_script), 0, 8)}"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Clone repos source-only onto the workspace data volume and prepare it for snapshotting"
    parameters = {
      Repos = {
        type        = "String"
        description = "Comma-separated git clone URLs"
      }
      GitHubAppKeyParam = {
        type        = "String"
        description = "SSM SecureString name holding the GitHub App private key (PEM)"
        default     = ""
      }
      GitHubAppId = {
        type        = "String"
        description = "GitHub App ID / Client ID (JWT issuer)"
        default     = ""
      }
      GitHubAppInstallationId = {
        type        = "String"
        description = "GitHub App installation ID"
        default     = ""
      }
      MountPoint = {
        type        = "String"
        description = "Workspace mount point"
        default     = "/workspace"
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "cloneWarm"
      inputs = {
        timeoutSeconds = "3600"
        runCommand     = local.clone_warm_run_command
      }
    }]
  })

  tags = local.tags
}

################################################################################
# Build Automation document
################################################################################

resource "aws_ssm_document" "snapshot_build" {
  name            = "${local.name_prefix}-build"
  document_type   = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Build an encrypted workspace EBS snapshot and publish its id"
    assumeRole    = aws_iam_role.snapshot_automation.arn
    mainSteps = [
      {
        name      = "resolveAmi"
        action    = "aws:executeAwsApi"
        onFailure = "Abort"
        inputs = {
          Service = "ssm"
          Api     = "GetParameter"
          Name    = var.ami_parameter
        }
        outputs  = [{ Name = "AmiId", Selector = "$.Parameter.Value", Type = "String" }]
        nextStep = "launchBuilder"
      },
      {
        name      = "launchBuilder"
        action    = "aws:executeAwsApi"
        onFailure = "Abort"
        inputs = {
          Service          = "ec2"
          Api              = "RunInstances"
          ImageId          = "{{ resolveAmi.AmiId }}"
          InstanceType     = var.builder_instance_type
          MinCount         = 1
          MaxCount         = 1
          SubnetId         = var.build_subnet_ids[0]
          SecurityGroupIds = [aws_security_group.build.id]
          IamInstanceProfile = {
            Name = aws_iam_instance_profile.builder_instance.name
          }
          MetadataOptions = {
            HttpEndpoint = "enabled"
            HttpTokens   = "required"
          }
          BlockDeviceMappings = [{
            DeviceName = local.data_device
            Ebs = {
              VolumeSize          = var.data_volume_size_gb
              VolumeType          = "gp3"
              DeleteOnTermination = true
              Encrypted           = true
              KmsKeyId            = aws_kms_key.workspace.arn
            }
          }]
          TagSpecifications = [
            { ResourceType = "instance", Tags = local.instance_tag_set },
            { ResourceType = "volume", Tags = local.instance_tag_set },
          ]
        }
        outputs  = [{ Name = "InstanceId", Selector = "$.Instances[0].InstanceId", Type = "String" }]
        nextStep = "waitForSsmOnline"
      },
      {
        name           = "waitForSsmOnline"
        action         = "aws:waitForAwsResourceProperty"
        onFailure      = "step:terminateBuilder"
        timeoutSeconds = 600
        inputs = {
          Service          = "ssm"
          Api              = "DescribeInstanceInformation"
          Filters          = [{ Key = "InstanceIds", Values = ["{{ launchBuilder.InstanceId }}"] }]
          PropertySelector = "$.InstanceInformationList[0].PingStatus"
          DesiredValues    = ["Online"]
        }
        nextStep = "runCloneWarm"
      },
      {
        name      = "runCloneWarm"
        action    = "aws:runCommand"
        onFailure = "step:terminateBuilder"
        inputs = {
          DocumentName   = aws_ssm_document.clone_warm.name
          InstanceIds    = ["{{ launchBuilder.InstanceId }}"]
          TimeoutSeconds = var.clone_warm_timeout_seconds
          CloudWatchOutputConfig = {
            CloudWatchLogGroupName  = aws_cloudwatch_log_group.builds.name
            CloudWatchOutputEnabled = true
          }
          Parameters = {
            Repos                   = [join(",", var.repos)]
            GitHubAppKeyParam       = [var.github_app_private_key_param_name]
            GitHubAppId             = [var.github_app_id]
            GitHubAppInstallationId = [var.github_app_installation_id]
            MountPoint              = ["/workspace"]
          }
        }
        nextStep = "describeDataVolume"
      },
      {
        name      = "describeDataVolume"
        action    = "aws:executeAwsApi"
        onFailure = "step:terminateBuilder"
        inputs = {
          Service = "ec2"
          Api     = "DescribeVolumes"
          Filters = [
            { Name = "attachment.instance-id", Values = ["{{ launchBuilder.InstanceId }}"] },
            { Name = "attachment.device", Values = [local.data_device] },
          ]
        }
        outputs  = [{ Name = "VolumeId", Selector = "$.Volumes[0].VolumeId", Type = "String" }]
        nextStep = "createSnapshot"
      },
      {
        name      = "createSnapshot"
        action    = "aws:executeAwsApi"
        onFailure = "step:terminateBuilder"
        inputs = {
          Service           = "ec2"
          Api               = "CreateSnapshot"
          VolumeId          = "{{ describeDataVolume.VolumeId }}"
          Description       = "devbox workspace snapshot"
          TagSpecifications = [{ ResourceType = "snapshot", Tags = local.snapshot_tag_set }]
        }
        outputs  = [{ Name = "SnapshotId", Selector = "$.SnapshotId", Type = "String" }]
        nextStep = "waitSnapshotComplete"
      },
      {
        name           = "waitSnapshotComplete"
        action         = "aws:waitForAwsResourceProperty"
        onFailure      = "step:terminateBuilder"
        timeoutSeconds = 3600
        inputs = {
          Service          = "ec2"
          Api              = "DescribeSnapshots"
          SnapshotIds      = ["{{ createSnapshot.SnapshotId }}"]
          PropertySelector = "$.Snapshots[0].State"
          DesiredValues    = ["completed"]
        }
        nextStep = "publishParameter"
      },
      {
        name      = "publishParameter"
        action    = "aws:executeAwsApi"
        onFailure = "step:terminateBuilder"
        inputs = {
          Service   = "ssm"
          Api       = "PutParameter"
          Name      = var.ssm_parameter_path
          Value     = "{{ createSnapshot.SnapshotId }}"
          Type      = "String"
          Overwrite = true
        }
        nextStep = "cleanupOldSnapshots"
      },
      {
        name      = "cleanupOldSnapshots"
        action    = "aws:executeScript"
        onFailure = "step:terminateBuilder"
        inputs = {
          Runtime = "python3.11"
          Handler = "handler"
          InputPayload = {
            RetentionCount    = var.retention_count
            SnapshotParameter = var.ssm_parameter_path
          }
          Script = file("${path.module}/scripts/cleanup-snapshots.py")
        }
        nextStep = "terminateBuilder"
      },
      {
        name   = "terminateBuilder"
        action = "aws:executeAwsApi"
        isEnd  = true
        inputs = {
          Service     = "ec2"
          Api         = "TerminateInstances"
          InstanceIds = ["{{ launchBuilder.InstanceId }}"]
        }
      },
    ]
  })

  tags = local.tags
}

################################################################################
# Schedule: start the build automation on a cadence
################################################################################

resource "aws_cloudwatch_event_rule" "snapshot_schedule" {
  name                = "${local.name_prefix}-schedule"
  description         = "Run the workspace snapshot build on a cadence"
  schedule_expression = var.schedule_expression
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "snapshot_build" {
  rule     = aws_cloudwatch_event_rule.snapshot_schedule.name
  arn      = "arn:${local.aws_partition}:ssm:${local.aws_region}:${local.aws_account_id}:automation-definition/${aws_ssm_document.snapshot_build.name}:${aws_ssm_document.snapshot_build.default_version}"
  role_arn = aws_iam_role.snapshot_events.arn
}
