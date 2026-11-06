# TAKEOVER: Stream Deck Remote

Written as we go, after every major step (Marko, 6.11.2026: "After every major step, write automatically take over
document. Don't wait for closing of the session.").

## Where it stands (6.11.2026 ~20:50, step 6: the Wi-Fi path proven)

- Installed: Mac helper **v9** (release mac-v9), APK **v5** on the Pixel 7 (release v5, Latest).
- **Wi-Fi path tested (Marko: "now test Wi-Fi path")**: cable route OFF (`defaults write community.auroville.streamdeckremote
  cable -bool false`, or the CABLE / ADB OFF switch in the helper window), `adb reverse` removed, the phone's Tailscale
  app force-stopped (Marko: "Feel free now to disable ADB tailscale"): the phone showed "MacBook Pro · Wi-Fi"
  (192.168.1.101 → 192.168.1.102:8963, found by Bonjour) and key presses switched OBS 1 → 3 → 2 → 1 with the live scene
  following. No ADB, no Tailscale. macOS did not block the Local Network (the helper answered the phone at once).
  CABLE is still OFF on this Mac; ON brings the `adb reverse` back.
- v8-v9 fixes: Bonjour gets 2.5 s before Tailscale; only the local address is remembered; the helper window's ON/OFF row
  was cut under the title bar (now an NSHostingController).
- Done earlier: shared engine (real deck + phone mirror, press enlarges 118 % on both), APPS (apps 1-12, NEXT, F1,
  F2) and OBS (absolute dock positions, key 1 = top scene, re-read at every change and every 2 s), ROTATE and the
  immersive landscape deck (APK v3), dark icons with quiet glowing keys (APK v4, Mac v7), Stream Deck Control removed.
- The real deck's display is broken (hardware); judge it roughly.
- Not yet tested: the ROTATE press-hold against the sensor on a real turn of the phone (Marko's hand), the press
  enlarge by eye, the MK.2.
- Open question for Marko: how to switch profile on the real deck alone (it has no tabs).
- Next profile: whatever Marko names.

## The plan

- **Stream Deck Remote** (Android, Kotlin + Compose, package com.mantra.streamdeckremote): a 5 × 3 deck like Marko's
  Elgato 15-key, mirrored with the real deck, profile tabs at the bottom: APPS (the application switcher) and OBS (one numbered key per scene).
- **Stream Deck Remote (Mantra)** (Mac, Swift): HTTP on port 8963 (MANTRA_PORTS name `streamdeck-remote`), Bonjour
  `_mantradeck._tcp` so the phone finds it on the same Wi-Fi without ADB; `adb reverse` over a USB cable as the fallback.
- OBS through obs-websocket v5 on 127.0.0.1:4455; the password is read from OBS's own config, never stored here.
