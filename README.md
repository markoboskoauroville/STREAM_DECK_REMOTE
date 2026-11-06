# Stream Deck Remote

Marko's Stream Deck on the phone: an Android app that looks like his Elgato 15-key deck (5 across, 3 down) and
drives this Mac through a small helper, **Stream Deck Remote (Mantra)**. Profiles are tabs at the bottom of the
phone; no editor yet, Marko names the profiles.

| Profile | What the keys do |
|---|---|
| **APPS** | the application switcher: every open app with its icon; a press brings it to the front and moves it to key 1; the app in front has a green bar; more than 15 apps → key 15 is NEXT |
| **OBS** | recognises when OBS is open; one key per scene, numbered 1, 2, 3… as OBS lists them, top first; a press makes it the live scene (green); OBS closed → key 1 opens it |

## How the phone reaches the Mac (no ADB needed)

1. **Same Wi-Fi:** the helper announces itself by Bonjour (`_mantradeck._tcp`, port 8963); the phone finds it.
   macOS 15 asks once to allow Local Network for the helper (Marko's click).
2. **Cable or wireless ADB:** the helper sets `adb reverse tcp:8963 tcp:8963` on every phone adb sees, so the phone
   finds the Mac at 127.0.0.1.
3. **Tailscale** (100.79.251.19) and **an address typed by hand** (tap the line at the top of the phone).

## The wire (HTTP, port 8963, MANTRA_PORTS name `streamdeck-remote`)

`GET /hello` · `GET /state?profile=apps|obs&v=N` (long poll, 8 s) · `GET /press?profile=…&key=0…14` · `GET /icon?id=<bundle id>`

OBS: obs-websocket v5 on 127.0.0.1 (port and password read from OBS's own `plugin_config/obs-websocket/config.json`).

## Built by GitHub only

- `android/` → workflow **Android APK** → release `v<N>` (`android/gradle.properties` appVersion), signed with the
  repository secret `ANDROID_DEBUG_KEYSTORE_B64`, so each version installs over the last one.
- `mac/` → workflow **Mac app** → release `mac-v<N>` (`mac/app/App.swift` VERSION). On the Mac:

      gh release download mac-v1 -R markoboskoauroville/STREAM_DECK_REMOTE -p app.zip -D /tmp/sdr --clobber
      ditto -x -k /tmp/sdr/app.zip /Applications && codesign --force -s "Mantra Apps" "/Applications/Stream Deck Remote (Mantra).app"
