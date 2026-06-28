# shellcheck shell=bash
# Test-stage exercise of the real /workspace mount and warm-up against the booted
# AMI. Resolves the workspace snapshot, creates + attaches it as a volume, mounts it
# by filesystem label, then restarts devbox-warmup and asserts it reaches active.
#
# Injected into 04-devbox's test phase via templatefile/indent (no runtime S3
# dependency). Reads one value from the environment, set by the calling step:
#   DEVBOX_WORKSPACE_SNAPSHOT_PARAM - SSM parameter name holding the snapshot id
# Self-skips until a real snapshot exists, so it is a no-op on a bootstrap build.
set -eu

snap=$(aws ssm get-parameter --name "${DEVBOX_WORKSPACE_SNAPSHOT_PARAM}" --query 'Parameter.Value' --output text)
echo "workspace snapshot param = ${snap}"
case "${snap}" in
snap-*) : ;;
*)
  echo "no real workspace snapshot yet (${snap}); skipping mount/warmup test"
  exit 0
  ;;
esac

imds() {
  token=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
  curl -fsS -H "X-aws-ec2-metadata-token: ${token}" "http://169.254.169.254/latest/meta-data/$1"
}

# create-volume and attach are eventually consistent: right after the API call,
# describe-volumes can briefly return InvalidVolume.NotFound or lag the real state,
# which makes `aws ec2 wait` fail hard. Poll ourselves, tolerating transient errors,
# until the volume reports the wanted state.
wait_volume_state() {
  want=$1
  for _ in $(seq 1 60); do
    state=$(aws ec2 describe-volumes --volume-ids "${vol}" --region "${region}" --query 'Volumes[0].State' --output text 2>/dev/null || true)
    [ "${state}" = "${want}" ] && return 0
    sleep 2
  done
  echo "volume ${vol} did not reach ${want} (last state=${state:-none})"
  return 1
}
iid=$(imds instance-id)
az=$(imds placement/availability-zone)
region=$(imds placement/region)
echo "instance=${iid} az=${az} region=${region}"

vol=$(aws ec2 create-volume --availability-zone "${az}" --snapshot-id "${snap}" --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=devbox:role,Value=workspace-test}]' \
  --query VolumeId --output text --region "${region}")
echo "created volume ${vol}"
# Reap the volume if anything below fails before delete-on-termination is set.
trap 'aws ec2 detach-volume --volume-id "${vol}" --region "${region}" >/dev/null 2>&1 || true; aws ec2 delete-volume --volume-id "${vol}" --region "${region}" >/dev/null 2>&1 || true' EXIT

wait_volume_state available
aws ec2 attach-volume --volume-id "${vol}" --instance-id "${iid}" --device /dev/sdf --region "${region}" >/dev/null
wait_volume_state in-use
# Once attached, let Image Builder's test-instance teardown reap the volume.
aws ec2 modify-instance-attribute --instance-id "${iid}" --region "${region}" \
  --block-device-mappings '[{"DeviceName":"/dev/sdf","Ebs":{"DeleteOnTermination":true}}]'

udevadm settle
i=0
while [ ! -e /dev/disk/by-label/workspace ] && [ "${i}" -lt 30 ]; do
  sleep 1
  i=$((i + 1))
done

systemctl restart workspace.mount
systemctl is-active workspace.mount
mountpoint /workspace
echo "workspace volume mounted from ${snap}"

systemctl reset-failed devbox-warmup.service || true
systemctl restart devbox-warmup.service
if ! systemctl is-active devbox-warmup.service; then
  journalctl -u devbox-warmup.service --no-pager | tail -n 50
  exit 1
fi
echo "devbox-warmup reached active on the AMI"

systemctl stop workspace.mount || true
echo "workspace mount + warmup test complete"
