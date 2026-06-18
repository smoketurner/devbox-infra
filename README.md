# devbox-infra

Terraform infrastructure repository.

## Structure

```
.
├── environments/       # Per-environment Terraform configurations
│   └── dev/
├── modules/            # Reusable Terraform modules
│   └── vpc/
└── README.md
```

## Conventions

- `main.tf` — Resource definitions and module calls
- `variables.tf` — Input variable declarations
- `outputs.tf` — Output value declarations
- `locals.tf` — Local value definitions
- `data.tf` — Data source definitions
- `providers.tf` — Provider configurations
- `versions.tf` — Terraform and provider version constraints

## Usage

Each environment directory contains a full Terraform root module that references
shared modules from the `modules/` directory.

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```
