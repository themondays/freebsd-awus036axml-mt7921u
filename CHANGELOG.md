# Changelog

## v0.1.0-wip - 2026-05-09

Initial standalone Wi-Fi release candidate.

Included:

- FreeBSD 14.3 and 14.4 WIP MT7921U / AWUS036AXML patch sets.
- LinuxKPI USB and skb compatibility work captured as patch artifacts.
- mt76 IDR sentinel guard patch.
- Active monitor VAP patch.
- Deferred LinuxKPI monitor config patch to keep mt7921 sniffer MCU commands
  out of net80211 locked state transitions.
- RX mbuf length guard patch for Kismet/promiscuous monitor fanout.
- RX mbuf chain sanity patch for active monitor all-VAP fanout.
- Monitor radiotap fanout bypass for unassociated monitor frames.
- TX status info fallback patch for mt76 USB completion.
- Build and diagnostic capture scripts.
- Station boot recovery helper for `mt7921u0`/`wlan1`.
- Experimental MT7961 Bluetooth firmware loader and devd integration tooling.
- Focused testing and release notes.

Known limits:

- Experimental only.
- Bluetooth/coexistence is not complete. MT7961 firmware load and `ubt0hci`
  bring-up are validated on the X201, but pairing, HID/audio, suspend/resume,
  detach, and longer Wi-Fi coexistence still need testing.
- Detach/unload and sustained traffic still need hardening.
- Whole-device USB reset is not a safe recovery flow yet; use physical replug
  if the AWUS composite device wedges during testing.
- Kismet has only short fixed-channel and AU channel-hopping smoke coverage on
  FreeBSD 14.4; long-running monitor soak testing is still needed.
- Active-monitor Kismet has a clean 3-minute fixed-channel smoke test after the
  radiotap fanout bypass, but unattended active-monitor soak is still open.
- Active monitor is validated on the station channel. Changing country or
  broad channel hopping while the station VAP is live can be rejected as busy.
- Avoid `bsdconfig` network probing on this WIP stack; direct network commands
  are documented for setup and testing.
- Patches need to be split and cleaned before upstream submission.
