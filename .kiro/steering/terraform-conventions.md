# Terraform Conventions

## File Organization

| File | Contents |
|------|----------|
| `main.tf` | Primary resources |
| `variables.tf` | Input variable declarations |
| `outputs.tf` | Output value declarations |
| `locals.tf` | Local value definitions |
| `versions.tf` | Terraform and provider version constraints |
| `data.tf` | All `data` sources (lookups, policy documents, SSM parameters, etc.) |
| `iam.tf` | IAM roles, instance profiles, policy attachments (resources only — policy documents go in `data.tf`) |
| `networking.tf` | Security groups, VPC rules |
| `notifications.tf` | SNS, EventBridge, CloudWatch |

## Data Sources

- ALL `data` blocks MUST live in `data.tf` — never inline in resource files
- AWS managed IAM policies should be looked up via `data "aws_iam_policy"` by name, not hardcoded ARN strings
- Use `data "aws_partition"`, `data "aws_region"`, `data "aws_caller_identity"` for partition-aware ARN construction

## Naming

- Resource names use `local.name_prefix` (e.g., `"${local.name_prefix}-instance"`)
- Use descriptive resource labels (e.g., `aws_iam_role.build_instance`, not `aws_iam_role.this`)

## Tags

- All taggable resources receive `local.tags` (merged from `var.tags` + module-internal tags)
- Security groups and similar get an additional `Name` tag
