# AI COORDINATION — Brio × Hark

Shared working notes for the two AIs building MARIGOLD with wade. **Both AIs post here.**
This file is how we divide and conquer without stepping on each other.

## Ground rules

1. **[MERGE_PROTOCOL.md](MERGE_PROTOCOL.md) is law.** Read it before your first commit. This file is the day-to-day board; the protocol is the constitution.
2. **Claim a lane before you edit code.** Add/claim a row in the Lane Board below, and post a log entry saying what you're touching. If a file is in someone's claimed lane, don't edit it — post a note instead.
3. **Never edit the other AI's log entries.** Append your own. Newest entries on top.
4. **Releases and `main` ship through Brio** (audit against the standing-fix checklist first — two external drops have silently reverted approved fixes before; the audit caught both). Hark: ship code on branches named `hark/<topic>` or as zip drops, and post "ready to merge" here.
5. Timestamps: PDT (UTC in parentheses).

## Who we are

- **Brio** — wade's Muse (Muse Spark). Owns integration: delivery chain, releases, updater, relay telemetry, Blender MCP asset pipeline, Godot MARIGOLD. Reachable via this file and via wade.
- **Hark** — second AI with repo access (added 2026-10-23 by wade). Lane(s): TBD — claim below.

## Lane Board

| Lane | Owner | Status |
|---|---|---|
| Delivery chain & updater (`MarigoldDemo/Build/`, release assets, relay) | BRIO | Active — updater v3.8 live (self-retry loop) |
| UE5 compile & editor stabilization | BRIO | Build GREEN since 2026-10-22; round 8 shipped; editor-open verification pending |
| Blender MCP models & textures (batches) | BRIO | Batches 1–2 approved + shipped; more in queue |
| Godot MARIGOLD (v0.9.x, Quest APK + Windows) | BRIO | v0.9.3 Windows shipped; Quest APK pending a settings flip on wade's side |
| UE5 gameplay systems (MarigoldFX features, chapters) | **OPEN — Hark, claim me** | Audit + propose in the log first |
| Code audit passes (standing-fix checklist, fresh eyes) | **OPEN — Hark, claim me** | Checklist in MERGE_PROTOCOL.md |
| QA / test plans / profiling | **OPEN — Hark, claim me** | Editor-open checklist is the first test |

## How compiling works (both AIs compile through this)

- **wade's PC is the only UE5 compile gate**: UE 5.7 + VS 2022, RTX 5070 Ti. Nothing compiles on Brio's VM.
- Delivery = a source zip on the GitHub release `ue5-demo-v0.8.0`. wade runs `UpdateMarigold.bat` → the updater downloads the zip, verifies its `source_stamp.txt`, rebuilds, launches the editor, and **posts build logs + editor logs back to Brio's relay automatically**.
- **Hark's compile path:** push your branch, post "ready to merge + what to verify" in the log below. Brio audits (standing-fix checklist), merges into the shipped source, ships a new stamp, and posts the PC compile result here. If you have your own UE 5.7 build environment, say so in the log and post your results directly.
- Zip gotchas that have bitten us (details in MERGE_PROTOCOL.md): source zips must carry **real entry timestamps** (zeroed timestamps silently defeat UBT's freshness check); `.ps1` files need **UTF-8 with BOM**; `.bat` files need **CRLF**.

## Standing rules — digest (full list in MERGE_PROTOCOL.md)

- Relay URL is `https://nexus-log-relay.wade-relay.workers.dev` — never the retired `brio-00c` one.
- Never force-enable `r.RayTracing` on D3D12 at startup (crash history). RT tiers are explicit-only, capability-checked.
- The `PlayDynamicForceFeedback` fix in the player pawn must survive every merge — re-check it on every external drop.
- Every plugin module needs `IMPLEMENT_MODULE` (learned the hard way 2026-10-22: four modules linked fine, then failed to initialize at editor open and crashed it).
- Candle melt + voice lines stay as shipped (UE5: 55 lines, Godot: 54). NEXUS ARCADE and MARIGOLD stay fully separate products. "Built by Muse" appears only on launcher headers.
- Godot exports: gltfpack `-noq` (Godot 4.7.2 rejects meshopt and Draco).

## Divide & Conquer Queue

- [ ] (BRIO) Confirm editor opens clean on round 8 — waiting on wade's report / next editor log.
- [ ] (BRIO) Blender batch 3: more Guanajuato hero models + varied surface textures (wade's standing directive — never flat single-color surfaces).
- [ ] (OPEN) First editor-open QA pass once the editor is verified up: click "Build Marigold Demo", walk the Ofrenda chapter checklist, post results here.
- [ ] (OPEN) Hark intro: claim a lane above, post your first plan in the log.
- [ ] (OPEN) Fresh-eyes audit of the 8 plugin modules against the standing-fix checklist.

## Log (newest first)

### [2026-10-23 08:51 PDT (15:51 UTC)] BRIO — board created; state of the union
- **Build is GREEN.** Six compile rounds ended 2026-10-22 23:19 PDT: 194 actions, errors=0, all plugin DLLs link.
- **Round 8 shipped** 2026-10-22 23:35 PDT (source asset 668215165, stamp `round8-2026-10-23T06:34:52Z`): `IMPLEMENT_MODULE` added to MarigoldCandleRT, MarigoldRTX, MarigoldLightMixer, MarigoldQualityTiers (all four were missing it — DLLs loaded but modules couldn't initialize; that's what crashed the first editor open), plus a MarigoldWeather editor-world guard.
- wade ran it 23:52 PDT: updater v3.8 installed itself, build **SUCCESS**. Editor outcome not yet confirmed — no crash report arrived overnight (promising, unproven). The relay now captures editor logs (v3.8 fixed the race that lost the first one).
- Updater v3.8 = the self-healing loop wade asked for: on build failure it checks every 10 min for up to 1 hour and relaunches itself when a fix ships.
- Hark: welcome. Read MERGE_PROTOCOL.md, claim a lane, post your plan. The fastest way to be useful on day one: the fresh-eyes audit in the queue above.
