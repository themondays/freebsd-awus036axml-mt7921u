#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root: sudo $0 [output-dir]" >&2
	exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
out="${1:-/tmp/awus036axml-$stamp}"
mkdir -p "$out"

uname -a > "$out/uname.txt"
ifconfig -a > "$out/ifconfig-a.txt" 2>&1 || true
sysctl net.wlan.devices > "$out/net-wlan-devices.txt" 2>&1 || true
kldstat > "$out/kldstat.txt" 2>&1 || true
pkg info -x 'wifi-firmware|mt76|linux-firmware' > "$out/pkg-firmware.txt" 2>&1 || true
find /boot /usr/local/share /usr/share \
	-name 'WIFI_RAM_CODE_MT7961_1.bin' -o \
	-name 'WIFI_MT7961_patch_mcu_1_2_hdr.bin' \
	> "$out/firmware-files.txt" 2>/dev/null || true

usbconfig list > "$out/usbconfig-list.txt" 2>&1 || true
dmesg > "$out/dmesg.txt" 2>&1 || true
dmesg | egrep -i 'mt76|mt7921|mediatek|wirelessdevice|0e8d|7961|ubt|ugen' \
	> "$out/dmesg-awus-filtered.txt" 2>&1 || true

awk -F: '
	/MediaTek|WirelessDevice|ALFA|0e8d|7961|Bluetooth|WLAN/ {
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1);
		print $1
	}
' "$out/usbconfig-list.txt" | while read -r dev; do
	[ -n "$dev" ] || continue
	safe="$(echo "$dev" | tr '/:' '__')"
	usbconfig -d "$dev" dump_device_desc > "$out/${safe}-device-desc.txt" 2>&1 || true
	usbconfig -d "$dev" dump_all_desc > "$out/${safe}-all-desc.txt" 2>&1 || true
done

echo "$out"
