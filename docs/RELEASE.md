# Release Checklist

Recommended GitHub repository:

```text
themondays/freebsd-awus036axml-mt7921u
```

Recommended description:

```text
WIP native FreeBSD MT7921U / AWUS036AXML Wi-Fi driver patches and test tooling
```

Recommended first tag:

```text
v0.1.0-wip
```

Mark the first GitHub release as a pre-release.

## Before Publishing

1. Confirm no local machine inventory, IPs, SSIDs, WPA keys, crash dumps,
   packet captures, built packages, kernel modules, or object files are tracked.
2. Keep the README status explicit: this is WIP Wi-Fi bring-up, not full
   AWUS036AXML support.
3. Keep Bluetooth/coexistence listed as incomplete until `ubt(4)` attach,
   `service bluetooth start`, and concurrent Wi-Fi/Bluetooth operation are
   proven.
4. Preserve upstream license headers when converting patches into FreeBSD src
   commits.
5. Split upstream submissions into reviewable chunks:
   - LinuxKPI USB interface fixes.
   - LinuxKPI skb/headroom helpers.
   - mt76 FreeBSD compatibility fixes.
   - mt76 USB reset/detach hardening.
   - mt76 FreeBSD wlan parent naming cleanup.
   - MT7921U USB module enablement.
   - active monitor and RX mbuf guard work.
   - AU lib80211 regdomain userland patch.

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

## Release Notes

Title:

```text
v0.1.0-wip: FreeBSD MT7921U / AWUS036AXML Wi-Fi bring-up
```

Body:

```text
Initial WIP release for native FreeBSD support of ALFA AWUS036AXML / MediaTek
MT7921U USB Wi-Fi.

Includes FreeBSD 14.3 WIP patches, build/capture scripts, AU regdomain helper
tooling, and testing notes for USB attach, firmware load, station mode, WPA2
association, basic traffic, monitor mode, and short Kismet radiotap capture.

This is a pre-release. Full device support is not complete. Remaining work
includes sustained traffic, reboot/replug soak testing, clean detach,
Bluetooth/coexistence, channel hopping, injection, 6 GHz, AP mode, and
upstream-ready patch splitting.
```
