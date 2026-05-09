# Bluetooth

The AWUS036AXML exposes a MediaTek MT7961 Bluetooth function on the same USB
device as the MT7921U Wi-Fi function. FreeBSD 14.4 attaches it with the generic
`ng_ubt` driver as `ubt0`, but standard HCI reset times out before MediaTek
firmware and WMT initialization have run:

```text
ng_hci_process_command_timeout: ubt0hci - unable to complete HCI command OGF=0x3, OCF=0x3. Timeout
/etc/rc.d/bluetooth: ERROR: Unable to setup Bluetooth stack for device ubt0
```

On the X201, the built-in Broadcom Bluetooth adapter appears separately as
`ubt1` and responds to normal HCI commands. The failing device is the MediaTek
Bluetooth side of the AWUS adapter, not the FreeBSD Bluetooth stack as a whole.

## Experimental Loader

`tools/mtkbtfw/mtkbtfw.c` is a small userland loader for the MT7961 Bluetooth
firmware flow. It reads the MediaTek device ID and firmware version over USB
vendor control requests, sends the WMT patch download sequence, writes the
endpoint reset option register, and enables the Bluetooth protocol before
starting the normal FreeBSD Bluetooth stack.

The firmware file is not stored in this repository. Use the linux-firmware
MediaTek file:

```text
BT_RAM_CODE_MT7961_1_2_hdr.bin
```

Install on a test host:

```sh
sudo ./scripts/install-awus-mt7921u-bluetooth.sh --yes --fetch-firmware
```

By default this installs a safe `devd` override that suppresses FreeBSD's
generic early `ubt0` start for `0e8d:7961`, but does not automatically run the
experimental loader. After manual HCI bring-up works reliably, reinstall with:

```sh
sudo ./scripts/install-awus-mt7921u-bluetooth.sh --yes --enable-devd-loader
```

Manual one-shot test:

```sh
sudo /usr/local/sbin/awus-mt7921u-bluetooth-start ubt0
sudo hccontrol -n ubt0hci read_local_version_information
sudo hccontrol -n ubt0hci read_bd_addr
```

The installer adds `/usr/local/etc/devd/awus-mt7921u-bluetooth.conf`, a
higher-priority `devd` rule for `vendor=0x0e8d product=0x7961`. Other
Bluetooth controllers, such as the X201 Broadcom `ubt1`, continue to use
FreeBSD's default `/etc/devd/bluetooth.conf` path.

## Status

Current scope is firmware load and HCI bring-up. On the X201 running FreeBSD
14.4, `mtkbtfw` loaded `BT_RAM_CODE_MT7961_1_2_hdr.bin`, `service bluetooth
quietstart ubt0` succeeded, and `ubt0hci` answered:

```text
HCI revision: 0x2411
LMP sub-version: 0x2602
Manufacturer: MediaTek, Inc. [0x46]
BD_ADDR: <adapter-address>
```

The installed host can enable automatic firmware load/start on future attaches:

```sh
sudo ./scripts/install-awus-mt7921u-bluetooth.sh --yes --enable-devd-loader
```

Pairing, HID, audio, suspend, resume, detach, and longer coexistence with active
Wi-Fi still need validation before this can be called full Bluetooth support.
Avoid `usbconfig reset` or whole-controller reset as a recovery flow for now;
on the X201 that wedged the composite AWUS USB device until reboot.

Linux reference implementation points:

- `drivers/bluetooth/btusb.c` marks MediaTek Bluetooth devices for a MediaTek
  setup path.
- `drivers/bluetooth/btmtk.c` implements MT79xx WMT firmware download and
  Bluetooth protocol enable.
- `drivers/bluetooth/btmtk.h` names the MT7961 firmware file.
