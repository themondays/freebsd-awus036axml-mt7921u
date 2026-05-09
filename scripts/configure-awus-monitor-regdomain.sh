#!/bin/sh
set -eu

parent=""
iface="wlan2"
channel="157"
country="AU"
regdomain=""
assume_yes="no"
list_only="no"
reset_parent_vaps="no"

usage()
{
	cat <<EOF
Usage: sudo $0 --yes [--parent mt7921u1] [--iface wlan2] [--country AU] [--channel 157]
       sudo $0 --yes --regdomain DEBUG [--iface wlan2] [--channel 157]
       sudo $0 --yes --reset-parent-vaps [options]

Configures an AWUS036AXML/mt7921u monitor VAP for Kismet channel hopping.
With the AU regdomain patch installed, country AU exposes the native Australian
RLAN monitor channel set. Use --regdomain DEBUG only as a broad capture fallback.
By default this preserves existing station VAPs so active monitoring can be
tested. Use --reset-parent-vaps for isolated monitor setup or channel recovery.
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
		--reset-parent-vaps)
			reset_parent_vaps="yes"
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
	echo "This will create/configure monitor VAP $iface on $parent,"
	if [ -n "$regdomain" ]; then
		echo "set regdomain $regdomain, and leave $iface up in monitor mode."
	else
		echo "set country $country, and leave $iface up in monitor mode."
	fi
	if [ "$reset_parent_vaps" = "yes" ]; then
		echo "It will also down all existing wlan VAPs on $parent first."
	else
		echo "Existing station VAPs on $parent will be preserved."
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

run_or_warn()
{
	desc="$1"
	shift

	if "$@"; then
		return 0
	fi

	rc="$?"
	if [ "$reset_parent_vaps" = "yes" ]; then
		return "$rc"
	fi

	echo "$iface: $desc failed while station VAPs are preserved; continuing" >&2
	return 0
}

if [ "$list_only" != "yes" ]; then
	if [ "$reset_parent_vaps" = "yes" ]; then
		down_parent_vaps
	fi

	if ! ifconfig "$iface" >/dev/null 2>&1; then
		ifconfig "$iface" create wlandev "$parent" wlanmode monitor
	fi

	ifconfig "$iface" down || true
	if [ -n "$regdomain" ]; then
		# Do not append country here: country remapping can hide channels.
		run_or_warn "setting regdomain $regdomain" \
		    ifconfig "$iface" regdomain "$regdomain"
	else
		run_or_warn "setting country $country" \
		    ifconfig "$iface" country "$country"
	fi
	run_or_warn "bringing monitor VAP up" ifconfig "$iface" up

	if [ -n "$channel" ]; then
		run_or_warn "setting channel $channel" \
		    ifconfig "$iface" channel "$channel"
	fi
fi

ifconfig "$iface" | egrep 'channel |regdomain|parent interface|status:'
ifconfig "$iface" list chan
