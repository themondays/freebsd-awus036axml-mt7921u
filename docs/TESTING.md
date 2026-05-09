# Testing

Use controlled tests and keep Ethernet or a known-good internal Wi-Fi path
available while testing the WIP driver.

Run monitor-mode, Kismet, and packet-capture tests only where you are
authorized to test. Keep local SSIDs, keys, pcaps, and operational identifiers
out of public logs and release artifacts.

## Patch Set

Use the patch directory matching the FreeBSD source tree:

```sh
awk -F\" '/^REVISION=/{ print $2 }' /usr/src/sys/conf/newvers.sh
sudo ./scripts/build-mt7921u-freebsd14.sh --yes
```

The build script currently supports `freebsd-14.3` and `freebsd-14.4`. During
an incomplete base upgrade, force the intended tree with `FREEBSD_MINOR=14.4`.

## Baseline Capture

```sh
sudo ./scripts/capture-awus036axml.sh
```

Save the output directory before changing kernel modules or routes.

## Module Load

```sh
sudo kldload mt76_core
sudo kldload if_mt7921
sudo usbconfig list
sysctl net.wlan.devices
dmesg | tail -100
```

## Station Smoke Test

Encrypted-root systems need local key entry after every reboot before SSH can
return. Treat remote polling timeouts during reboot tests as inconclusive until
the filesystem has been unlocked on the console.

For reboot-persistent station setup:

```sh
sudo ./scripts/configure-awus-station-boot.sh --yes
service awus_mt7921u_wlan onestart
```

This keeps the internal fallback interface on non-blocking `WPA DHCP` and
configures the AWUS station VAP as `wlan1`. The helper is intentionally
conservative: keep SSH on the fallback interface until `wlan1` has associated
and received an address.

```sh
parent=$(sysctl -n net.wlan.devices | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^mt7921u[0-9]+$/) { print $i; exit } }')
sudo ifconfig wlan1 create wlandev "$parent"
sudo ifconfig wlan1 up
sudo ifconfig wlan1 scan
sudo wpa_supplicant -B -i wlan1 -c /etc/wpa_supplicant.conf -D bsd
wpa_cli -i wlan1 status
sudo dhclient wlan1
```

Prefer source-bound or host-route tests before moving the default route:

```sh
ping -c 5 -S <wlan1-address> <gateway>
```

## Monitor Smoke Test

Create a monitor VAP beside the station VAP. For active monitoring, preserve
the station VAP and keep the monitor on the current station channel:

```sh
sudo ./scripts/configure-awus-monitor-regdomain.sh --yes \
  --iface wlan2 --country AU --channel <associated-channel>
sudo tcpdump -ni wlan2 -y IEEE802_11_RADIO -s 512 -c 20 -vv
```

If `ifconfig` reports `SIOCS80211: Device busy` while setting country or
regdomain, keep going if the printed `wlan2` state shows the expected channel
and `status: running`. FreeBSD may reject regulatory changes while a station
VAP is associated. Use `--reset-parent-vaps` only for isolated monitor tests,
because it downs existing VAPs on the mt7921u parent.

Destroy the monitor VAP after capture:

```sh
sudo ifconfig wlan2 destroy
```

## AU Regdomain

FreeBSD 14.3/14.4 maps country `AU` to a generic regdomain that hides several
Australian 5 GHz monitor channels. For AU capture testing, install the local
lib80211 regdomain patch matching the source tree:

```sh
sudo ./scripts/apply-au-regdomain-freebsd14.sh --yes
sudo ./scripts/configure-awus-monitor-regdomain.sh --yes \
  --iface wlan2 --country AU --channel 157
```

Expected accepted checks:

```sh
sudo ifconfig wlan2 channel 52
sudo ifconfig wlan2 channel 100
sudo ifconfig wlan2 channel 132
sudo ifconfig wlan2 channel 157
```

Expected rejected gap checks:

```sh
sudo ifconfig wlan2 channel 120
sudo ifconfig wlan2 channel 144
```

## Kismet

The primary feature test is active monitoring: keep `wlan1` associated and
passing traffic while Kismet captures on monitor VAP `wlan2`.

Legacy Kismet may need the BSD radiotap source type:

```sh
src=$(ifconfig wlan1 | awk '/inet /{print $2; exit}')
sudo ping -S "$src" -i 0.2 -c 360 <gateway> >/tmp/awus-active-ping.out &
sudo timeout 45 kismet_server --no-plugins --no-line-wrap \
  -f /usr/local/etc/kismet.conf \
  -c wlan2:type=radiotap_bsd_a,name=awus,hop=false,channel=<channel> \
  -p /tmp/kismet-awus-rxguard -t awus-rxguard -T pcapdump,nettxt
wait
```

