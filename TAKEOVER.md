# TAKEOVER: Stream Deck Remote

Written as we go, after every major step (Marko, 6.11.2026: "After every major step, write automatically take over
document. Don't wait for closing of the session.").

## Where it stands (6.11.2026, step 3: one engine for the real deck and the phone, v2)

- Step 1: repository, requests word for word (momentaryupdates.md).
- Step 2: v1 built green by GitHub (APK release v1, Mac release mac-v1): phone deck with APPS/OBS tabs + Mac helper.
- Step 3 (request 3, "they reflect each other's actions"): the Mac helper now also drives the real Elgato deck over
  USB (Deck.swift from STREAM_DECK_CONTROL, plus MK.2 / original v2 support because a new deck is coming). One
  Engine (mac/app/Engine.swift) holds the profile and the 15 keys; both faces show it, both press it; a press
  enlarges the key to 118 % on both, then acts. Phone tabs switch the profile of both. APPS layout = Stream Deck
  Control v3 (apps 1–12, NEXT, F1, F2). The helper quits Stream Deck Control (Mantra) at start (one holder of the deck).
- Next: v2 green → install mac-v2 → APK v2 on the Pixel 7 emulator → screenshots → Marko plugs in the deck.
- Open question for Marko: how to switch profile on the real deck alone (it has no tabs).

## The plan

- **Stream Deck Remote** (Android, Kotlin + Compose, package com.mantra.streamdeckremote): a 5 × 3 deck like Marko's
  Elgato 15-key, mirrored with the real deck, profile tabs at the bottom: APPS (the application switcher) and OBS (one numbered key per scene).
- **Stream Deck Remote (Mantra)** (Mac, Swift): HTTP on port 8963 (MANTRA_PORTS name `streamdeck-remote`), Bonjour
  `_mantradeck._tcp` so the phone finds it on the same Wi-Fi without ADB; `adb reverse` over a USB cable as the fallback.
- OBS through obs-websocket v5 on 127.0.0.1:4455; the password is read from OBS's own config, never stored here.
