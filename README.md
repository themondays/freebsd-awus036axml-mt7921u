# FreeBSD AWUS036AXML / MT7921U

Standalone WIP workspace for native FreeBSD support of the ALFA AWUS036AXML
USB Wi-Fi 6E adapter, based on MediaTek MT7921AUN / MT7921U.

This is not a Linux driver wrapper. The work targets FreeBSD 14.3/14.4 kernel
sources, FreeBSD LinuxKPI gaps, and the imported mt76 / mt7921 driver stack.

## Authorized Use

Monitor-mode, Kismet, and packet-capture validation must be run only on
systems, networks, and spectrum where the operator has authorization. Do not
publish local SSIDs, keys, pcaps, or operational identifiers with release
artifacts.

## Status

Pre-release, experimental, and not ready to claim full device support.

Validated so far on FreeBSD 14.3 and on the X201 running FreeBSD 14.4:
an `mt7921uN` parent appears, `wlan1` associates, DHCP assigns an address, bounded
station traffic passes in both directions, and radiotap monitor capture works
with `tcpdump` and Kismet.

Validated areas:

- USB Wi-Fi interface match and attach through LinuxKPI USB.
- Firmware load for MT7961/MT7921 firmware.
- `wlan` parent creation and scan.
- WPA2 station association and DHCP.
- Basic gateway traffic.
- Concurrent station plus monitor VAP on the associated channel.
- Active-monitor Kismet test: `wlan1` stayed associated and passed traffic
  while `wlan2` captured radiotap packets.
- Short Kismet radiotap capture after RX mbuf length guard.
- Short Kismet active-monitor capture after monitor radiotap fanout bypass.
- FreeBSD 14.4 Kismet fixed-channel and AU channel-hopping monitor smoke tests.
- Native AU regdomain userland patch for the tested monitor channel set.
- FreeBSD 14.4 station upload smoke after the TX status info fallback patch.
- MediaTek Bluetooth WMT control path can be reached from userland while Wi-Fi
  remains attached.
- Experimental MediaTek Bluetooth firmware load and `ubt0hci` bring-up.
- Four-hour Wi-Fi plus Bluetooth controller soak on the X201 without a new
  crash dump or AWUS detach.

Not complete yet:

- Sustained default-route traffic and speed testing.
- Reboot/replug soak testing.
- Clean detach/unload paths.
- Long-running Kismet and channel-hopping soak testing.
- Long-running active-monitor Kismet soak testing. A short fixed-channel
  active-monitor run is clean, but unattended soak is not yet release proven.
- Active monitor is currently validated on the station channel. Setting country
  or broad channel hopping while the station VAP is live may be rejected by
  FreeBSD as `Device busy`.
- Packet injection.
- 6 GHz validation.
- AP mode.
- Bluetooth pairing, HID/audio, suspend/resume, detach, and broader
  Wi-Fi/Bluetooth coexistence validation beyond HCI bring-up.
- Whole-device USB reset is not a safe recovery flow yet; on the X201 it can
  wedge the AWUS composite device and drop the `mt7921uN` parent until physical
  replug.
- Upstream-ready patch split and style cleanup.

## Layout

```text
patches/freebsd-14.3/
  freebsd-14.3-mt76-mt7921u-wip.patch
  freebsd-14.3-mt76-tx-status-idr-sentinel.patch
  freebsd-14.3-mt76-usb-reset-hardening.patch
  freebsd-14.3-mt76-freebsd-wlan-parent-name.patch
  freebsd-14.3-mt76-drop-usb-tx-debug.patch
  freebsd-14.3-linuxkpi-active-monitor-wip.patch
  freebsd-14.3-linuxkpi-deferred-monitor-config-wip.patch
  freebsd-14.3-linuxkpi-rx-mbuf-length-guard-wip.patch
  freebsd-14.3-linuxkpi-rx-mbuf-chain-sanity-wip.patch
  freebsd-14.3-linuxkpi-monitor-radiotap-fanout-wip.patch
  freebsd-14.3-linuxkpi-tx-status-info-fallback-wip.patch
  freebsd-14.3-lib80211-au-regdomain-wip.patch

patches/freebsd-14.4/
  freebsd-14.4-linuxkpi-page-pool-compat.patch
  freebsd-14.4-linuxkpi-from-timer-compat.patch
  freebsd-14.4-mt76-mt7921u-wip.patch
  freebsd-14.4-mt76-usb-device-table-guard.patch
  freebsd-14.4-mt76-tx-status-idr-sentinel.patch
  freebsd-14.4-mt76-usb-reset-hardening.patch
  freebsd-14.4-mt76-freebsd-wlan-parent-name.patch
  freebsd-14.4-mt76-drop-usb-tx-debug.patch
  freebsd-14.4-linuxkpi-active-monitor-wip.patch
  freebsd-14.4-linuxkpi-deferred-monitor-config-wip.patch
  freebsd-14.4-linuxkpi-rx-mbuf-length-guard-wip.patch
  freebsd-14.4-linuxkpi-rx-mbuf-chain-sanity-wip.patch
  freebsd-14.4-linuxkpi-monitor-radiotap-fanout-wip.patch
  freebsd-14.4-linuxkpi-tx-status-info-fallback-wip.patch
  freebsd-14.4-lib80211-au-regdomain-wip.patch

scripts/
  build-mt7921u-freebsd14.sh
  capture-awus036axml.sh
  configure-awus-station-boot.sh
  apply-au-regdomain-freebsd14.sh
  configure-awus-monitor-regdomain.sh
  install-awus-mt7921u-bluetooth.sh

docs/
  BLUETOOTH.md
  TESTING.md
  RELEASE.md

tools/
  mtkbtfw/
```

