#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root: sudo $0 --yes" >&2
	exit 1
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root_dir="$(dirname -- "$script_dir")"
firmware_dir="${MTKBT_FIRMWARE_DIR:-/usr/local/share/mtkbt-firmware}"
firmware_url="${MTKBT_FIRMWARE_URL:-https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin}"
fetch_firmware=0
enable_devd_loader=0

usage()
{
	cat >&2 <<EOF
usage: sudo $0 --yes [--fetch-firmware] [--enable-devd-loader]

Installs the experimental MT7921U Bluetooth firmware loader and devd hook.
Firmware is not stored in this repository; use --fetch-firmware to download
BT_RAM_CODE_MT7961_1_2_hdr.bin from linux-firmware.

By default the devd hook only suppresses the stock early ubt0 start. Use
--enable-devd-loader after manual firmware-load testing succeeds on the host.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--yes)
			;;
		--fetch-firmware)
			fetch_firmware=1
			;;
		--enable-devd-loader)
			enable_devd_loader=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			usage
			exit 2
			;;
	esac
	shift
done

mkdir -p /usr/local/sbin /usr/local/etc/devd "$firmware_dir"

cc -O2 -Wall -Wextra -o /usr/local/sbin/mtkbtfw \
	"$root_dir/tools/mtkbtfw/mtkbtfw.c" -lusb
install -o root -g wheel -m 755 \
	"$root_dir/scripts/awus-mt7921u-bluetooth-start.sh" \
	/usr/local/sbin/awus-mt7921u-bluetooth-start

if [ "$enable_devd_loader" -eq 1 ]; then
	cat >/usr/local/etc/devd/awus-mt7921u-bluetooth.conf <<'EOF'
# Start MT7921U Bluetooth only after the MediaTek firmware loader succeeds.
# This higher-priority rule overrides /etc/devd/bluetooth.conf for 0e8d:7961.
attach 200 {
	device-name "ubt[0-9]+";
	match "vendor" "0x0e8d";
	match "product" "0x7961";
	action "/usr/local/sbin/awus-mt7921u-bluetooth-start $device-name";
};
EOF
else
	cat >/usr/local/etc/devd/awus-mt7921u-bluetooth.conf <<'EOF'
# Suppress the stock early ubt0 start for MT7921U Bluetooth until the
# experimental MediaTek firmware loader is enabled on this host.
attach 200 {
	device-name "ubt[0-9]+";
	match "vendor" "0x0e8d";
	match "product" "0x7961";
	action "logger -t awus-mt7921u-bluetooth 'skipping generic Bluetooth start for $device-name; run mtkbtfw manually first'";
};
EOF
fi

if [ "$fetch_firmware" -eq 1 ]; then
	if command -v fetch >/dev/null 2>&1; then
		fetch -o "$firmware_dir/BT_RAM_CODE_MT7961_1_2_hdr.bin" \
			"$firmware_url"
	else
		curl -L -o "$firmware_dir/BT_RAM_CODE_MT7961_1_2_hdr.bin" \
			"$firmware_url"
	fi
	chmod 644 "$firmware_dir/BT_RAM_CODE_MT7961_1_2_hdr.bin"
fi

service devd restart

cat <<EOF
Installed /usr/local/sbin/mtkbtfw
Installed /usr/local/sbin/awus-mt7921u-bluetooth-start
Installed /usr/local/etc/devd/awus-mt7921u-bluetooth.conf

Manual test:
  sudo /usr/local/sbin/awus-mt7921u-bluetooth-start ubt0
EOF
