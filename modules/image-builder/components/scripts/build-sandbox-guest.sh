#!/bin/bash
# Build the Nitro Sandbox guest image under /opt/devbox/sandbox on this build
# instance:
#   vmlinuz      the kernel this AMI boots (AWS boots the guest on the parent's
#                own AL2023 kernel, an EFI-stub image)
#   initrd.img   a dracut initramfs for that kernel. kernel6.18 builds the
#                drivers the guest needs as modules, so the initramfs loads them
#                before the root drive mounts. Its systemd module runs
#                systemd-volatile-root for systemd.volatile=overlay.
#   rootfs.ext4  an Amazon Linux 2023 root from dnf packages. The guest boots it
#                read-only (systemd.volatile=overlay gives it a writable tmpfs
#                layer) and runs `devbox-agent guest` from devbox-guest.service.
#
# Inputs (environment):
#   GUEST_PACKAGES      dnf packages for the guest, space-separated
#   GUEST_NPM_PACKAGES  npm packages installed globally in the guest (harness CLIs)
#   GUEST_UNIT          path of the devbox-guest.service to install
set -euo pipefail

out_dir=/opt/devbox/sandbox
# Drivers the guest needs before its root drive mounts: virtio-PCI for every
# device, virtio-blk + ext4 for the root and workspace drives, overlay for the
# volatile root, the vsock transport for the host relay, and nsm. Forced, so
# they load even when the initramfs's udev doesn't ask for them.
guest_drivers="virtio_pci virtio_blk ext4 overlay vmw_vsock_virtio_transport nsm"

kernel="$(grubby --default-kernel)"
kver="${kernel#/boot/vmlinuz-}"
install -d -m 0755 "$out_dir"
install -m 0644 "$kernel" "$out_dir/vmlinuz"
dracut --force --no-hostonly --no-hostonly-cmdline --reproducible \
  --force-drivers "$guest_drivers" --kver "$kver" "$out_dir/initrd.img"
echo "sandbox guest kernel: $kver"

root="$(mktemp -d /var/tmp/sandbox-guest.XXXXXX)"
trap 'rm -rf "$root"' EXIT

# shellcheck disable=SC2086 # the package list is meant to split into words
dnf --installroot="$root" --releasever=2023 --setopt=install_weak_deps=False \
  --setopt=tsflags=nodocs -y install $GUEST_PACKAGES
dnf --installroot="$root" clean all

if [ -n "${GUEST_NPM_PACKAGES:-}" ]; then
  # shellcheck disable=SC2086 # the package list is meant to split into words
  npm install --global --prefix "$root/usr/local" --no-fund --no-audit $GUEST_NPM_PACKAGES
fi

# The same verified devbox-agent the host runs (installed by 04-devbox).
install -D -m 0755 /usr/local/sbin/devbox-agent "$root/usr/local/sbin/devbox-agent"
install -D -m 0644 "$GUEST_UNIT" "$root/etc/systemd/system/devbox-guest.service"
systemctl --root="$root" enable devbox-guest.service
# The serial console is the host's log of the guest, not a login prompt.
systemctl --root="$root" mask serial-getty@ttyS0.service getty@tty1.service
mkdir -p "$root/workspace" "$root/etc/devbox/harnesses"

# Fail the build now, not at a sub-agent's first boot, if the guest can't run
# what the init needs.
for tool in git node; do
  chroot "$root" /usr/bin/env "$tool" --version >/dev/null 2>&1 ||
    chroot "$root" /usr/bin/env "$tool" -V >/dev/null 2>&1 || {
    echo "guest is missing a working $tool" >&2
    exit 1
  }
done

size_mib="$(($(du -sm "$root" | cut -f1) + 512))"
mkfs.ext4 -q -F -L sbroot -d "$root" "$out_dir/rootfs.ext4.tmp" "${size_mib}M"
mv "$out_dir/rootfs.ext4.tmp" "$out_dir/rootfs.ext4"
echo "sandbox guest rootfs: $out_dir/rootfs.ext4 (${size_mib} MiB)"
