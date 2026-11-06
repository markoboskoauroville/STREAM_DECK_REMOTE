# LESSONS: Stream Deck Remote

- (6.11.2026, from MACOS_TASK_SWITCHER) A listener in a signed app on macOS 15 gets nothing from the home Wi-Fi until
  Local Network is allowed for it; 127.0.0.1 (adb reverse) and Tailscale always work. Hence three ways to the Mac.
- (6.11.2026) OBS's GetSceneList returns the scenes bottom first (sceneIndex 0 = the lowest in the Scenes dock);
  turned so key 1 is the top scene, as Marko sees them.
- (6.11.2026) Marko's original deck has a broken display: torn pictures and blue "black" keys are the hardware.
  The same picture looked torn under Stream Deck Control too. Test it roughly; the phone is the exact face.
- (6.11.2026) The original deck: first page 7749 bytes of BMP, the rest on page 2 (8175 per page left keys empty).
  Never send the reset feature report right before pictures; and never redraw on a refused picture (a loop).
