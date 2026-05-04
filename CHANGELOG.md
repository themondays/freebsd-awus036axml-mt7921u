# Changelog

## v0.1.0-wip - 2026-05-05

Initial standalone Wi-Fi release candidate.

Included:

- FreeBSD 14.3 WIP MT7921U / AWUS036AXML patch set.
- LinuxKPI USB and skb compatibility work captured as patch artifacts.
- mt76 IDR sentinel guard patch.
- Active monitor VAP patch.
- RX mbuf length guard patch for Kismet/promiscuous monitor fanout.
- Build and diagnostic capture scripts.
- Focused testing and release notes.

Known limits:

- Experimental only.
- Bluetooth/coexistence is not complete.
- Detach/unload and sustained traffic still need hardening.
- Patches need to be split and cleaned before upstream submission.
