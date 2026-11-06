# TAKEOVER: Stream Deck Remote

Written as we go, after every major step (Marko, 6.11.2026: "After every major step, write automatically take over
document. Don't wait for closing of the session.").

## Where it stands (6.11.2026 ~20:40, step 4: tested on the real deck and the real Pixel 7; Mac v5, APK v2)

- Installed: /Applications/Stream Deck Remote (Mantra).app **v5** (release mac-v5, signed "Mantra Apps"), APK **v2** on
  the Pixel 7 (41241FDH2S10SJ, release v2).
- Verified: the phone finds the Mac over the cable (adb reverse set by the helper) and shows APPS (apps 1-12, NEXT,
  F1, F2, the same as the real deck); a tap on the OBS tab switched BOTH faces to OBS; OBS's 3 scenes are keys 1-3,
  top scene = 1 (Marko: "What is at the top is one, middle is two"); a tap on key 2 made scene 2 OBS's live output
  (green on phone and deck). Marko swapped scenes himself after; the keys followed.
- The real deck (original 15-key, 0x0060, serial AL21I1C06271) has a **broken display** (Marko 6.11.2026): pictures look
  torn and black keys look blue. Judge it only roughly. Photographed through the Pixel's back camera
  (scratchpad deckshot.sh: scrcpy camera 2 s, last frame, clip deleted).
- Driver lessons v3-v5: the 7749-byte first page is right for this deck (8175 left keys empty); the reset command
  before each redraw is gone; a refused picture no longer causes a redraw loop.
- Stream Deck Control (Mantra) **removed** (Marko: "Delete one app so we have only one"): app deleted, star row and
  icon replaced by this app, repo stream-deck-control archived with an "obsolete" line.
- Not yet tested: same-Wi-Fi without the cable (needs Marko's one click: allow Local Network for the helper if macOS
  asks), the press-enlarge seen by eye on both (160 ms), the MK.2 path (no MK.2 here yet).
- Open question for Marko: how to switch profile on the real deck alone (it has no tabs).

## The plan

- **Stream Deck Remote** (Android, Kotlin + Compose, package com.mantra.streamdeckremote): a 5 × 3 deck like Marko's
  Elgato 15-key, mirrored with the real deck, profile tabs at the bottom: APPS (the application switcher) and OBS (one numbered key per scene).
- **Stream Deck Remote (Mantra)** (Mac, Swift): HTTP on port 8963 (MANTRA_PORTS name `streamdeck-remote`), Bonjour
  `_mantradeck._tcp` so the phone finds it on the same Wi-Fi without ADB; `adb reverse` over a USB cable as the fallback.
- OBS through obs-websocket v5 on 127.0.0.1:4455; the password is read from OBS's own config, never stored here.
