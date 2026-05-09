#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root: sudo $0 --yes" >&2
	exit 1
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root_dir="$(dirname -- "$script_dir")"
src="${SRC:-/usr/src}"

detect_freebsd_minor()
{
	if [ -r "$src/sys/conf/newvers.sh" ]; then
		awk -F\" '/^REVISION=/{ print $2; exit }' "$src/sys/conf/newvers.sh"
	else
		freebsd-version -u 2>/dev/null |
		    sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' |
		    sed -n '1p'
	fi
}

freebsd_minor="${FREEBSD_MINOR:-$(detect_freebsd_minor)}"
patch_set="${PATCH_SET:-freebsd-$freebsd_minor}"
patch_dir="$root_dir/patches/$patch_set"
patches="
$patch_set-linuxkpi-page-pool-compat.patch
$patch_set-linuxkpi-from-timer-compat.patch
$patch_set-mt76-mt7921u-wip.patch
$patch_set-mt76-usb-device-table-guard.patch
$patch_set-mt76-usb-reset-hardening.patch
$patch_set-mt76-freebsd-wlan-parent-name.patch
$patch_set-mt76-drop-usb-tx-debug.patch
$patch_set-linuxkpi-active-monitor-wip.patch
$patch_set-linuxkpi-deferred-monitor-config-wip.patch
$patch_set-linuxkpi-rx-mbuf-length-guard-wip.patch
$patch_set-linuxkpi-rx-mbuf-chain-sanity-wip.patch
$patch_set-linuxkpi-monitor-radiotap-fanout-wip.patch
$patch_set-linuxkpi-tx-status-info-fallback-wip.patch
"
# The mt76-tx-status-idr-sentinel patch is kept for patch-split review, but the
# current monolithic WIP patch already includes it.

patch_strip()
{
	case "$1" in
		*-mt76-mt7921u-wip.patch)
			echo 1
			;;
		*)
			echo 0
			;;
	esac
}

patch_already_applied()
{
	case "$1" in
		*-mt76-mt7921u-wip.patch)
			grep -q 'MT76U_FBSD_BULK_BUFSIZE' \
			    "$src/sys/contrib/dev/mediatek/mt76/usb.c" &&
			    grep -q 'usb.c' "$src/sys/modules/mt76/mt7921/Makefile"
			;;
		*-linuxkpi-page-pool-compat.patch)
			test -r "$src/sys/compat/linuxkpi/common/include/net/page_pool.h"
			;;
		*-linuxkpi-from-timer-compat.patch)
			grep -q 'drivers using from_timer' \
			    "$src/sys/compat/linuxkpi/common/include/linux/timer.h"
			;;
		*-mt76-usb-reset-hardening.patch)
			grep -q 'mt76u_fbsd_usb_control_removed_error' \
			    "$src/sys/contrib/dev/mediatek/mt76/usb.c"
			;;
		*-mt76-usb-device-table-guard.patch)
			grep -q 'MODULE_DEVICE_TABLE_BUS_usb' \
			    "$src/sys/contrib/dev/mediatek/mt76/mt7921/usb.c"
			;;
		*-mt76-freebsd-wlan-parent-name.patch)
			grep -q 'fbsd_wlan_name' \
			    "$src/sys/contrib/dev/mediatek/mt76/mt76.h" &&
			    grep -q 'linuxkpi_set_ieee80211_dev' \
			    "$src/sys/contrib/dev/mediatek/mt76/mac80211.c" &&
			    grep -Fq 'linuxkpi_set_ieee80211_dev(struct ieee80211_hw *, const char *)' \
			    "$src/sys/compat/linuxkpi/common/include/net/mac80211.h"
			;;
		*-mt76-drop-usb-tx-debug.patch)
			! grep -q 'fbsd_usb_tx_log_count' \
			    "$src/sys/contrib/dev/mediatek/mt76/usb.c" &&
			    ! grep -q 'fbsd_tx_log_count' \
			    "$src/sys/contrib/dev/mediatek/mt76/mt792x_core.c"
			;;
		*-linuxkpi-active-monitor-wip.patch)
			grep -q 'lkpi_lhw_has_running_monitor_vif' \
			    "$src/sys/compat/linuxkpi/common/src/linux_80211.c"
			;;
		*-linuxkpi-deferred-monitor-config-wip.patch)
			grep -q 'monitor config; mt7921 sniffer MCU commands may sleep' \
			    "$src/sys/compat/linuxkpi/common/src/linux_80211.h" &&
			    grep -q 'lkpi_hw_monitor_task' \
			    "$src/sys/compat/linuxkpi/common/src/linux_80211.c"
			;;
		*-linuxkpi-rx-mbuf-length-guard-wip.patch)
			grep -q 'mbuf chain length' \
			    "$src/sys/compat/linuxkpi/common/src/linux_80211.c"
			;;
		*-linuxkpi-rx-mbuf-chain-sanity-wip.patch)
			grep -q 'lkpi_mbuf_rx_chain_sane' \
			    "$src/sys/compat/linuxkpi/common/src/linux_80211.c"
			;;
		*-linuxkpi-monitor-radiotap-fanout-wip.patch)
			grep -q 'bypass net80211 all-VAP fanout' \
			    "$src/sys/compat/linuxkpi/common/src/linux_80211.c"
			;;
		*-linuxkpi-tx-status-info-fallback-wip.patch)
			grep -q 'txstat->info unset' \
			    "$src/sys/compat/linuxkpi/common/src/linux_80211.c"
			;;
		*)
			return 1
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

if [ ! -d "$patch_dir" ]; then
	echo "Missing patch set: $patch_dir" >&2
	echo "Set FREEBSD_MINOR=14.3 or FREEBSD_MINOR=14.4 if auto-detection is wrong." >&2
	exit 1
fi

echo "Using patch set $patch_set for source tree $src"

pkg install -y wifi-firmware-mt76-kmod-mt7921

for patch_name in $patches; do
	patch_file="$patch_dir/$patch_name"
	strip="$(patch_strip "$patch_name")"
	if [ ! -r "$patch_file" ]; then
		case "$patch_name" in
			*-linuxkpi-page-pool-compat.patch|*-linuxkpi-from-timer-compat.patch|*-mt76-usb-device-table-guard.patch)
				continue
				;;
			*)
				echo "Missing patch: $patch_file" >&2
				exit 1
				;;
		esac
	fi
	if patch_already_applied "$patch_name"; then
		echo "Patch already appears to be applied: $patch_name"
		continue
	fi
	if patch -d "$src" -p"$strip" -C -t < "$patch_file" >/tmp/mt7921u-patch-check.log 2>&1; then
		if grep -q 'Reversed (or previously applied)' /tmp/mt7921u-patch-check.log ||
		    grep -q 'Assuming -R' /tmp/mt7921u-patch-check.log; then
			echo "Patch dry-run reports reversed or already applied: $patch_name"
			continue
		fi
		echo "Applying $patch_name"
		patch -d "$src" -p"$strip" -t < "$patch_file"
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
