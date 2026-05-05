#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root: sudo $0 --yes" >&2
	exit 1
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root_dir="$(dirname -- "$script_dir")"
src="${SRC:-/usr/src}"
patch_dir="$root_dir/patches/freebsd-14.3"
patches="
freebsd-14.3-mt76-mt7921u-wip.patch
freebsd-14.3-mt76-usb-reset-hardening.patch
freebsd-14.3-mt76-freebsd-wlan-parent-name.patch
freebsd-14.3-mt76-drop-usb-tx-debug.patch
freebsd-14.3-linuxkpi-active-monitor-wip.patch
freebsd-14.3-linuxkpi-rx-mbuf-length-guard-wip.patch
"
# freebsd-14.3-mt76-tx-status-idr-sentinel.patch is kept for patch-split
# review, but the current monolithic WIP patch already includes it.

patch_strip()
{
	case "$1" in
		freebsd-14.3-mt76-mt7921u-wip.patch)
			echo 1
			;;
		*)
			echo 0
			;;
	esac
}

case "${1:-}" in
	--yes)
		;;
	*)
		echo "This will patch $src and build/install mt76_core + if_mt7921."
		echo "If the running kernel has COMPAT_LINUXKPI built in, a separate"
		echo "kernel build/install/reboot is also required for linux_usb.c."
		echo "Re-run with --yes to continue."
		exit 2
		;;
esac

if [ ! -d "$src/sys/modules/mt76" ]; then
	echo "Missing FreeBSD mt76 source under $src/sys/modules/mt76" >&2
	exit 1
fi

pkg install -y wifi-firmware-mt76-kmod-mt7921

for patch_name in $patches; do
	patch_file="$patch_dir/$patch_name"
	strip="$(patch_strip "$patch_name")"
	if [ ! -r "$patch_file" ]; then
		echo "Missing patch: $patch_file" >&2
		exit 1
	fi
	if patch -d "$src" -p"$strip" --dry-run < "$patch_file" >/tmp/mt7921u-patch-check.log 2>&1; then
		echo "Applying $patch_name"
		patch -d "$src" -p"$strip" < "$patch_file"
	elif patch -d "$src" -p"$strip" -R --dry-run < "$patch_file" >/tmp/mt7921u-patch-check.log 2>&1; then
		echo "Patch already appears to be applied: $patch_name"
	else
		cat /tmp/mt7921u-patch-check.log >&2
		exit 1
	fi
done

make -C "$src/sys/modules/mt76/core" WITH_USB=1 clean all install
make -C "$src/sys/modules/mt76/mt7921" WITH_USB=1 clean all install
kldxref /boot/kernel /boot/modules || true

echo "Built and installed mt76_core and if_mt7921. Load manually with:"
echo "  kldload mt76_core"
echo "  kldload if_mt7921"
if sysctl -n kern.conftxt 2>/dev/null | grep -q 'options[[:space:]]*COMPAT_LINUXKPI'; then
	echo
	echo "This kernel has COMPAT_LINUXKPI built in."
	echo "Because this patch changes LinuxKPI kernel sources, build/reboot a patched"
	echo "kernel before testing mt7921u attach."
	echo
	echo "Do not run installkernel with NO_MODULES=yes on the X201 ZFS-root setup."
	echo "That can leave /boot/kernel without modules needed to boot. Either do a"
	echo "normal full installkernel with modules, or preserve modules with this"
	echo "manual kernel-only swap:"
	echo "  cd $src"
	echo "  make -j1 buildkernel KERNCONF=GENERIC NO_MODULES=yes NO_CLEAN=yes"
	echo "  stamp=\$(date +%Y%m%d-%H%M%S)"
	echo "  cp -p /boot/kernel/kernel /boot/kernel/kernel.before-awus-\${stamp}"
	echo "  install -o root -g wheel -m 555 \\"
	echo "    /usr/obj/usr/src/amd64.amd64/sys/GENERIC/kernel /boot/kernel/kernel"
	echo "  kldxref /boot/kernel /boot/modules"
	echo "  reboot"
fi
echo "Then replug the AWUS036AXML and check:"
echo "  usbconfig list"
echo "  sysctl net.wlan.devices"
echo "  dmesg | tail -80"
