# shellcheck shell=bash
#
# Clone the configured repos source-only onto a freshly formatted workspace data
# volume, then quiesce and unmount so the automation can snapshot a clean
# filesystem. Runs as root via SSM run-command (no shebang: the SSM agent picks
# the interpreter, AL2023 /bin/sh is bash). Inputs arrive as DEVBOX_* env vars set
# by the run-command preamble.
#
# Source-only first cut: warm hooks run only when DEVBOX_RUN_WARM_HOOKS=true and a
# repo ships an executable .devbox/warm.sh; heavy recompilation is otherwise left
# to the claimant's incremental build against the cache dirs seeded here.
set -euo pipefail

MOUNT="${DEVBOX_MOUNT:-/workspace}"
KEYFILE=""
cleanup() { [ -n "$KEYFILE" ] && rm -f "$KEYFILE"; }
trap cleanup EXIT

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

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Mint a 1h read-only GitHub App installation token (RS256 JWT -> installation
# access token). Echoes the token, or returns non-zero so the caller clones
# unauthenticated (private repos then simply won't clone).
mint_token() {
  local now iat exp header payload signing_input sig jwt api_base token
  KEYFILE="$(mktemp)"
  aws ssm get-parameter --name "$DEVBOX_GH_KEY_PARAM" --with-decryption \
    --query 'Parameter.Value' --output text >"$KEYFILE"
  now="$(date +%s)"
  iat="$((now - 60))"
  exp="$((now + 540))"
  header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
  payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$iat" "$exp" "$DEVBOX_GH_APP_ID" | b64url)"
  signing_input="${header}.${payload}"
  sig="$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$KEYFILE" -binary | b64url)"
  jwt="${signing_input}.${sig}"
  api_base="${DEVBOX_GH_API_BASE:-https://api.github.com}"
  token="$(curl -fsS -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github+json" \
    "${api_base}/app/installations/${DEVBOX_GH_INSTALLATION_ID}/access_tokens" |
    jq -r '.token')"
  [ -n "$token" ] && [ "$token" != "null" ] || return 1
  printf '%s' "$token"
}

DATA_DEV="$(resolve_data_device)" || {
  echo "ERROR: no blank data disk found to format; refusing to continue" >&2
  exit 1
}
echo "Formatting and mounting data device ${DATA_DEV} at ${MOUNT}"
mkfs.ext4 -F -L workspace "$DATA_DEV"
mkdir -p "$MOUNT"
mount "$DATA_DEV" "$MOUNT"

# Optional read-only credential.
GH_TOKEN=""
git_auth=()
if [ -n "${DEVBOX_GH_KEY_PARAM:-}" ] && [ -n "${DEVBOX_GH_APP_ID:-}" ] && [ -n "${DEVBOX_GH_INSTALLATION_ID:-}" ]; then
  if GH_TOKEN="$(mint_token)"; then
    export GH_TOKEN
    git_auth=(-c "credential.helper=!f() { echo username=x-access-token; echo \"password=\$GH_TOKEN\"; }; f")
    echo "Minted read-only GitHub App installation token"
  else
    echo "WARNING: token mint failed; cloning unauthenticated" >&2
    GH_TOKEN=""
  fi
fi
export GIT_TERMINAL_PROMPT=0

# Clone each repo source-only (blobless partial clone bounds transfer/size).
IFS=',' read -ra REPOS <<<"${DEVBOX_REPOS:-}"
for url in "${REPOS[@]}"; do
  url="$(echo "$url" | xargs)"
  [ -n "$url" ] || continue
  name="$(basename "$url" .git)"
  dest="${MOUNT}/${name}"
  echo "Cloning ${url} -> ${dest}"
  git ${git_auth[@]+"${git_auth[@]}"} -c protocol.version=2 \
    clone --filter=blob:none "$url" "$dest"
  if [ "${DEVBOX_RUN_WARM_HOOKS:-false}" = "true" ] && [ -x "${dest}/.devbox/warm.sh" ]; then
    echo "Running warm hook for ${name}"
    (cd "$dest" && timeout 1800 ./.devbox/warm.sh) || echo "WARNING: warm hook failed for ${name}" >&2
  fi
  git -C "$dest" gc --quiet || true
done

# Seed shared on-volume cache dirs (must match /etc/environment in the AMI). They
# ride the snapshot and chown to the claimant with the rest of /workspace.
mkdir -p \
  "${MOUNT}/.cache/cargo" \
  "${MOUNT}/.cache/go/mod" \
  "${MOUNT}/.cache/go/build" \
  "${MOUNT}/.cache/uv" \
  "${MOUNT}/.cache/pnpm"

# Scrub any credential material before snapshotting; never let a token ride the
# snapshot.
unset GH_TOKEN
find "$MOUNT" -name '.git-credentials' -type f -delete 2>/dev/null || true

# Quiesce: a clean unmount means no dirty journal -> no fsck on first pool mount.
sync
umount "$MOUNT" || {
  echo "ERROR: failed to unmount ${MOUNT}; refusing to snapshot a dirty filesystem" >&2
  exit 1
}
echo "Workspace data volume prepared and unmounted cleanly"
