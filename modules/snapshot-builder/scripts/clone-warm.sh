# shellcheck shell=bash
#
# Prepare the workspace data volume for snapshotting: format and mount the blank
# data disk, seed the shared on-volume tool-home/cache dirs, then hand cloning off
# to devbox-agent (baked into the golden AMI). The agent mints per-repo read-only
# GitHub App installation tokens, clones source-only, and runs any executable
# .devbox/warm.sh hook — one tested implementation instead of a bash reimplementation.
# Finally quiesce and unmount so the automation can snapshot a clean filesystem.
#
# Runs as root via SSM run-command (no shebang: the SSM agent picks the interpreter,
# AL2023 /bin/sh is bash). Inputs arrive as DEVBOX_* env vars set by the run-command
# preamble; the agent reads DEVBOX_SERVER_URL itself to request tokens.
set -euo pipefail

MOUNT="${DEVBOX_MOUNT:-/workspace}"

# Resolve the data device without guessing: it is the one whole disk that is
# neither the (mounted) root disk nor carries any mountpoint. Refuse to proceed
# otherwise — formatting the root disk would be catastrophic.
resolve_data_device() {
  local root_src root_disk dev
  root_src="$(findmnt -no SOURCE /)"
  root_disk="$(lsblk -no PKNAME "$root_src" 2>/dev/null || true)"
  for dev in $(lsblk -dn -o NAME,TYPE | awk '$2 == "disk" { print $1 }'); do
    [ "$dev" = "$root_disk" ] && continue
    if lsblk -no MOUNTPOINT "/dev/$dev" | grep -q .; then continue; fi
    printf '/dev/%s' "$dev"
    return 0
  done
  return 1
}

DATA_DEV="$(resolve_data_device)" || {
  echo "ERROR: no blank data disk found to format; refusing to continue" >&2
  exit 1
}
echo "Formatting and mounting data device ${DATA_DEV} at ${MOUNT}"
mkfs.ext4 -F -L workspace "$DATA_DEV"
mkdir -p "$MOUNT"
# noatime to match the pool's workspace.mount and cut atime writes during the
# checkout/warm build (cargo target, node_modules, git object stores).
mount -o noatime "$DATA_DEV" "$MOUNT"

# Seed shared on-volume tool-home and cache dirs (must match /etc/environment in
# the AMI) before cloning so warm hooks populate them; they ride the snapshot and
# chown to the claimant with the rest of /workspace.
mkdir -p \
  "${MOUNT}/.rustup" \
  "${MOUNT}/.cargo" \
  "${MOUNT}/go/bin" \
  "${MOUNT}/.cache/go/mod" \
  "${MOUNT}/.cache/go/build" \
  "${MOUNT}/.cache/uv" \
  "${MOUNT}/.cache/pnpm"

# Make the baked toolchains usable by warm hooks. The SSM run-command shell is
# non-login and sources neither /etc/profile.d nor /etc/environment, so put the
# toolchain on PATH and repoint every tool home / build cache at the workspace
# volume: a hook's toolchains, downloads, and build output must ride the snapshot,
# not the ephemeral root disk. RUSTUP_HOME on the volume also lets warm hooks
# install each repo's pinned toolchain (rust-toolchain.toml) into the snapshot.
# devbox-agent inherits this environment and passes it through to each warm hook.
# shellcheck source=/dev/null
[ -r /etc/profile.d/go.sh ] && . /etc/profile.d/go.sh
# shellcheck source=/dev/null
[ -r /etc/profile.d/rust.sh ] && . /etc/profile.d/rust.sh
export RUSTUP_HOME="${MOUNT}/.rustup"
export CARGO_HOME="${MOUNT}/.cargo"
export GOPATH="${MOUNT}/go"
export GOMODCACHE="${MOUNT}/.cache/go/mod"
export GOCACHE="${MOUNT}/.cache/go/build"
export UV_CACHE_DIR="${MOUNT}/.cache/uv"
export XDG_CACHE_HOME="${MOUNT}/.cache"

# Seed the default stable toolchain onto the volume so repos that do not pin a
# toolchain build, and editors (rust-analyzer) work, on the claimant's box. Pinned
# toolchains are installed automatically when a repo's warm hook runs cargo under
# its rust-toolchain.toml.
rustup toolchain install stable --profile default --component clippy rustfmt rust-analyzer
rustup default stable

# Delegate cloning and warm-hook execution to the agent baked into the golden AMI.
# It requests a per-repo read-only token from the control plane (DEVBOX_SERVER_URL),
# authenticated by this instance's AWS identity, and never writes credentials to disk.
# Absolute path: the non-login SSM shell may not have /usr/local/sbin on PATH. Repos
# are passed as space-separated positional args.
IFS=',' read -ra REPOS <<<"${DEVBOX_REPOS:-}"
/usr/local/sbin/devbox-agent checkout --workspace "$MOUNT" "${REPOS[@]}"

# Quiesce: a clean unmount means no dirty journal -> no fsck on first pool mount.
sync
umount "$MOUNT" || {
  echo "ERROR: failed to unmount ${MOUNT}; refusing to snapshot a dirty filesystem" >&2
  exit 1
}
echo "Workspace data volume prepared and unmounted cleanly"