## Hardware

AWUS036AXML appears as a USB combo device. The Bluetooth side may bind to
`ubt(4)`, while the Wi-Fi side is a vendor-specific interface normally using
USB id `0e8d:7961` and should attach through `usb_linux` / `if_mt7921` after
the WIP patch set is applied.

On USB 2.0-only laptops, the adapter is limited to high-speed USB 2.0 rates
even though the radio supports Wi-Fi 6E.

## Quick Start

Capture baseline state:

```sh
sudo ./scripts/capture-awus036axml.sh
```

Install firmware and apply the WIP mt76/MT7921U patch:

```sh
sudo ./scripts/build-mt7921u-freebsd14.sh --yes
```

The build script selects `patches/freebsd-14.3` or `patches/freebsd-14.4`
from `/usr/src/sys/conf/newvers.sh`. Override with `FREEBSD_MINOR=14.4` if
the source tree and running userland are temporarily out of sync during an
upgrade.

If `COMPAT_LINUXKPI` is built into the running kernel, rebuild and install a
patched kernel before testing. On ZFS-root systems, avoid a kernel install path
that removes the existing `/boot/kernel/*.ko` module tree.

After reboot:

```sh
sudo kldload mt76_core
sudo kldload if_mt7921
sudo usbconfig list
sysctl net.wlan.devices
dmesg | tail -80
```

Expected early success is a new wlan parent device in `net.wlan.devices` in
addition to any internal Wi-Fi device. On the AWUS036AXML path it should be
named `mt7921uN`, not the generic LinuxKPI root name `device`.

For a persistent station setup, keep a known-good internal Wi-Fi or Ethernet
path available and then install the rc.conf/devd helper:

```sh
sudo ./scripts/configure-awus-station-boot.sh --yes
```

The helper sets the internal Wi-Fi fallback to `WPA DHCP`, configures
`wlan1` as the AWUS station VAP, and retries late USB attach at boot. It assumes
`/etc/wpa_supplicant.conf` already contains the target networks.

Avoid `bsdconfig` network probing on this WIP setup. On the X201, its
`120.networking/devices` helper can spin at one full CPU while probing the
mixed native/LinuxKPI wireless stack. Prefer direct `ifconfig`, `wpa_cli`,
`dhclient`, `service`, and `sysrc` commands while this driver is experimental.

For AU monitor testing and Kismet channel hopping, install the userland
regdomain patch separately:

```sh
sudo ./scripts/apply-au-regdomain-freebsd14.sh --yes
sudo ./scripts/configure-awus-monitor-regdomain.sh --yes \
  --iface wlan2 --country AU --channel 157
```

The validated AU monitor channel set is 1-13, 36-64, 100-116, 132-140, and
149-165. The patch intentionally keeps 120/124/128 and 144 unavailable.

For active monitoring, keep the station VAP associated and create the monitor
VAP on the current station channel:

```sh
sudo ./scripts/configure-awus-monitor-regdomain.sh --yes \
  --iface wlan2 --country AU --channel 40
```

If FreeBSD reports `Device busy` while setting country/regdomain, the helper
warns and preserves the station VAP. Use `--reset-parent-vaps` only for
isolated monitor setup or channel recovery, because it intentionally downs
station VAPs on the mt7921u parent.

## Publication Scope

Use this repository for public review, repeatable testing, and upstream patch
preparation. Do not describe the current state as full AWUS036AXML support.

Recommended first tag:

```text
v0.1.0-wip
```

## License

Repository-original material is BSD-2-Clause. See [LICENSES.md](LICENSES.md)
for patch licensing notes.
