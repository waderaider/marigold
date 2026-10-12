# MARIGOLD — Gameplay Telemetry

Permanent system (v0.6.1+). The `GameplayTelemetry` autoload
(`scripts/shared/gameplay_telemetry.gd`) batches gameplay events in memory
and POSTs them as tiny JSON payloads to the **same Cloudflare relay** as
crash reports (`POST /report`, `report_url` from `version.json`).

- Flush cadence: every 60s + on every `chapter_end` + on app close.
- Transport: async `HTTPRequest` — gameplay never blocks on network.
- Offline/URL-less: events stay in a 300-event in-memory ring (oldest dropped).
- Privacy: gameplay events ONLY. No personal data, no audio/video, no room-scan
  data. Identifiers are limited to what crash reports already carry
  (device model, platform, headset type, app version).

## Envelope (every POST)

| Field | Meaning |
|---|---|
| `app` | `"MARIGOLD"` (required by the relay) |
| `kind` | `"gameplay_telemetry"` (distinguishes from crash reports) |
| `version` / `version_code` | app version, e.g. `"0.6.1"` / `7` |
| `device` / `platform` / `headset` | e.g. `"Quest 3"` / `"Android"` / `"OpenXR"` |
| `session_id` | random per app launch, e.g. `"20261008_143022_41793"` |
| `timestamp` | ISO-8601 UTC of the flush |
| `events` | array of event objects (below) |

## Events

Every event object has `t` (unix time, float) and `name` (string), plus
name-specific fields:

| Event `name` | Fields | When |
|---|---|---|
| `chapter_start` | `chapter` (display name), `key` (e.g. `"ch1"`, `"pinta"`), `via` (`"menu"`\|`"restart"`\|`"complete"`\|`"nav"`) | `_load_chapter` / `_load_experience`; a new session auto-ends any open one with `exit`=`via` |
| `chapter_end` | `chapter`, `key`, `duration_s` (float, 0.1s), `exit` (`"quit_to_menu"`\|`"restart"`\|`"completed"`\|`"app_close"`\|`"nav"`), `input_method` (first-used, `""` if none) | quit/restart/complete/close/nav-jump; idempotent |
| `menu_open` | `version`, `controllers` (e.g. `"L+R live"`), `hands`, `xr` (bool), `headset` | **v0.7.0** — logged once at menu boot (stage 1) with an immediate flush; makes menu-only sessions visible (fixes the zero-phone-home gap) |
| `pause_open` | `chapter`, `via` (`"menu_button"`\|`"exit_button"`\|`"esc"`) | **v0.7.0** — pause overlay opened; `via` attributes the source so the digest can tell accidental taps from real opens |
| `teleport` | `via` (`"laser"`), `dist` (m, 0.1s) | **v0.7.0** — laser-pointer teleport fired |
| `input_method` | `chapter`, `method` (`"controllers"`\|`"hands"`\|`"gaze"`\|`"mouse"`) | first input used in a chapter session (first wins) |
| `error` | `chapter`, `message` (≤160 chars), `context` (≤160 chars, optional) | error breadcrumbs with chapter context (e.g. scene load failure) |

## v0.7.0 additions

- **Crash parity**: the `BugReporter` autoload (ported from NEXUS) writes
  session logs + clean-exit flags and POSTs crash reports to the same relay.
  Sessions start/end with each chapter/experience load (`main.gd`); a pending
  crash from the previous session auto-sends on menu boot (MARIGOLD has no
  crash-prompt UI).
- **Headset model**: every report envelope's `headset` field now carries the
  real model via `XR_META_headset_id` (`OpenXRMetaHeadsetIDExtension`), with
  fallback to the interface scan on desktop. Also shown on the menu's
  on-screen diagnostics line and in the Test-connection ping.
- **`environment_depth`** enabled for passthrough folk scenes (matches NEXUS).

## Weekly-digest queries this supports

- **Quit in <30s** → `chapter_end` with `duration_s < 30` grouped by `chapter` (feeds the quality bar — a chapter players bail on fast is a chapter that needs work).
- **Replayed chapters** → `chapter_start` with `via="restart"` counts per `chapter`.
- **Where players pause/quit** → `pause_open` counts per `chapter`; `chapter_end.exit` distribution.
- **Hands vs controllers vs gaze** → `input_method` / `chapter_end.input_method` distribution.
- **Error hotspots** → `error` events grouped by `chapter` + `message`.
