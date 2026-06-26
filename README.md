# devbox-infra

Terraform for the **devbox** platform: pre-warmed cloud dev boxes claimed through a
control plane. This repo provisions the AWS infrastructure. The application code it
runs lives in the sibling repo
[`smoketurner/devbox`](https://github.com/smoketurner/devbox), checked out alongside
this one as `../devbox`.

## Relationship to `smoketurner/devbox`

`smoketurner/devbox` is a Rust Cargo workspace (`../devbox/crates/`) that produces
three binaries:

| Crate          | Binary         | Role                                              |
| -------------- | -------------- | ------------------------------------------------- |
| `devbox-cli`   | `devbox`       | user-facing CLI (claim/connect to a box)          |
| `devbox-agent` | `devbox-agent` | on-host agent baked into the golden AMI           |
| `devbox-server`| `devbox-server`| the control-plane service                         |

This repo **consumes** those build artifacts; it does not build them:

- **`release.yml`** (on `v*` tags) publishes the `devbox-agent` binary to GitHub
  Releases (`devbox-agent-{aarch64,x86_64}-unknown-linux-musl` + `SHA256SUMS`).
  `image-builder` downloads the arm64 binary and bakes it into the golden AMI
  (`var.devbox_agent_url`, default the `latest` release; pin with `var.devbox_agent_sha256`).
- **`deploy.yml`** (on push to `main`) builds the `devbox-server` container image and
  pushes it to the ECR repo created by `control-plane`, which then rolls the ECS service.

## Build pipeline

The two builders are chained through SSM Parameter Store: each publishes the id of
what it produced, and the next stage resolves it. Nothing is hardcoded.

```
  smoketurner/devbox              devbox-infra (this repo)
  ──────────────────              ────────────────────────

  release.yml
   └─ devbox-agent ──────▶ image-builder ──[/devbox/ami/latest]──────────┐
       (GitHub Release)     (golden AMI)                                  │
                                  │                                       ├─▶ pool ──▶ running
                                  ▼ AMI                                   │   (warm     dev box
                           snapshot-builder ─[/devbox/workspace-snapshot/─┘    ASG)
                           (warm /workspace)  latest]

  deploy.yml
   └─ devbox-server ─▶ ECR ─▶ control-plane (ECS) ──▶ sets pool desired capacity
```

| SSM parameter                        | Producer         | Consumers                |
| ------------------------------------ | ---------------- | ------------------------ |
| `/devbox/ami/latest`                 | image-builder    | snapshot-builder, pool   |
| `/devbox/workspace-snapshot/latest`  | snapshot-builder | pool                     |

## Modules

### `image-builder` — the golden AMI

An EC2 Image Builder pipeline on Amazon Linux 2023 (arm64/Graviton). Components install
the toolchains (Go, Rust, Node 22, Python, uv, Docker), pre-pull container images,
download `devbox-agent` to `/usr/local/sbin/devbox-agent`, and install the systemd units
and SSH config that drive the agent on a running box:

- `devbox-warmup.service` → `devbox-agent warmup` (freshen `/workspace`, self-tag `devbox:ready=true`)
- `devbox-owner-sync.service` → `devbox-agent owner-sync` (provision the claimant's login account)
- SSHD `AuthorizedPrincipalsCommand` → `devbox-agent principals %u` (per-claim auth against Vouch CA certs)

Publishes the resulting AMI id to `/devbox/ami/latest`.

### `snapshot-builder` — the warm workspace snapshot

Launches a throwaway builder from the golden AMI, formats a data volume, and runs
`devbox-agent checkout` (see `scripts/clone-warm.sh`) to clone the configured repos
source-only into `/workspace` and run each repo's `.devbox/warm.sh` hook — seeding the
toolchain caches so a fresh box starts warm. Snapshots the volume and publishes the
snapshot id to `/devbox/workspace-snapshot/latest`. Runs on a schedule.

### `pool` — the warm fleet

An Auto Scaling Group whose launch template resolves the golden AMI
(`resolve:ssm:/devbox/ami/latest`) and attaches the latest workspace snapshot as
`/workspace`. Instances run the baked agent (warmup → `devbox:ready=true`). The control
plane sets desired capacity.

### `control-plane` — orchestration

An ECS Fargate service running `devbox-server` from ECR, behind an NLB with TLS. Handles
auth (Vouch OIDC), claims, and reconciles the pool ASG desired capacity.

### `vpc` — networking

The shared VPC, subnets, and routing the other modules build on.

## The agent contract (important when changing it)

`image-builder`, `snapshot-builder/scripts/clone-warm.sh`, and the on-box systemd units
all call `devbox-agent` subcommands and rely on the `DEVBOX_GITHUB_*` env vars the agent
reads. A new agent binary reaches running infra **only through a new golden AMI**, so a
change in `../devbox` that infra depends on must roll out in order:

1. Merge the agent change in `smoketurner/devbox` → `release.yml` publishes the binary.
2. Run the `image-builder` pipeline → `/devbox/ami/latest` updates to an AMI with it.
3. Only then land the infra change.

Landing infra first breaks the next build/boot (a new subcommand is `command not found`;
a renamed env var silently disables auth). See `CLAUDE.md`.

## Layout

```
.
├── environments/        # Per-environment Terraform roots (reference modules/)
│   └── dev/
├── modules/
│   ├── image-builder/   # golden AMI (EC2 Image Builder)
│   ├── snapshot-builder/# warm /workspace EBS snapshot
│   ├── pool/            # warm-box Auto Scaling Group
│   ├── control-plane/   # devbox-server on ECS Fargate
│   └── vpc/             # shared networking
├── Makefile
└── README.md
```

## Conventions

- Standard Terraform file split per module: `main.tf`, `variables.tf`, `outputs.tf`,
  `locals.tf`, `data.tf`, `iam.tf`, `versions.tf`, etc.
- Shell scripts under `modules/*/scripts/` run via SSM run-command with no shebang
  (AL2023 `/bin/sh` is bash). Lint with `shellcheck` and `shfmt -i 2`.

## Usage

Each environment root references the shared `modules/`. The `Makefile` wraps the common
Terraform commands; its targets assume `AWS_PROFILE=dev-admin` and default to `ENV=dev`.

```bash
make fmt        # terraform fmt -recursive
make validate   # fmt + terraform validate
make plan
make apply
```