The FreeBSD 14.4 deferred monitor-config patch fixes the earlier X201 WITNESS
panic where Kismet opened the BPF source while the mt7921 sniffer transition
slept under the `mt7921uN_com_lo` lock. After installing that patch and rebooting,
fixed-channel Kismet ran for 45 seconds on channel 40 and logged 11,389 packets
without a new crash dump.

The RX mbuf chain sanity patch fixes a later active-monitor page fault in
`ieee80211_input_mimo_all() -> m_dup()` caused by malformed RX mbufs reaching
all-VAP fanout. With that patch on the X201, Kismet ran for 70 seconds on
`wlan2` while `wlan1` completed 360/360 gateway pings with 0% loss; Kismet
logged 56,260 packets and no new crash dump appeared.

The monitor radiotap fanout patch narrows the RX path for unassociated monitor
frames: when no node is found and a monitor VAP is running, LinuxKPI now sends
the mbuf directly through `ieee80211_radiotap_rx_all()` instead of duplicating
it through net80211 all-VAP input. With that patch installed and rebooted on
FreeBSD 14.4, a 3-minute fixed-channel active-monitor Kismet run logged 31,070
packets while the station VAP kept passing gateway traffic and no new crash
dump appeared.

For AU channel hopping, keep the hop list inside the tested native AU set:

```text
36,40,44,48,52,56,60,64,100,104,108,112,116,132,136,140,149,153,157,161,165
```

Example AU channel-hopping smoke test:

```sh
sudo timeout 35 kismet_server --no-plugins --no-line-wrap \
  -f /usr/local/etc/kismet.conf \
  -c wlan2:type=radiotap_bsd_a,name=awus,channellist=IEEE80211a \
  -p /tmp/kismet-awus-hop -t awus-hop -T pcapdump,nettxt
```

On the X201 this logged 1,131 packets and 18 networks across the AU 5 GHz
channel list without a panic. Treat that as a smoke test only; long-running
Kismet soak testing is still required.

Long unattended active-monitor soak is not release proven yet. One later soak
made the host unreachable without producing a new crash dump; treat that as an
open stability item until the test can complete with retained logs.

Channel hopping is not the same as active monitoring. Active monitoring should
first be tested on the associated station channel. Hopping away from the station
channel may disrupt station traffic or be rejected while the station VAP is
live.

## Bluetooth HCI Smoke Test

The AWUS036AXML Bluetooth function is MediaTek MT7961 on `ubt0`. It needs the
MediaTek WMT firmware loader before the normal FreeBSD Bluetooth startup path.

```sh
sudo ./scripts/install-awus-mt7921u-bluetooth.sh --yes
sudo /usr/local/sbin/awus-mt7921u-bluetooth-start ubt0
sudo hccontrol -n ubt0hci read_local_version_information
sudo hccontrol -n ubt0hci read_bd_addr
```

Expected result is that `ubt0hci` answers with `Manufacturer: MediaTek, Inc.`
and a stable `BD_ADDR`. Avoid `usbconfig reset` on the composite AWUS device;
on the X201 it can wedge the adapter until physical replug.

## Wi-Fi + Bluetooth Soak

Use the bundled soak runner to check that station traffic, the AWUS USB
functions, and `ubt0hci` stay alive together over time:

```sh
sudo ./scripts/run-awus-bt-wifi-soak.sh
```

On the X201 this completed a four-hour run with source-bound ping traffic,
`wlan1` still associated, `ubt0hci` still answering, and no new crash dump
from the start marker.

Timeout exit status is expected when using `timeout`. Confirm the kernel did
not reboot and no new crash dump appeared.

## Crash Data

For panics, collect:

```sh
ls -ltr /var/crash
cat /var/crash/info.N
grep -i 'panic\\|mt76\\|mt7921\\|linuxkpi\\|wlan' /var/log/messages
```

Keep the exact kernel/module build identifiers with the crash report.

## bsdconfig Caveat

Avoid `bsdconfig` network probing while testing this WIP stack. On the X201,
`/usr/libexec/bsdconfig/120.networking/devices` has been observed spinning at
one full CPU after probing wireless interfaces. Use direct `ifconfig`,
`wpa_cli`, `dhclient`, `service`, and `sysrc` commands instead.
