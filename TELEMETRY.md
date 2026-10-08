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
| `chapter_start` | `chapter` (display name), `key` (e.g. `"ch1"`, `"pinta"`), `via` (`"menu"`\|`"restart"`\|`"complete"`) | `_load_chapter` / `_load_experience`; a new session auto-ends any open one with `exit`=`via` |
| `chapter_end` | `chapter`, `key`, `duration_s` (float, 0.1s), `exit` (`"quit_to_menu"`\|`"restart"`\|`"completed"`\|`"app_close"`), `input_method` (first-used, `""` if none) | quit/restart/complete/close; idempotent |
| `pause_open` | `chapter` | pause overlay opened (menu button / Esc / floating button) |
| `input_method` | `chapter`, `method` (`"controllers"`\|`"hands"`\|`"gaze"`\|`"mouse"`) | first input used in a chapter session (first wins) |
| `error` | `chapter`, `message` (≤160 chars), `context` (≤160 chars, optional) | error breadcrumbs with chapter context (e.g. scene load failure) |

## Weekly-digest queries this supports

- **Quit in <30s** → `chapter_end` with `duration_s < 30` grouped by `chapter` (feeds the quality bar — a chapter players bail on fast is a chapter that needs work).
- **Replayed chapters** → `chapter_start` with `via="restart"` counts per `chapter`.
- **Where players pause/quit** → `pause_open` counts per `chapter`; `chapter_end.exit` distribution.
- **Hands vs controllers vs gaze** → `input_method` / `chapter_end.input_method` distribution.
- **Error hotspots** → `error` events grouped by `chapter` + `message`.
