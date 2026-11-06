# TAKEOVER: Stream Deck Remote

Written as we go, after every major step (Marko, 6.11.2026: "After every major step, write automatically take over
document. Don't wait for closing of the session.").

## Where it stands (6.11.2026 ~20:55, step 7: the helper shows the deck like the phone; Mac v10, APK v5)

- **Mac helper v10** (release mac-v10, installed): its window is the phone's view on top: the 15 keys (a click presses,
  the press enlarges on all three), the live line, APPS / OBS tabs that switch the profile on the Mac, the phone and the
  real deck at once (Marko: "the Stream Deck cannot switch the profiles but I can switch it through the app on the
  phone or through the app on my Mac"); the technical details below it scroll; the window is sized from its own screen
  (its bottom was cut on the second screen; rule MANTRA_MANIFEST modules/two-screens.md: two screens, check both).
- Tested: AX press on the Mac's APPS tab → profile apps on the phone (over Wi-Fi) and the real deck (camera); back to
  OBS the same way. Screenshots of both screens taken (BenQ = display 2, the helper opened there and fits).
- **Wi-Fi path proven** (step 6): no ADB, no Tailscale; CABLE / ADB is OFF on this Mac.
- **APK v5** on the Pixel: ROTATE + immersive landscape, dark glowing icon, LAN before Tailscale.
- OBS keys = absolute positions in OBS's Scenes dock (key 1 = top), re-read at every change and every 2 s.
- The real deck's display is broken (hardware); judge roughly. Stream Deck Control removed, repo archived.
- Not yet tested: ROTATE against a real turn of the phone (Marko's hand), the press-enlarge by eye, the MK.2.
- Next profile: whatever Marko names. OBS's own window was closed, so the switch was checked through OBS's events, not
  by eye.

## The plan

- **Stream Deck Remote** (Android, Kotlin + Compose, package com.mantra.streamdeckremote): a 5 × 3 deck like Marko's
  Elgato 15-key, mirrored with the real deck, profile tabs at the bottom: APPS (the application switcher) and OBS (one numbered key per scene).
- **Stream Deck Remote (Mantra)** (Mac, Swift): HTTP on port 8963 (MANTRA_PORTS name `streamdeck-remote`), Bonjour
  `_mantradeck._tcp` so the phone finds it on the same Wi-Fi without ADB; `adb reverse` over a USB cable as the fallback.
- OBS through obs-websocket v5 on 127.0.0.1:4455; the password is read from OBS's own config, never stored here.
