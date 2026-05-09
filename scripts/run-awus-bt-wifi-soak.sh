#!/bin/sh
set -u

duration="${1:-14400}"
interval="${AWUS_SOAK_INTERVAL:-60}"
iface="${AWUS_SOAK_IFACE:-wlan1}"
bt_node="${AWUS_SOAK_BT_NODE:-ubt0hci}"
ping_interval="${AWUS_SOAK_PING_INTERVAL:-1}"
stamp="$(date +%Y%m%d-%H%M%S)"
run="${AWUS_SOAK_RUN_DIR:-/tmp/awus-bt-wifi-soak-long-$stamp}"
mkdir -p "$run"
log="$run/soak.log"
pinglog="$run/ping.log"
start_info="$(readlink /var/crash/info.last 2>/dev/null || true)"
gateway="${AWUS_SOAK_GATEWAY:-$(route -n get default 2>/dev/null |
    awk '/gateway:/{ print $2; exit }')}"
usb_dev="${AWUS_SOAK_USB_DEV:-$(usbconfig list 2>/dev/null |
    awk '/MediaTek|Wireless_Device|0e8d|7961/{ sub(":", "", $1); print $1; exit }')}"
src="$(ifconfig "$iface" 2>/dev/null |
    sed -n 's/^[[:space:]]*inet \([0-9.]*\).*/\1/p' | sed -n '1p')"

if [ -z "$gateway" ]; then
	echo "missing gateway; set AWUS_SOAK_GATEWAY" | tee -a "$log"
	exit 1
fi

if [ -z "$src" ]; then
	echo "missing $iface inet" | tee -a "$log"
	exit 1
fi

{
	echo "run=$run"
	echo "pid=$$"
	echo "start=$(date)"
	echo "duration=$duration"
	echo "interval=$interval"
	echo "iface=$iface"
	echo "src=$src"
	echo "gateway=$gateway"
	echo "bt_node=$bt_node"
	echo "usb_dev=$usb_dev"
	echo "ping_interval=$ping_interval"
	echo "start_info=$start_info"
	uname -a
	sysctl -n net.wlan.devices 2>/dev/null || true
	ifconfig "$iface" 2>/dev/null | sed -n '1,14p'
	sudo -n hccontrol -n "$bt_node" read_bd_addr 2>&1 || true
	sudo -n hccontrol -n "$bt_node" read_local_version_information 2>&1 || true
} >>"$log" 2>&1

echo "$run" >/tmp/awus-bt-wifi-soak-long.latest
sudo -n ping -i "$ping_interval" -S "$src" "$gateway" >"$pinglog" 2>&1 &
pingpid=$!
trap 'kill "$pingpid" 2>/dev/null || true' EXIT INT TERM

end=$(( $(date +%s) + duration ))
iter=0
fail=0
while [ "$(date +%s)" -lt "$end" ]; do
	sleep "$interval"
	iter=$((iter + 1))
	now="$(date)"
	info="$(readlink /var/crash/info.last 2>/dev/null || true)"
	wlan_status="$(ifconfig "$iface" 2>/dev/null | awk '/status:/{print $2; exit}')"
	wlan_inet="$(ifconfig "$iface" 2>/dev/null |
	    sed -n 's/^[[:space:]]*inet \([0-9.]*\).*/\1/p' | sed -n '1p')"
	bt_bd="$(sudo -n hccontrol -n "$bt_node" read_bd_addr 2>&1 | tr '\n' ' ')"
	bt_ver="$(sudo -n hccontrol -n "$bt_node" read_local_version_information 2>&1 | tr '\n' ' ')"
	devices="$(sysctl -n net.wlan.devices 2>/dev/null || true)"

	if [ -n "$usb_dev" ]; then
		if ! timeout 8 sudo -n usbconfig -d "$usb_dev" show_ifdrv >/dev/null 2>&1; then
			echo "[$now] iter=$iter usb_ifdrv=failed usb_dev=$usb_dev devices=$devices wlan=$wlan_status inet=$wlan_inet crash=$info bt=$bt_bd" >>"$log"
			fail=1
			break
		fi
	fi
	if [ "$info" != "$start_info" ]; then
		echo "[$now] iter=$iter crash_changed from=$start_info to=$info devices=$devices wlan=$wlan_status inet=$wlan_inet bt=$bt_bd" >>"$log"
		fail=1
		break
	fi
	case "$bt_bd $bt_ver" in
		*"BD_ADDR:"*"Manufacturer: MediaTek"*|*"BD_ADDR:"*"HCI revision:"*)
			;;
		*)
			echo "[$now] iter=$iter bt_query_suspicious devices=$devices wlan=$wlan_status inet=$wlan_inet crash=$info bt=$bt_bd ver=$bt_ver" >>"$log"
			fail=1
			break
			;;
	esac
	if [ "$wlan_status" != "associated" ] || [ -z "$wlan_inet" ]; then
		echo "[$now] iter=$iter wlan_bad devices=$devices wlan=$wlan_status inet=$wlan_inet crash=$info bt=$bt_bd" >>"$log"
		fail=1
		break
	fi

	echo "[$now] iter=$iter ok devices=$devices wlan=$wlan_status inet=$wlan_inet crash=$info bt=$bt_bd" >>"$log"
done

kill "$pingpid" 2>/dev/null || true
wait "$pingpid" 2>/dev/null || true
ping_summary="$(tail -5 "$pinglog" | tr '\n' ' ')"
{
	echo "end=$(date)"
	echo "fail=$fail"
	echo "ping_summary=$ping_summary"
	echo "final_info=$(readlink /var/crash/info.last 2>/dev/null || true)"
	sysctl -n net.wlan.devices 2>/dev/null || true
	ifconfig "$iface" 2>/dev/null | sed -n '1,14p'
	sudo -n hccontrol -n "$bt_node" read_bd_addr 2>&1 || true
	sudo -n hccontrol -n "$bt_node" read_local_version_information 2>&1 || true
	echo "run=$run"
} >>"$log" 2>&1

exit "$fail"
