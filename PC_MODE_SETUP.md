# MARIGOLD — PC Mode Setup (v0.8.0)

One Windows exe, two ways to play. Choose at boot (or any time in
Settings → Mode; the switch takes effect on restart).

## Play on PC (desktop monitor)

- **Move:** WASD or arrow keys · **Look:** mouse · **Sprint:** Shift
- **Interact:** left-click — light candles, grab petals, paint, strum
- **Teleport:** aim the crosshair at the ground until the marigold-petal
  ring appears, then **right-click**
- **Pause / settings:** Esc
- First boot defaults to Ultra graphics (built for the RTX 5070 Ti).
  Fullscreen, resolution, mouse sensitivity and invert-Y are in the
  pause-menu Settings (Esc → Ajustes).

Tips:

- The menu follows your view while you walk — it never gets lost.
- Espejo (the mirror dance) needs a headset for body tracking, so it is
  dimmed in PC mode. Everything else plays fully with mouse + keyboard.
- Force a mode from the command line: `Marigold.exe --pc` or
  `Marigold.exe --vr`.

## Play in VR — Quest via Virtual Desktop

Pick "Play in VR" at boot with Virtual Desktop streaming from this PC.
Laser pointer + trigger to select, marigold-petal-ring teleport, pinch
and hand tracking all work exactly as on the Quest standalone build.
If no headset is found, the boot screen says so and lets you pick PC
instead — it never hangs.

## Troubleshooting

- **Mouse stuck / invisible:** press Esc (opens pause, frees the cursor).
- **Wrong mode after an update:** Esc → Ajustes → Modo → pick PC or VR,
  then restart the app.
- **Menu too small / big:** it's a fixed 1.35x scale on desktop; walk
  closer or farther — it follows you.
- Check for Updates is in the main menu (Windows builds report new
  versions; download the new zip from the release page).
