#!/bin/bash
# Size the Nitro Enclaves allocator pool for Nitro Sandboxes from this
# host's resources. Sandbox memory is never overcommitted and pinned
# vCPUs come out of this pool, so whatever is reserved here is taken
# from the claimant's own session. Defaults: half the vCPUs (at least
# 1, as AWS requires on a 2-vCPU Graviton host) and a quarter of RAM.
# Override via /etc/devbox/nitro-sandbox.env:
#   DEVBOX_SANDBOX_CPU_PERCENT, DEVBOX_SANDBOX_MEMORY_PERCENT
set -euo pipefail
if [ -r /etc/devbox/nitro-sandbox.env ]; then
  # shellcheck disable=SC1091
  . /etc/devbox/nitro-sandbox.env
fi
cpu_percent="${DEVBOX_SANDBOX_CPU_PERCENT:-50}"
mem_percent="${DEVBOX_SANDBOX_MEMORY_PERCENT:-25}"
vcpus="$(nproc --all)"
mem_mib="$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)"
cpu_count=$((vcpus * cpu_percent / 100))
if [ "$cpu_count" -lt 1 ]; then cpu_count=1; fi
if [ "$cpu_count" -ge "$vcpus" ]; then cpu_count=$((vcpus - 1)); fi
memory_mib=$((mem_mib * mem_percent / 100))
if [ "$memory_mib" -lt 512 ]; then memory_mib=512; fi
install -d -m 0755 /etc/nitro_enclaves
printf -- '---\nmemory_mib: %s\ncpu_count: %s\n' "$memory_mib" "$cpu_count" \
  >/etc/nitro_enclaves/allocator.yaml
echo "nitro sandbox pool: cpu_count=${cpu_count}/${vcpus} memory_mib=${memory_mib}/${mem_mib}"
