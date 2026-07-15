# CLAUDE.md

Terraform for the **devbox** platform. `README.md` has the full architecture; this file
is the working context for making changes here.

## Repo relationship

The application code lives in the sibling repo `smoketurner/devbox`, checked out as
`../devbox` — a Rust Cargo workspace under `../devbox/crates/` (`devbox-cli`,
`devbox-agent`, `devbox-server`). This repo only provisions AWS infra and **consumes**
devbox build artifacts: the `devbox-agent` binary via GitHub Releases, the
`devbox-server` image via ECR. It does not build them. When a task spans both, the Rust
source is in `../devbox/crates/`.

## The SSM-parameter handoff

Components are chained through SSM Parameter Store, not direct Terraform references:

- `/devbox/ami/latest` — `image-builder` publishes; `snapshot-builder` and `pool` resolve.
- `/devbox/workspace-snapshot/latest` — `snapshot-builder` publishes; `pool` resolves
  (seeded `none` until the first real snapshot; pool gates volume attachment on it).

`pool` resolves both at launch via `resolve:ssm:...`; `snapshot-builder` resolves the AMI
in its SSM Automation. So a new AMI or snapshot rolls out on the next launch/build — not
on `terraform apply`. Never hardcode AMI or snapshot ids; always go through these params.

## Agent-contract ordering gate (read before changing the agent contract)

`image-builder`, `snapshot-builder/scripts/clone-warm.sh`, and the on-box systemd units
all call `devbox-agent` subcommands (`checkout`, `warmup`, `owner-sync`, `principals`)
and rely on the `DEVBOX_*` env vars it reads. The agent binary reaches running
infra only through a new golden AMI. So when an infra change depends on **new** agent
behavior:

1. Merge the agent change in `../devbox`; `release.yml` (on a `v*` tag) publishes the binary.
2. Run the `image-builder` pipeline; `/devbox/ami/latest` updates to an AMI with the new binary.
3. Only then land the infra change.

Flipping infra first breaks the next build/boot (new subcommand → `command not found`;
renamed env var → silently unauthenticated). The env vars the agent reads are defined in
`../devbox/crates/devbox-agent/src/control_plane.rs` (`DEVBOX_SERVER_URL`) and
`../devbox/crates/devbox-agent/src/git.rs` (`DEVBOX_GITHUB_TOKEN`).

## Conventions

- Standard Terraform file split per module: `main.tf`, `variables.tf`, `outputs.tf`,
  `data.tf`, `locals.tf`, `iam.tf`, `versions.tf`.
- Per-environment roots under `environments/` (only `dev` today) reference `modules/`.
  State is in S3 (see `environments/dev/versions.tf`).
- Use the `Makefile` — targets assume `AWS_PROFILE=dev-admin`, default `ENV=dev`:
  `make fmt`, `make validate` (= fmt + validate), `make plan`, `make apply`.
- Shell scripts under `modules/*/scripts/` run via SSM run-command with no shebang
  (AL2023 `/bin/sh` is bash). Lint with `shellcheck` and `shfmt -i 2 -d` before committing.
- SSM Command documents whose name embeds `sha256(script)` (e.g. snapshot-builder's
  clone-warm doc) are replaced when the script changes — expected; the automation
  references them by `.name`, so it re-points automatically.

## Don't

- Don't run Terraform that mutates AWS (`make apply`, `make plan` against live state, SSM
  run-command) without explicit confirmation — the dev-admin session is read-only by
  default; the human runs applies.
- Don't add backward-compat shims for the agent contract. The binary and infra ship
  together through the ordering gate above; replace, don't dual-path.
