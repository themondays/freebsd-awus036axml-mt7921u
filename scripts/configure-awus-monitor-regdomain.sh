#!/bin/sh
set -eu

parent=""
iface="wlan2"
channel="157"
country="AU"
regdomain=""
assume_yes="no"
list_only="no"

usage()
{
	cat <<EOF
Usage: sudo $0 --yes [--parent mt7921u1] [--iface wlan2] [--country AU] [--channel 157]
       sudo $0 --yes --regdomain DEBUG [--iface wlan2] [--channel 157]

Configures an AWUS036AXML/mt7921u monitor VAP for Kismet channel hopping.
With the AU regdomain patch installed, country AU exposes the native Australian
RLAN monitor channel set. Use --regdomain DEBUG only as a broad capture fallback.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--yes)
			assume_yes="yes"
			;;
		--parent)
			parent="${2:?missing --parent value}"
			shift
			;;
		--iface)
			iface="${2:?missing --iface value}"
			shift
			;;
		--channel)
			channel="${2:?missing --channel value}"
			shift
			;;
		--regdomain)
			regdomain="${2:?missing --regdomain value}"
			shift
			;;
		--country)
			country="${2:?missing --country value}"
			shift
			;;
		--list-only)
			list_only="yes"
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			usage >&2
			exit 2
			;;
	esac
	shift
done

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root: sudo $0 --yes" >&2
	exit 1
fi

if [ -z "$parent" ]; then
	parent="$(sysctl -n net.wlan.devices 2>/dev/null |
	    awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^mt7921u[0-9]+$/) { print $i; exit } }')"
fi

if [ -z "$parent" ]; then
	echo "No mt7921u parent found in net.wlan.devices." >&2
	exit 1
fi

if [ "$assume_yes" != "yes" ] && [ "$list_only" != "yes" ]; then
	echo "This will down all wlan VAPs on $parent, create/configure $iface,"
	if [ -n "$regdomain" ]; then
		echo "set regdomain $regdomain, and leave $iface up in monitor mode."
	else
		echo "set country $country, and leave $iface up in monitor mode."
	fi
	echo "Re-run with --yes to continue."
	exit 2
fi

down_parent_vaps()
{
	ifconfig -l | tr ' ' '\n' | while read -r vap; do
		[ -n "$vap" ] || continue
		if ifconfig "$vap" 2>/dev/null | grep -q "parent interface: $parent"; then
			ifconfig "$vap" down || true
		fi
	done
}

if [ "$list_only" != "yes" ]; then
	down_parent_vaps

	if ! ifconfig "$iface" >/dev/null 2>&1; then
		ifconfig "$iface" create wlandev "$parent" wlanmode monitor
	fi

	ifconfig "$iface" down || true
	if [ -n "$regdomain" ]; then
		# Do not append country here: country remapping can hide channels.
		ifconfig "$iface" regdomain "$regdomain"
	else
		ifconfig "$iface" country "$country"
	fi
	ifconfig "$iface" up

	if [ -n "$channel" ]; then
		ifconfig "$iface" channel "$channel"
	fi
fi

ifconfig "$iface" | egrep 'channel |regdomain|parent interface|status:'
ifconfig "$iface" list chan
