# shellcheck shell=bash
#
# Clone the configured repos source-only onto a freshly formatted workspace data
# volume, then quiesce and unmount so the automation can snapshot a clean
# filesystem. Runs as root via SSM run-command (no shebang: the SSM agent picks
# the interpreter, AL2023 /bin/sh is bash). Inputs arrive as DEVBOX_* env vars set
# by the run-command preamble.
#
# Warm hooks run for any repo that ships an executable .devbox/warm.sh; repos
# without one are cloned source-only, leaving heavy recompilation to the claimant's
# incremental build against the cache dirs seeded here.
set -euo pipefail

MOUNT="${DEVBOX_MOUNT:-/workspace}"
KEYFILE=""
# Must return 0: an EXIT trap whose last command is non-zero makes bash exit
# non-zero even when the script itself succeeded.
cleanup() {
  [ -n "$KEYFILE" ] && rm -f "$KEYFILE"
  return 0
}
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

# Sign a GitHub App JWT (RS256) from the key in $KEYFILE, issuer $DEVBOX_GH_APP_ID.
# Valid ~9 min and signed fresh per repo, so a long clone run can't outlive it.
sign_jwt() {
  local now iat exp header payload signing_input sig
  now="$(date +%s)"
  iat="$((now - 60))"
  exp="$((now + 540))"
  header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
  payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$iat" "$exp" "$DEVBOX_GH_APP_ID" | b64url)"
  signing_input="${header}.${payload}"
  sig="$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$KEYFILE" -binary | b64url)"
  printf '%s.%s' "$signing_input" "$sig"
}

# Parse a git remote URL ($1) into globals R_HOST/R_OWNER/R_REPO; non-zero for a
# remote with no host or no owner/repo path. Handles scheme://host/owner/repo[.git]
# and scp-like user@host:owner/repo[.git].
parse_remote() {
  local url="$1" rest host path
  R_HOST=""
  R_OWNER=""
  R_REPO=""
  case "$url" in
  *://*)
    rest="${url#*://}"
    host="${rest%%/*}"
    path="${rest#*/}"
    ;;
  *@*:*)
    rest="${url#*@}"
    host="${rest%%:*}"
    path="${rest#*:}"
    ;;
  *) return 1 ;;
  esac
  host="${host##*@}" # strip any user@
  host="${host%%:*}" # strip any :port
  case "$path" in */*) : ;; *) return 1 ;; esac
  path="${path%.git}"
  path="${path%/}"
  R_HOST="$host"
  R_OWNER="${path%%/*}"
  R_REPO="${path#*/}"
  R_REPO="${R_REPO%%/*}"
  [ -n "$R_HOST" ] && [ -n "$R_OWNER" ] && [ -n "$R_REPO" ]
}

# Resolve the installation id covering owner ($1) / repo ($2) using JWT ($3).
# Echoes the numeric id, or returns non-zero (e.g. the App isn't installed there).
resolve_installation() {
  local owner="$1" repo="$2" jwt="$3" api_base id
  api_base="${DEVBOX_GH_API_BASE:-https://api.github.com}"
  id="$(curl -fsS \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github+json" \
    "${api_base}/repos/${owner}/${repo}/installation" |
    jq -r '.id')"
  [ -n "$id" ] && [ "$id" != "null" ] || return 1
  printf '%s' "$id"
}

