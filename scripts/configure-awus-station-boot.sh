#!/bin/sh
set -eu

internal_parent="iwn0"
internal_iface="wlan0"
internal_config="WPA DHCP"
awus_parent="mt7921u0"
awus_iface="wlan1"
awus_config="WPA DHCP"
install_helper="yes"
assume_yes="no"

usage()
{
	cat <<EOF
Usage: sudo $0 --yes [options]

Persists a conservative station setup for an internal Wi-Fi fallback plus an
AWUS036AXML/mt7921u station VAP.

Options:
  --internal-parent DEV   Internal parent device (default: iwn0)
  --internal-iface IFACE  Internal wlan iface (default: wlan0)
  --internal-config CFG   rc.conf value (default: WPA DHCP)
  --awus-parent DEV       Preferred AWUS parent device (default: mt7921u0)
  --awus-iface IFACE      AWUS wlan iface (default: wlan1)
  --awus-config CFG       rc.conf value (default: WPA DHCP)
  --no-helper             Do not install the late-attach rc.d/devd helper
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--yes)
			assume_yes="yes"
			;;
		--internal-parent)
			internal_parent="${2:?missing --internal-parent value}"
			shift
			;;
		--internal-iface)
			internal_iface="${2:?missing --internal-iface value}"
			shift
			;;
		--internal-config)
			internal_config="${2:?missing --internal-config value}"
			shift
			;;
		--awus-parent)
			awus_parent="${2:?missing --awus-parent value}"
			shift
			;;
		--awus-iface)
			awus_iface="${2:?missing --awus-iface value}"
			shift
			;;
		--awus-config)
			awus_config="${2:?missing --awus-config value}"
			shift
			;;
		--no-helper)
			install_helper="no"
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

if [ "$assume_yes" != "yes" ]; then
	echo "This will update /etc/rc.conf for:"
	echo "  wlans_${internal_parent}=${internal_iface}"
	echo "  ifconfig_${internal_iface}=${internal_config}"
	echo "  wlans_${awus_parent}=${awus_iface}"
	echo "  ifconfig_${awus_iface}=${awus_config}"
	if [ "$install_helper" = "yes" ]; then
		echo "It will also install /usr/local/etc/rc.d/awus_mt7921u_wlan"
		echo "and /usr/local/etc/devd/awus-mt7921u.conf."
	fi
	echo "Re-run with --yes to continue."
	exit 2
fi

append_kld()
{
	current="$(sysrc -n kld_list 2>/dev/null || true)"
	for module in "$@"; do
		case " $current " in
			*" $module "*)
				;;
			*)
				current="${current:+$current }$module"
				;;
		esac
	done
	sysrc kld_list="$current"
}

remove_stale_awus_wlans()
{
	sysrc -a 2>/dev/null |
	    awk -F': ' '/^wlans_mt7921u[0-9]+: / { print $1 }' |
	    while IFS= read -r key; do
		[ -n "$key" ] || continue
		if [ "$key" = "wlans_${awus_parent}" ]; then
			continue
		fi
		sysrc -x "$key" >/dev/null
	    done
}

stamp="$(date +%Y%m%d-%H%M%S)"
cp -p /etc/rc.conf "/etc/rc.conf.before-awus-station-${stamp}"
echo "Backed up /etc/rc.conf to /etc/rc.conf.before-awus-station-${stamp}"

sysrc "wlans_${internal_parent}=${internal_iface}"
sysrc "ifconfig_${internal_iface}=${internal_config}"
remove_stale_awus_wlans
sysrc "wlans_${awus_parent}=${awus_iface}"
sysrc "ifconfig_${awus_iface}=${awus_config}"
append_kld mt76_core if_mt7921

if [ "$install_helper" = "yes" ]; then
	install -d -o root -g wheel -m 755 /usr/local/etc/rc.d /usr/local/etc/devd

	cat > /usr/local/etc/rc.d/awus_mt7921u_wlan <<'EOF'
#!/bin/sh

# PROVIDE: awus_mt7921u_wlan
# REQUIRE: netif devd
# BEFORE: LOGIN
# KEYWORD: shutdown

. /etc/rc.subr

name="awus_mt7921u_wlan"
rcvar="awus_mt7921u_wlan_enable"
start_cmd="awus_mt7921u_wlan_start"
stop_cmd=":"

load_rc_config "$name"
: ${awus_mt7921u_wlan_enable:="NO"}
: ${awus_mt7921u_wlan_parent:="mt7921u0"}
: ${awus_mt7921u_wlan_iface:="wlan1"}
: ${awus_mt7921u_wlan_wait:="20"}

awus_mt7921u_wlan_start()
{
	resolve_parent()
	{
		if sysctl -n net.wlan.devices 2>/dev/null |
		    awk -v p="$awus_mt7921u_wlan_parent" '{ for (i = 1; i <= NF; i++) if ($i == p) found = 1 } END { exit found ? 0 : 1 }'; then
			echo "$awus_mt7921u_wlan_parent"
			return 0
		fi
		sysctl -n net.wlan.devices 2>/dev/null |
		    awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^mt7921u[0-9]+$/) { print $i; exit } }'
	}

	i=0
	while [ "$i" -lt "$awus_mt7921u_wlan_wait" ]; do
		parent="$(resolve_parent)"
		if [ -n "$parent" ]; then
			if ! ifconfig "$awus_mt7921u_wlan_iface" >/dev/null 2>&1; then
				ifconfig "$awus_mt7921u_wlan_iface" create \
				    wlandev "$parent" || return 1
			fi
			/etc/rc.d/netif quietstart "$awus_mt7921u_wlan_iface" || true
			return 0
		fi
		i=$((i + 1))
		sleep 1
	done
	echo "$name: preferred parent $awus_mt7921u_wlan_parent not present and no mt7921uN parent was found"
	return 0
}

run_rc_command "$1"
EOF
	chown root:wheel /usr/local/etc/rc.d/awus_mt7921u_wlan
	chmod 555 /usr/local/etc/rc.d/awus_mt7921u_wlan

	cat > /usr/local/etc/devd/awus-mt7921u.conf <<EOF
notify 100 {
	match "system" "IFNET";
	match "subsystem" "mt7921u[0-9]+";
	match "type" "ATTACH";
	action "/usr/sbin/service awus_mt7921u_wlan onestart";
};
EOF
	chown root:wheel /usr/local/etc/devd/awus-mt7921u.conf
	chmod 444 /usr/local/etc/devd/awus-mt7921u.conf

	sysrc awus_mt7921u_wlan_enable="YES"
	sysrc awus_mt7921u_wlan_parent="$awus_parent"
	sysrc awus_mt7921u_wlan_iface="$awus_iface"
	service devd restart || true
fi

echo "Station boot configuration complete."
echo "Check with:"
echo "  sysrc wlans_${internal_parent} ifconfig_${internal_iface}"
echo "  sysrc wlans_${awus_parent} ifconfig_${awus_iface}"
echo "  service awus_mt7921u_wlan onestart"
