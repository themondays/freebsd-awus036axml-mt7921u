#!/bin/sh
set -eu

dev="${1:-}"
firmware_dir="${MTKBT_FIRMWARE_DIR:-/usr/local/share/mtkbt-firmware}"
loader="${MTKBTFW:-/usr/local/sbin/mtkbtfw}"

if [ -z "$dev" ]; then
	echo "usage: $0 ubtN" >&2
	exit 2
fi

case "$dev" in
	ubt[0-9]*)
		unit="${dev#ubt}"
		;;
	*)
		echo "unsupported Bluetooth device: $dev" >&2
		exit 2
		;;
esac

pnp="$(sysctl -n "dev.ubt.$unit.%pnpinfo" 2>/dev/null || true)"
case "$pnp" in
	*vendor=0x0e8d*product=0x7961*)
		;;
	*)
		exec service bluetooth quietstart "$dev"
		;;
esac

location="$(sysctl -n "dev.ubt.$unit.%location" 2>/dev/null || true)"
ugen="$(printf '%s\n' "$location" | sed -n 's/.* ugen=\([^ ]*\).*/\1/p')"
if [ -z "$ugen" ]; then
	logger -t awus-mt7921u-bluetooth "cannot find ugen for $dev"
	exit 1
fi

if [ ! -x "$loader" ]; then
	logger -t awus-mt7921u-bluetooth "missing $loader"
	exit 1
fi

if "$loader" -d "$ugen" -f "$firmware_dir"; then
	exec service bluetooth quietstart "$dev"
fi

logger -t awus-mt7921u-bluetooth "firmware load failed for $dev on $ugen"
exit 1