# Mint a 1h read-only installation token for installation id ($1) using JWT ($2).
# Echoes the token, or returns non-zero so the caller clones unauthenticated.
mint_token() {
  local installation_id="$1" jwt="$2" api_base token
  api_base="${DEVBOX_GH_API_BASE:-https://api.github.com}"
  token="$(curl -fsS -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    -d '{"permissions":{"contents":"read","metadata":"read"}}' \
    "${api_base}/app/installations/${installation_id}/access_tokens" |
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

# Optional read-only credentials. With the App key configured, each repo's
# installation is discovered from its own URL and a short-lived token minted per
# repo, so one App clones repos from any org that installed it — there are no
# installation IDs to configure. The key is read once here; tokens are minted in the
# clone loop and only for repos on the App's GitHub host.
GH_CONFIGURED=0
if [ -n "${DEVBOX_GH_KEY_PARAM:-}" ] && [ -n "${DEVBOX_GH_APP_ID:-}" ]; then
  KEYFILE="$(mktemp)"
  aws ssm get-parameter --name "$DEVBOX_GH_KEY_PARAM" --with-decryption \
    --query 'Parameter.Value' --output text >"$KEYFILE"
  GH_CONFIGURED=1
fi

# The git host whose remotes this App serves: public GitHub's API is api.github.com
# but its remotes are github.com; a GHES install shares one host for both.
GH_GIT_HOST="${DEVBOX_GH_API_BASE:-https://api.github.com}"
GH_GIT_HOST="${GH_GIT_HOST#*://}"
GH_GIT_HOST="${GH_GIT_HOST%%/*}"
GH_GIT_HOST="${GH_GIT_HOST%%:*}"
[ "$GH_GIT_HOST" = "api.github.com" ] && GH_GIT_HOST="github.com"

export GIT_TERMINAL_PROMPT=0

# Seed shared on-volume tool-home and cache dirs (must match /etc/environment in
# the AMI) before cloning so warm hooks populate them; they ride the snapshot and
# chown to the claimant with the rest of /workspace.
mkdir -p \
  "${MOUNT}/.cargo" \
  "${MOUNT}/go/bin" \
  "${MOUNT}/.cache/go/mod" \
  "${MOUNT}/.cache/go/build" \
  "${MOUNT}/.cache/uv" \
  "${MOUNT}/.cache/pnpm"

# Make the baked toolchains usable by warm hooks. The SSM run-command shell is
# non-login and sources neither /etc/profile.d nor /etc/environment, so put the
# toolchain on PATH and repoint every build cache at the workspace volume: a hook's
# downloads and build output must ride the snapshot, not the ephemeral root disk.
# shellcheck source=/dev/null
[ -r /etc/profile.d/go.sh ] && . /etc/profile.d/go.sh
# shellcheck source=/dev/null
[ -r /etc/profile.d/rust.sh ] && . /etc/profile.d/rust.sh
export CARGO_HOME="${MOUNT}/.cargo"
export GOPATH="${MOUNT}/go"
export GOMODCACHE="${MOUNT}/.cache/go/mod"
export GOCACHE="${MOUNT}/.cache/go/build"
export UV_CACHE_DIR="${MOUNT}/.cache/uv"
export XDG_CACHE_HOME="${MOUNT}/.cache"

# Clone each repo source-only (blobless partial clone bounds transfer/size). The
# read-only token, if any, is minted per repo from that repo's own installation, so
# repos in different orgs each authenticate against the right installation.
IFS=',' read -ra REPOS <<<"${DEVBOX_REPOS:-}"
for url in "${REPOS[@]}"; do
  url="$(echo "$url" | xargs)"
  [ -n "$url" ] || continue
  name="$(basename "$url" .git)"
  dest="${MOUNT}/${name}"

  GH_TOKEN=""
  git_auth=()
  if [ "$GH_CONFIGURED" = "1" ] && parse_remote "$url" && [ "$R_HOST" = "$GH_GIT_HOST" ]; then
    jwt="$(sign_jwt)"
    if iid="$(resolve_installation "$R_OWNER" "$R_REPO" "$jwt")" &&
      GH_TOKEN="$(mint_token "$iid" "$jwt")"; then
      export GH_TOKEN
      git_auth=(-c "credential.helper=!f() { echo username=x-access-token; echo \"password=\$GH_TOKEN\"; }; f")
      echo "Minted read-only token for ${R_OWNER}/${R_REPO}"
    else
      echo "WARNING: token mint failed for ${R_OWNER}/${R_REPO}; cloning unauthenticated" >&2
      GH_TOKEN=""
    fi
  fi

  echo "Cloning ${url} -> ${dest}"
  git ${git_auth[@]+"${git_auth[@]}"} -c protocol.version=2 \
    clone --filter=blob:none "$url" "$dest"
  if [ -x "${dest}/.devbox/warm.sh" ]; then
    echo "Running warm hook for ${name}"
    (cd "$dest" && timeout 1800 ./.devbox/warm.sh) || echo "WARNING: warm hook failed for ${name}" >&2
  fi
  git -C "$dest" gc --quiet || true
  unset GH_TOKEN
done

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
