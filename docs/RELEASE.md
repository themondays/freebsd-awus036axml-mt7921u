# Release Checklist

Recommended GitHub repository:

```text
themondays/freebsd-awus036axml-mt7921u
```

Recommended description:

```text
WIP native FreeBSD MT7921U / AWUS036AXML Wi-Fi driver patches and test tooling
```

Recommended GitHub release tag:

```text
v0.1.0-wip
```

Mark the first GitHub release as a pre-release.
GitHub releases are tied to one Git tag. Do not add multiple version tags to
one release. If `v0.1.0-wip` is already published, do not move it; create a new
pre-release tag such as `v0.1.1-wip` for the next snapshot.

## Before Publishing

1. Confirm no local machine inventory, IPs, SSIDs, WPA keys, crash dumps,
   packet captures, built packages, kernel modules, or object files are tracked.
2. Keep the README status explicit: this is WIP Wi-Fi bring-up, not full
   AWUS036AXML support.
3. Keep Bluetooth/coexistence listed as incomplete until pairing, HID/audio,
   suspend/resume, detach, and concurrent Wi-Fi/Bluetooth operation are proven.
4. Preserve upstream license headers when converting patches into FreeBSD src
   commits.
5. Split upstream submissions into reviewable chunks:
   - LinuxKPI USB interface fixes.
   - LinuxKPI skb/headroom helpers.
   - mt76 FreeBSD compatibility fixes.
   - mt76 USB reset/detach hardening.
   - mt76 FreeBSD wlan parent naming cleanup.
   - MT7921U USB module enablement.
   - active monitor, deferred monitor config, RX mbuf guard, and RX mbuf
     chain sanity work.
   - LinuxKPI monitor radiotap fanout bypass for unassociated monitor frames.
   - LinuxKPI TX status info fallback for USB TX completion.
   - AU lib80211 regdomain userland patch.
6. Keep FreeBSD 14.3 and 14.4 patch sets separate. The 14.4 active-monitor
   patch is rebased for the 14.4 `wiphy_lock()` VAP-create path.
7. Keep the 14.4 `page_pool.h` compatibility wrapper until mt76 includes the
   newer split `net/page_pool/types.h` and `net/page_pool/helpers.h` headers.
8. Keep the 14.4 `from_timer()` compatibility wrapper separate from mt76
   changes; it is a LinuxKPI source compatibility shim for imported drivers.
9. Keep the 14.4 USB `MODULE_DEVICE_TABLE()` guard separate until LinuxKPI has
   a native `MODULE_DEVICE_TABLE_BUS_usb` implementation.
10. Keep station boot recovery in the release artifact:
   `scripts/configure-awus-station-boot.sh` must be executable and documented
   in `README.md` and `docs/TESTING.md`.
11. Do not document local SSIDs, WPA keys, DHCP addresses, encrypted-disk
   passphrases, or hostnames in release notes.
12. Keep `docs/BLUETOOTH.md` explicit that the MT7961 Bluetooth loader is
   experimental and that whole-device USB reset is not a safe recovery flow.
13. Keep `bsdconfig` network probing out of recommended setup flows until the
   probing spin against this mixed wireless stack is understood.

## Fresh Release Install Smoke Flow

Use this flow from a clean checkout or release archive after unpacking it on
the FreeBSD test host:

```sh
sudo ./scripts/capture-awus036axml.sh
sudo ./scripts/build-mt7921u-freebsd14.sh --yes
```

If `COMPAT_LINUXKPI` is compiled into the running kernel, install a patched
kernel and reboot before testing USB attach. Preserve the existing module tree
on ZFS-root systems.

After reboot and local disk unlock, if applicable:

```sh
sudo ./scripts/configure-awus-station-boot.sh --yes
sudo service awus_mt7921u_wlan onestart
sysctl net.wlan.devices
ifconfig wlan1
```

Expected first station result is a parent named `mt7921uN`, a created station
VAP named `wlan1`, WPA association, and DHCP address assignment. Keep a known
internal Wi-Fi or Ethernet fallback available while testing.

## Publish

```sh
git init
git add .
git commit -m "Prepare standalone MT7921U WIP release"
git branch -M main
git remote add origin git@github.com:themondays/freebsd-awus036axml-mt7921u.git
git push -u origin main
git tag -a v0.1.0-wip -m "v0.1.0-wip"
git push origin v0.1.0-wip
```

For later snapshots after `v0.1.0-wip` exists:

```sh
git push origin main
git tag -a v0.1.1-wip -m "v0.1.1-wip"
git push origin v0.1.1-wip
```

## Release Notes

Title:

```text
v0.1.0-wip: FreeBSD MT7921U / AWUS036AXML Wi-Fi bring-up
```

Body:

```text
Initial WIP release for native FreeBSD support of ALFA AWUS036AXML / MediaTek
MT7921U USB Wi-Fi.

Includes FreeBSD 14.3/14.4 WIP patches, build/capture scripts, AU regdomain
helper tooling, station boot recovery helper, and testing notes for USB attach,
firmware load, station mode, WPA2 association, basic traffic, monitor mode, and
active-monitor Kismet radiotap capture.

This is a pre-release. Full device support is not complete. Remaining work
includes sustained traffic, reboot/replug soak testing, clean detach,
Bluetooth pairing/HID/audio, suspend/resume, broader coexistence beyond HCI
bring-up, long-running Kismet and active-monitor soak testing, channel-hop
behavior while active monitoring, injection, 6 GHz, AP mode, and upstream-ready
patch splitting. Avoid bsdconfig network probing on this WIP stack; use direct
ifconfig/wpa_cli/dhclient/service/sysrc flows for now.
```
