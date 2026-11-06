# TAKEOVER: Stream Deck Remote

Written as we go, after every major step (Marko, 6.11.2026: "After every major step, write automatically take over
document. Don't wait for closing of the session.").

## Where it stands (6.11.2026 ~20:55, step 5)

- Installed and tested: Mac helper **v5**, APK **v2** (see LESSONS for the deck's quirks). Pushed, building on GitHub:
  APK **v3** (ROTATE button: portrait = line to the Mac + deck + tabs + ROTATE; landscape = immersive, only the deck,
  small ROTATE in the corner; turning the phone rotates too, ROTATE holds against the sensor until the phone is
  really turned) and Mac helper **v6** (OBS order re-read at every scene change and every 2 s).
- OBS rule (Marko, 6.11.2026, request 5): keys are **absolute positions in OBS's Scenes dock**: key 1 = the top scene,
  key 2 the next, key 3 the one below. The live scene only lights its key (green); keys never follow a scene around;
  a reorder in the dock shows within 2 s. Code: mac/app/OBS.swift (`scenes` sorted top first, `layout()`).
- Stream Deck Control (Mantra) removed; its repo archived. The real deck's display is broken (hardware).
- Icons (Marko, request 6-7): APK launcher icon and the Mac icon are near-black with quietly glowing keys (APK v4, Mac v7); rule in MANTRA_MANIFEST modules/app-icon.md.
- Next: v3/v6 green → install both → test ROTATE on the Pixel (screenshots of both orientations) → check the key order
  against OBS's dock (screenshot of OBS) → ask Marko to swap two scenes in the dock and see the keys follow.
- Not yet tested: same-Wi-Fi without the cable (Local Network click is Marko's), MK.2, the press-enlarge by eye.
- Open question for Marko: how to switch profile on the real deck alone (it has no tabs).

## The plan

- **Stream Deck Remote** (Android, Kotlin + Compose, package com.mantra.streamdeckremote): a 5 × 3 deck like Marko's
  Elgato 15-key, mirrored with the real deck, profile tabs at the bottom: APPS (the application switcher) and OBS (one numbered key per scene).
- **Stream Deck Remote (Mantra)** (Mac, Swift): HTTP on port 8963 (MANTRA_PORTS name `streamdeck-remote`), Bonjour
  `_mantradeck._tcp` so the phone finds it on the same Wi-Fi without ADB; `adb reverse` over a USB cable as the fallback.
- OBS through obs-websocket v5 on 127.0.0.1:4455; the password is read from OBS's own config, never stored here.
