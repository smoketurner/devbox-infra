"""Roll the warm pool onto a new workspace snapshot.

The pool launch template carries the workspace EBS snapshot id as a *literal*
block-device-mapping value (resolve:ssm is only valid for the top-level image_id),
and Terraform reads it at plan time. So a snapshot the snapshot-builder publishes
to SSM never reaches the running pool on its own: it needs a new launch-template
version *and* an instance refresh. This script, run by the SSM Automation that
EventBridge starts when /devbox/workspace-snapshot/latest changes, does both:

1. read the new snapshot id from SSM (skip unless it is a real snap-... id),
2. clone the launch template's current $Latest, swapping the workspace device's
   snapshot id (inserting the device if the LT predates the first real snapshot),
3. start a rolling ASG instance refresh that skips Claimed (scale-in-protected)
   hosts, so only unclaimed warm hosts roll; Claimed hosts adopt on release.

Idempotent: if $Latest already points at the snapshot it makes no new version and
starts no refresh, and an already-running refresh is reported, not raised.
"""

import boto3
from botocore.exceptions import ClientError


def _workspace_mapping(device, snapshot_id, size, source_ebs):
    """The block-device mapping for the workspace volume on the new LT version.

    Encryption and the CMK are inherited from the snapshot, so they must not be
    set here (EC2 rejects them on a snapshot-backed mapping)."""
    ebs = dict(source_ebs or {})
    ebs.pop("Encrypted", None)
    ebs.pop("KmsKeyId", None)
    ebs["SnapshotId"] = snapshot_id
    ebs["VolumeSize"] = size
    ebs.setdefault("VolumeType", "gp3")
    ebs["DeleteOnTermination"] = True
    return {"DeviceName": device, "Ebs": ebs}


def handler(event, context):
    ec2 = boto3.client("ec2")
    ssm = boto3.client("ssm")
    asg = boto3.client("autoscaling")

    snapshot_id = ssm.get_parameter(Name=event["SnapshotParameter"])["Parameter"][
        "Value"
    ]
    if not snapshot_id.startswith("snap-"):
        return {"status": "skipped", "reason": f"snapshot parameter is {snapshot_id!r}"}

    lt_id = event["LaunchTemplateId"]
    device = event["WorkspaceDevice"]
    size = int(event["WorkspaceVolumeSize"])

    latest = ec2.describe_launch_template_versions(
        LaunchTemplateId=lt_id, Versions=["$Latest"]
    )["LaunchTemplateVersions"][0]["LaunchTemplateData"]
    mappings = latest.get("BlockDeviceMappings", [])

    current = next((m for m in mappings if m.get("DeviceName") == device), None)
    if current and current.get("Ebs", {}).get("SnapshotId") == snapshot_id:
        return {"status": "noop", "reason": "launch template already on this snapshot"}

    # Preserve every other device (e.g. the root volume) verbatim; replace or
    # append the workspace device with the new snapshot.
    new_mappings = [m for m in mappings if m.get("DeviceName") != device]
    new_mappings.append(
        _workspace_mapping(
            device, snapshot_id, size, current.get("Ebs") if current else None
        )
    )

    version = ec2.create_launch_template_version(
        LaunchTemplateId=lt_id,
        SourceVersion="$Latest",
        LaunchTemplateData={"BlockDeviceMappings": new_mappings},
    )["LaunchTemplateVersion"]["VersionNumber"]

    # The ASG references $Latest, so the new version is picked up with no
    # ModifyLaunchTemplate default-version change needed.
    try:
        refresh_id = asg.start_instance_refresh(
            AutoScalingGroupName=event["AsgName"],
            Strategy="Rolling",
            Preferences={
                "MinHealthyPercentage": int(event["MinHealthyPercentage"]),
                "InstanceWarmup": int(event["InstanceWarmup"]),
                "ScaleInProtectedInstances": "Ignore",
                "StandbyInstances": "Ignore",
            },
        )["InstanceRefreshId"]
    except ClientError as e:
        if e.response.get("Error", {}).get("Code") == "InstanceRefreshInProgress":
            return {
                "status": "version-created-refresh-in-progress",
                "version": version,
            }
        raise

    return {"status": "started", "version": version, "instanceRefreshId": refresh_id}
