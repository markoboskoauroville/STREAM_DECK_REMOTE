# TAKEOVER: Stream Deck Remote

Written as we go, after every major step (Marko, 6.11.2026: "After every major step, write automatically take over
document. Don't wait for closing of the session.").

## Where it stands (6.11.2026, step 1: the repository)

- Repository made, requests saved word for word in momentaryupdates.md.
- Next: the Android app (android/) and the Mac helper (mac/), both built by GitHub Actions only.

## The plan

- **Stream Deck Remote** (Android, Kotlin + Compose, package com.mantra.streamdeckremote): a 5 × 3 deck like Marko's
  Elgato 15-key, profile tabs at the bottom: APPS (the application switcher) and OBS (one numbered key per scene).
- **Stream Deck Remote (Mantra)** (Mac, Swift): HTTP on port 8963 (MANTRA_PORTS name `streamdeck-remote`), Bonjour
  `_mantradeck._tcp` so the phone finds it on the same Wi-Fi without ADB; `adb reverse` over a USB cable as the fallback.
- OBS through obs-websocket v5 on 127.0.0.1:4455; the password is read from OBS's own config, never stored here.
