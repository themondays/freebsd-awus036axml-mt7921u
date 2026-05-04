# FreeBSD AWUS036AXML / MT7921U

Standalone WIP workspace for native FreeBSD support of the ALFA AWUS036AXML
USB Wi-Fi 6E adapter, based on MediaTek MT7921AUN / MT7921U.

This is not a Linux driver wrapper. The work targets FreeBSD 14.3 kernel
sources, FreeBSD LinuxKPI gaps, and the imported mt76 / mt7921 driver stack.

## Status

Pre-release, experimental, and not ready to claim full device support.

Validated so far on a FreeBSD 14.3 test machine:

- USB Wi-Fi interface match and attach through LinuxKPI USB.
- Firmware load for MT7961/MT7921 firmware.
- `wlan` parent creation and scan.
- WPA2 station association and DHCP.
- Basic gateway traffic.
- Concurrent station plus monitor VAP on the associated channel.
- Short Kismet radiotap capture after RX mbuf length guard.

Not complete yet:

- Sustained default-route traffic and speed testing.
- Reboot/replug soak testing.
- Clean detach/unload paths.
- Channel hopping.
- Packet injection.
- 6 GHz validation.
- AP mode.
- Bluetooth attach and Wi-Fi/Bluetooth coexistence.
- Upstream-ready patch split and style cleanup.

## Layout

```text
patches/freebsd-14.3/
  freebsd-14.3-mt76-mt7921u-wip.patch
  freebsd-14.3-mt76-tx-status-idr-sentinel.patch
  freebsd-14.3-linuxkpi-active-monitor-wip.patch
  freebsd-14.3-linuxkpi-rx-mbuf-length-guard-wip.patch

scripts/
  build-mt7921u-freebsd14.sh
  capture-awus036axml.sh

docs/
  TESTING.md
  RELEASE.md
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
addition to any internal Wi-Fi device.

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
