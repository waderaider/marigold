# MARIGOLD v0.6.2 — "The Menu Fix" (2026-10-09)

Launcher-rework cycle driven by wade's Quest 3 headset photo: the v0.6.1 menu
RENDERED but buttons were clipped at the right edge ("Begin Jo…", "Mode:
Immer…") and NO laser pointer was visible — nothing was selectable.

## The headline: one simple 2D list (wade's LAUNCHER LAW)
- **One panel, one scrollable list.** Two passive headers: **STORY CHAPTERS**
  (ch1→ch5 in story order) then **EXPERIENCES** (Mano Magica, Guitarra, Pinta,
  Espejo, Galeria, Tu Ofrenda — finale last). Every row: "Name — built by
  Muse" (wade's permanent branding directive) + one-line description.
- **Deleted:** Journey/Experiences tabs, Continue-Journey hero button, chapter
  preview cards/key art, mode toggle (**defaults to immersive** — AR mode is
  gone from the menu; chapters still honor `MarigoldState.ar_mode`), the
  Sky & Weather time-of-day row (menu no longer owns the sky), papel banners
  in the menu (the pattern stays in-game).
- **Kept:** version badge, prominent CHECK FOR UPDATES button, Room setup
  button (now a small dialog: "Center panel on me" + where to find the
  Quest's own room capture).
- Explicit ▲▼ scroll buttons with hold-to-repeat (laser-scroll; injected
  clicks are press+release, so drag-scroll is deliberately not relied upon).
- New palette: bg #1B0F1E, panel #2A1626, cream #FFF6E8, marigold #FF9E1B,
  terracotta #E4572E, dim #D8BFA8. Opaque StyleBoxFlats, default font only,
  instant color-swap selection (text → #1B0F1E on accent).

## Panel framing (the photo bug — fixed, not worked around)
- Menu quad is now **0.96×1.28 m at 2.0 m**, yaw-aligned to the LIVE HMD
  forward on every menu open (+0.75 s re-settle one-shot, because the pose is
  often identity at boot). The old build parked the quad at a fixed
  tracking-space offset with NO recenter — any play-space offset clipped the
  buttons.
- A 0.5 s guard tick pushes the panel out to 1.5 m when closer than 0.8 m
  and recenters it when >30° off-axis.

## Input: belt and suspenders (the #1 bug)
- **NEW `DirectUIInput`** (`scripts/shared/direct_ui_input.gd`): independent
  per-frame fallback — name-agnostic controller discovery, raycast from each
  live controller's raw tracker pose + hand-tracker pinch, clicks on
  trigger/pinch rising edges. Draws its own bright-yellow beams (10 mm,
  energy 5) so wade sees where he's pointing even if the primary path dies.
- Primary `XRUIPointer` lasers thickened (4→8 mm) and brightened (2→4 energy),
  hit dots doubled; both paths always run through ONE deduped click funnel
  (120 ms / 8 px) — never double-fires.
- Gaze dwell (1.2 s) now fires only when NO beam is drawn by either path in
  the last 0.25 s — keyed on pixels, never on tracker registration (a
  live-but-useless tracker used to hide the reticle while the lasers were
  invisible: zero input).
- Trigger accessor hardened against the action map typings (verified in
  `openxr_action_map.tres`): float-typed `trigger` via `get_float`, boolean
  `trigger_click` via `is_button_pressed` — never crossed.

## On-screen diagnostics (ship-blocker)
- Plain-words input-state line, refreshed every 0.5 s: controllers (L+R
  live/none), hands, gaze, panel distance, "Boot: first frame Xs".
- ⚠ NO INPUT SOURCE LIVE warning when XR is up but nothing is live and no
  beam is drawn — the photo-state is now self-reporting; wade can read it back.
- **Test connection** button POSTs a ping to the relay (8 s timeout,
  non-blocking) and shows "Connection: SUCCESS" / "Connection: FAILED" —
  device-egress ground truth.

## Telemetry fix (prime suspect for zero reports ever arriving)
- The relay URL is now a **compiled-in fallback constant** in
  `GameplayTelemetry` (POST /report needs no key — the read key is
  server-side only). It was empty until the async `version.json` fetch
  completed; if the headset couldn't reach raw.githubusercontent.com, every
  report sat in the queue forever. The remote manifest can still override it.

## Boot speed (first frame < 2 s)
- **Stage 0** (`Main._ready`): XR init first, then panel + quad + one
  "LOADING" label — flat colors, default font.
- **Stage 1** (deferred): list UI, pointers, fallback, recenter.
- **Stage 2** (deferred): music node, updater. Altar decor deferred.
- `MarigoldSky` and the menu backdrop build on **chapter load** (chapters use
  `MarigoldSky.instance` null-safely); the menu uses a flat backdrop.
- `MarigoldMusic`: the 4 mood WAVs now lazy-load on first `play_mood` (the
  old `_ready` loaded them synchronously).

## Pause menu rework
- New order: **Continuar (Resume, green)** / **Controles (Controls, blue)** /
  **Reiniciar (Restart, orange)** / **◀ Prev name / Next name ▶ row (NEW —
  same 11-item list order, wraps)** / **SALIR AL INICIO (EXIT) (red,
  full-width, bottom, unmissable)**.
- Pause title now shows the current chapter/experience name (Restart's target
  is obvious).
- **Real bug fixed:** the old `_on_pointer_clicked` only noted the input
  method and never pushed the click into the viewport — laser clicks in the
  pause menu did nothing. Both paths now funnel through one deduped injector.
- DirectUIInput re-targets between the floating exit quad and the pause panel
  on open/resume. Pause panel yaw-aligns to the HMD at 1.8 m on open.

## Notes for wade's device checklist
1. Version badge reads **v0.6.2**; whole panel visible with margin.
2. Yellow or orange laser visible from each controller when the menu appears.
3. Trigger click launches a chapter; ▲▼ scroll the list.
4. Diagnostics line reads back input state; Test connection → SUCCESS.
5. Walk toward the panel: it pushes back out. Look away 30°+: it recenters.
6. In-chapter: menu button → pause → SALIR AL INICIO (EXIT) unmissable at
   bottom; laser works there too.

## Known / unchanged
- NOT Quest-tested (headless-verified only): parse checks on every touched
  .gd + 60-frame headless menu run, zero script errors.
- Mode toggle removed: the app always starts immersive now. AR mode code
  remains (`set_ar_mode`) but has no menu UI; chapters still apply
  `MarigoldState.ar_mode`.
- Time-of-day selector removed from the menu. The sky still supports it;
  a future cycle can re-add the UI at zero cost.
