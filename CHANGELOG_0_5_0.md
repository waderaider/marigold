# MARIGOLD v0.5.0 — Changelog

## NEW: Mano Magica (hand-tracking tour)
A guided tour of your own hands through six gestures: pinch a marigold bud until it blooms, grab a light orb and carry it to the stone bowl, throw petals at the paper ring, sculpt clay by pinching and moving, conduct bells with hand sweeps (height sets the pitch), and pet an alebrije spirit guide until it purrs. Every station gives haptic + audio feedback and advances early when you nail the gesture. Works with real hand tracking, controller trigger, or mouse.

## NEW: Gran Baile — Espejo (mirror dance)
Three calavera dancers (La Catrina, El Charro, La Dama) mirror YOUR real body moves: lean, crouch, sway, turn — they follow. Your hands show up as glowing orbs in front of each dancer so you can see it's really you. Uses Meta body tracking with heavy smoothing so joint noise never makes the dancers twitch; falls back gracefully to hands-only, then to a beat-synced auto-dance.

## Pause menu is now universal (ship-blocker fixed)
Every chapter and experience — all 5 chapters, Guitarra, Mano Magica, Espejo — now gets the shared pause overlay: press the controller Menu button (or Esc / the floating pause button) for Resume, Restart, Controls legend, and Quit to Menu. The floating exit button follows your view; pause freezes gameplay and works with controller laser, hand pinch, gaze dwell, and mouse.

## Ofrenda Viva night sequence (ch1)
Finish the ofrenda and night falls: the three photos ignite one by one with chimes and the names of your loved ones, five calavera dancers rise from the ground and dance beat-synced around you, marigold petals fall from the ceiling, and one dancer bows to you. Candlelight deepens to a warm amber grade — no extra lights, just grading.

## Ofrenda hero props (in-house Blender)
The ch1 altar now uses the full custom Blender ofrenda set: pan de muerto hero loaves (5,704 tris, replacing the procedural ones with procedural fallback), three candle heights (tall/mid/short) with flame VFX wired to each model's `FlameAnchor` at the wick tip, two tall decorative candles flanking tier 1, painted calavera skulls flanking the altar, ornate photo frames on tier 2, and a tileable marigold garland draped across the tier-1 edge.

## El Gran Baile dancers now move to the beat
The ch5 troupe and the dance leader hop, sway, and spin on the actual music beat (120 BPM finale), decaying through each bar — with a free groove when the music is silent.

## Weather answers gameplay
Rain ripples the ch2 bridge water in real time; wind gusts push Guitarra's petals, ripple banners, sway flowers, and make lantern flames dance; storms dim the ch5 finale lighting. Guitarra keeps gentle weather while you play.

## Petal-fall transitions + ambient life everywhere
No more hard cuts: a curtain of marigold petals falls between chapters. Butterflies and horizon spirits now drift through every chapter and experience.

## Controller skins + controls legend
Styled virtual controllers (with per-experience accessories: guitar pick, magic spark, marigold ring) render over your real controllers, with a controls card at the start of each chapter — re-openable anytime from the pause menu's Controls page.

## Technical
- Android targetSdk 34 (was unset)
- Version badge + update checker unchanged; all original music, all CC0/in-house assets

Not Quest-tested — feedback from the headset is welcome, as always.
