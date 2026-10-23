# MARIGOLD UE5 — Round-8 fresh-eyes audit (static read, NO compile)

- **Source audited:** `MarigoldDemo-v0.8.0-source.zip`, release `ue5-demo-v0.8.0`, asset **668215165** (5,505,936 bytes, uploaded Thu 2026-10-22 23:35 PDT), sha256 `f4e4ffb4f855953c0fc827e707bf913ac77dffd72e410c077044e1998e868d44`
- **source_stamp.txt (actual):** `round8-2026-10-23T06:34:52Z` ✅ matches the expected stamp. `VERSION` = `ue5-demo-v0.8.0`.
- **Rules read:** repo-root `MERGE_PROTOCOL.md` and `AI_COORDINATION.md` (main, fetched 2026-10-23 ~08:58 PDT).
- **Method:** grep/parse plus a manual read of every module's entry point, its Build.cs and .uplugin, the RT code path, the subsystems, and the scripts. **Nothing was compiled or run.** Wade's PC is the only compile gate. Anything marked "needs PC confirm" is inference.
- Nothing in the source tree was modified, and nothing was pushed or posted to the board. Proposed fixes live only under `audit_round8/fixes/` plus the patch files.

## Summary verdict

**Mostly clean. Two standing rules fail, and there are a few smaller items.**

The round-8 module fix is complete. All 8 plugin modules and the game module have exactly one correct `IMPLEMENT_MODULE` / `IMPLEMENT_PRIMARY_GAME_MODULE`. Dependencies are guarded. The relay URL is clean. The force-feedback fix, candle melt and all 55 voice lines are intact. Static reading found nothing that should crash the **editor** on open.

The two rule failures:

1. **Ray tracing (FAIL, Crash-class for game sessions).** `DefaultEngine.ini:22` has `r.RayTracing=True` in `[/Script/Engine.RendererSettings]`. Worse, `MarigoldRTXSettings.cpp:211-229` **auto-enables the FULL RT tier at startup** the first time a game session boots on flat PC with an RTX 40/50 on D3D12. That is Wade's 5070 Ti. FULL includes `r.Lumen.HardwareRayTracing=1`, the exact HWRT config behind the 887A002B crash on 2026-10-16. A crash guard turns RT off *after* a crash, but the first standalone/packaged launch can still crash. This contradicts "RT tiers are explicit-only" in AI_COORDINATION and "MarigoldRTX must NOT force-enable…" in MERGE_PROTOCOL. The code comment cites a 2026-10-20 owner directive ("max it"), so **Wade needs to decide which rule wins**.
2. **`.ps1` encoding (FAIL).** 3 of 5 `.ps1` files have no BOM: `CrashWatchdog.ps1`, `AnalyzeRenderLog.ps1` and `SendBuildLog.ps1`. Two of them have em-dashes inside double-quoted strings, which is the exact PowerShell 5.1 parse-killer the protocol describes. `CrashWatchdog.ps1` probably never parses, and the updater's `try/catch` hides that (details in F2). So **"no crash report overnight" is weaker evidence than it looks**, on the paths that use the watchdog.

---

## Module table

| Module | Plugin | Type / Phase | IMPLEMENT_MODULE | Deps OK | Notes |
|---|---|---|---|---|---|
| MarigoldDemo (game) | — (.uproject) | Runtime / Default | `IMPLEMENT_PRIMARY_GAME_MODULE(FMarigoldDemoModule, MarigoldDemo, "MarigoldDemo")` `Source/MarigoldDemo/MarigoldDemo.cpp:18` | ✅ Core/CoreUObject/Engine/InputCore/MarigoldFX (`MarigoldDemo.Build.cs:13-20`) | Thin module. Class name `MarigoldDemo` matches. Both Target.cs files add it (`MarigoldDemo.Target.cs:11`, `MarigoldDemoEditor.Target.cs:11`). |
| MarigoldBuilder | MarigoldBuilder | **Editor** / PostEngineInit | `MarigoldBuilderModule.cpp:26` | ✅ UnrealEd, LevelEditor, ToolMenus, MaterialEditor are fine for an Editor module | Depends on modules `MarigoldFX` (`Build.cs:22`) and `MarigoldPreFlight` (`Build.cs:49`), but `MarigoldBuilder.uplugin` declares neither plugin, only ProceduralMeshComponent. UBT warns about this (Hygiene, fixed in patch). |
| MarigoldCandleRT | MarigoldCandleRT | Runtime / Default | `MarigoldCandleRT.cpp:22` (round-8 fix) | ✅ Core/CoreUObject/Engine | Telemetry header via include path only. |
| MarigoldFX | MarigoldFX | Runtime / Default | `MarigoldFX.cpp:17` | ✅ MaterialEditor guarded by `if (Target.bBuildEditor)` (`MarigoldFX.Build.cs:46-49`), and `MaterialEditingLibrary.h` is under `#if WITH_EDITOR` (`MarigoldMaterialFactory.cpp:38-49`) | The .uplugin lists EnhancedInput, QualityTiers, LightMixer, ProcMesh and AudioCapture (Optional). |
| MarigoldLightMixer | MarigoldLightMixer | Runtime / Default | `MarigoldLightMixer.cpp:21` (round-8 fix) | ✅ +HeadMountedDisplay (private) | — |
| MarigoldPreFlight | MarigoldPreFlight | **Editor** / PostEngineInit | `MarigoldPreFlight.cpp:24` | ✅ UnrealEd/Blutility/ToolMenus/ContentBrowser are fine for an Editor module. MarigoldRTX is declared in the .uplugin. | `UMarigoldPreFlightAutoFix::Get()` in StartupModule is rooted and guarded by `GIsRequestingExit` (`MarigoldPreFlightAutoFix.cpp:22-43`). |
| MarigoldQualityTiers | MarigoldQualityTiers | Runtime / Default | `MarigoldQualityTiers.cpp:77` (round-8 fix) | ✅ +RHI | StartupModule returns early when `GIsEditor` (`:37-40`). Never writes RT CVars (grep confirms). |
| MarigoldRTX | MarigoldRTX | Runtime / Default | `MarigoldRTX.cpp:250` (round-8 fix) | ✅ +RHI | StartupModule returns early when `GIsEditor` (`:137-140`). See F1 for the startup RT default. |
| MarigoldTelemetry | MarigoldTelemetry | Runtime / **PreDefault** | `MarigoldTelemetryModule.cpp:61` | ✅ UnrealEd guarded by `if (Target.bBuildEditor)` (`Build.cs:34-37`), and `FEditorDelegates` use is under `#if WITH_EDITOR` (`PlaySessionLogger.cpp:37,109,144`) | Installs a process crash handler at PreDefault (see F4). |

- **.uproject:** all 8 Marigold plugins are present and `Enabled: true` (`MarigoldDemo.uproject` "Plugins").
- **Folders and Build.cs:** every module named in a .uplugin has `Source/<Name>/<Name>.Build.cs`, and the class name matches.
- **Exactly one IMPLEMENT macro per module.** The other grep hits are comments only.
- No UnrealEd or editor-module dependency in any Runtime module without a `bBuildEditor` guard.

## Standing-fix table

| # | Check | Status | Evidence |
|---|---|---|---|
| 1 | IMPLEMENT_MODULE once per module, names match, StartupModule exists | **PASS** | See the module table. All 9 modules define StartupModule/ShutdownModule. |
| 2 | .uplugin Type/Phase, editor deps guarded, every module has a folder and Build.cs, plugins enabled in .uproject | **PASS** (1 hygiene WARN) | Builder .uplugin is missing its MarigoldFX/MarigoldPreFlight plugin deps: `MarigoldBuilder.uplugin` vs `MarigoldBuilder.Build.cs:22,49`. |
| 3 | Relay URL is `https://nexus-log-relay.wade-relay.workers.dev` everywhere, no `brio-00c` | **PASS** | `Build/CrashWatchdog.ps1:30`, `Build/MarigoldUpdater.ps1:59`, `Build/SendBuildLog.ps1:22`, `Build/UpdateMarigold.ps1:42`, `MarigoldCrashReporter.cpp:542` (WinHttpConnect host + HTTPS port + WINHTTP_FLAG_SECURE), `PlaySessionLogger.cpp:41`. The only `brio-00c` hit is a CHANGELOG line saying it is gone (`CHANGELOG.md:15`). Updater URLs are pinned to `ue5-demo-v0.8.0` (`MarigoldUpdater.ps1:57`, `UpdateMarigold.ps1:112`, both .bat). The release copies of `UpdateMarigold.ps1`/`MarigoldUpdater.ps1` are byte-identical to the zip copies. |
| 4 | No forced ray tracing on D3D12; RT explicit and capability-checked | **FAIL** | `Config/DefaultEngine.ini:22` `r.RayTracing=True` in `[/Script/Engine.RendererSettings]`, with `:98-100` `EnableOnDemand=1`, `Enable=0`, `Shadows=0`. The capability check is good: `MarigoldRTXSettings.cpp:40-62` uses `GRHISupportsRayTracing && IsD3D12 && r.RayTracing`. **But** the first-boot auto-default to Full is at `MarigoldRTXSettings.cpp:211-229`, called from the startup hook `MarigoldRTX.cpp:149-152` (OnPostEngineInit), and writes the RT CVars at `MarigoldRTX.cpp:208-215`. The editor is exempt (`MarigoldRTX.cpp:137`). See F1. |
| 5 | PlayDynamicForceFeedback fix in the player pawn | **PASS** | `MarigoldPlayerPawn.cpp:1188-1189`: `PC->PlayDynamicForceFeedback(FMath::Clamp(Intensity,0,1), Duration, true, true, true, true);`. This calls the **public native overload** `FDynamicForceFeedbackHandle PlayDynamicForceFeedback(float, float, bool, bool, bool, bool, EDynamicForceFeedbackAction::Type Action = Start, FDynamicForceFeedbackHandle ActionHandle = 0)`, so Action and Handle take their defaults. **Correction to the brief:** the `(…, TEnumAsByte<…> Action, FLatentActionInfo LatentInfo)` signature is the Blueprint latent overload, which has been **private** since UE 4.20 ("made private and only usable from blueprints"). C++ cannot call it. The pawn's call is the right one. Epic docs list the native overload and the `FDynamicForceFeedbackHandle` type through 5.5/5.7 (https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/GameFramework/APlayerController/PlayDynamicForceFeedback/1?application_version=5.1). The build is green, so no change is proposed. The comment at `:1181-1187` records that it was re-applied at the v0.8.0 merge. |
| 6 | Candle melt (MarigoldFX) present and wired | **PASS** | `UMarigoldCandleMeltSubsystem : UWorldSubsystem` (`MarigoldCandleMelt.h:343`) spawns `AMarigoldCandleMeltManager` in game worlds only (`MarigoldCandleMelt.cpp:1214-1230`, `IsGameWorld()` guard). The manager ticks (`:49-52`, `:119`). Flame hooks: `MarigoldCandleFlames.cpp:113,132` → `NotifyFlameChanged` (`:1232-1246`). CVar `marigold.wax.speed` and command `marigold.wax.reset` (`:28-43`). |
| 7 | 55 UE5 voice lines | **PASS** (55 unique stems) | `MarigoldChapterDialogue.cpp`: Welcome 12 (`:11`), Offering 16 (`:42`), FinaleAdditions 11 (`:81`), Relive 4 (`:110`) = 43. `MarigoldDialogueManager.cpp`: BuildLines 7 (`:238`), FinaleLines 5 (`:249`) = 12. **Total 55**, no duplicate stems. WAVs resolve at `/Game/Marigold/Audio/Voice/<stem>` (`MarigoldDialogueManager.cpp:159`). Note: `GetReliveLines()` is never called anywhere, so 4 of the 55 never play (F6). |
| 8a | `.ps1` = UTF-8 **with BOM** | **FAIL** | BOM: `MarigoldUpdater.ps1` ✅, `UpdateMarigold.ps1` ✅. **No BOM:** `CrashWatchdog.ps1` (em-dash inside strings at `:175,184,187`), `AnalyzeRenderLog.ps1` (em-dash inside a string at `:74`), `SendBuildLog.ps1` (em-dash in a comment only, `:71`). See F2. |
| 8b | `.bat` = CRLF | **PASS** | All 5 .bat files are CRLF with 0 LF-only lines and no BOM. `BuildDemo.bat`, `RunPreFlightCI.bat` and `LaunchEditorVulkan.bat` have UTF-8 em-dashes in `echo` lines (`BuildDemo.bat:48,91`, `RunPreFlightCI.bat:43,48`). That only garbles console text under cp437. It is not a parse problem. |
| 8c | Zip entries have real timestamps | **PASS** | 605 entries, all dated 2026-10-23 06:26:46–06:34:58. Zero 1980 or zeroed entries. |
| 9 | Editor-open crash risks | **PASS** (static), 3 WARN | Details below. |
| 10 | NEXUS ARCADE cross-links / "Built by Muse" outside the launcher header | **PASS** | Zero `NEXUS ARCADE` / `built by Muse` hits in source, config or scripts. The only "nexus" string is the relay hostname. `MarigoldBuilder.uplugin` has `"CreatedBy": "Muse"`. That is plugin metadata, not the "Built by Muse" product line, but flag it to Brio if the rule is meant strictly. |

### Check 9 detail: editor-open crash sweep

- **World subsystems (13):** Cinema, Ciudad, Costume, Life, Look, Music, Panteon, Physics, Rain and Ritual are all limited to Game/PIE via `DoesSupportWorldType` and/or `ShouldCreateSubsystem`. Examples: `Cinema/MarigoldCinemaSubsystem.cpp:163-166`, `Costume/MarigoldCostumeSubsystem.cpp:113-121`, `Life/MarigoldLifeSubsystem.cpp:310-318`, `Look/MarigoldLookSubsystem.cpp:218-226`, `Rain/MarigoldRainSubsystem.cpp:95-98`, `Physics/MarigoldPhysicsSubsystem.cpp:164-167`, `Panteon/MarigoldPanteonSubsystem.cpp:78-81`.
  - `UMarigoldWeather` has the round-8 guard: Initialize returns early when `!World->IsGameWorld()` (`MarigoldWeather.cpp:183-190`).
  - `UMarigoldCandleMeltSubsystem` has no world-type filter, so it is created in editor worlds. It does nothing there: the spawn happens only in `OnWorldBeginPlay` behind `IsGameWorld()` (`MarigoldCandleMelt.cpp:1218`), and `NotifyFlameChanged` is guarded too (`:1234`). Benign.
  - `UMarigoldSpectacleSubsystem` is a GameInstanceSubsystem. The editor world has no GameInstance outside PIE.
- **No ticking in the editor:** zero `bTickInEditor`, `ShouldTickIfViewportsOnly`, `IsTickableInEditor` or `FTickableEditorObject` hits. Tickable world subsystems are limited to Game/PIE.
- **CDO constructors:** I extracted the body of every `A*/U*` constructor. None calls `GetWorld`, `SpawnActor`, `TActorIterator`, `GEngine`, `GConfig` or `check()`. There are **no** `OnConstruction`, `OnRegister`, `PostLoad`, `PostInitProperties` or `PostInitializeComponents` overrides.
- **ConstructorHelpers:** all target `/Engine/BasicShapes/*` (always present), except `MarigoldBootMenuWidget.cpp:53-55`, which looks up `/Game/Marigold/Audio/sfx_ui_{hover,select,back}`. If those aren't imported yet, CDO construction logs "Failed to find" errors at editor open. That is not a crash (WARN W2).
- **`check()` / `verify()`:** none anywhere in plugin or game code.
- **Static init:** only TAutoConsoleVariable/FAutoConsoleCommand globals, which is standard. The one CVar defined in a header (`MarigoldW3.h:19`) is a function-local static inside an inline function, so it registers once, lazily.
- **Console name collisions:** 118 CVars/commands, all prefixed `marigold.*`/`mg*`, **no duplicates**.
- **Duplicate reflected type names:** 129 UCLASS/USTRUCT/UENUM types across modules, **no duplicates**.
- **UHT nested types:** none found. One parser hit in `MarigoldHLSLValidator.h:77` was checked by hand and is global scope. The green build corroborates this.
- **Module startup:** QualityTiers and RTX return early in the editor. PreFlight and Builder only register menus. Telemetry wraps its startup in `try/catch`, but with UE's default `bEnableExceptions=false` and no `/EHa`, that catches nothing real (hygiene only). See W1 for Builder under commandlets and F4 for the Telemetry crash handler.

---

## Findings (ranked)

### F1: Crash (game sessions on Wade's 5070 Ti): RT auto-enabled to FULL at first boot. Rule conflict.
- **Where:** `Plugins/MarigoldRTX/Source/MarigoldRTX/Private/MarigoldRTXSettings.cpp:211-229`, from the boot hook `MarigoldRTX.cpp:149-152`, which writes `r.RayTracing.Enable/Shadows/Reflections`, `r.Lumen.HardwareRayTracing` and `r.Lumen.Reflections.HardwareRayTracing` = 1 at `MarigoldRTX.cpp:208-215`. This needs `Config/DefaultEngine.ini:22` `r.RayTracing=True`.
- **Why:** with no saved `RequestedTier`, a flat-PC D3D12 game session on an "RTX 40/50" adapter picks Tier 2 with nobody choosing it. That turns on hardware-RT Lumen, the config DefaultEngine.ini itself says caused `DXGI_ERROR_DRIVER_INTERNAL_ERROR (887A002B)` on the 5070 Ti (`DefaultEngine.ini:14,106-109`). The crash guard only reverts it *after* an unclean exit. This breaks "RT tiers are explicit-only" (AI_COORDINATION) and "MarigoldRTX must NOT force-enable r.RayTracing on D3D12" (MERGE_PROTOCOL).
  - The editor is not affected (GIsEditor early-out).
  - It only fires if `[/Script/MarigoldRTX.MarigoldRTXSettings] RequestedTier` is absent from Wade's saved GameUserSettings/Game ini. If an earlier run saved 0, it won't fire. **Needs PC confirm:** check `Saved/Config/Windows/Game.ini`.
- **Proposed minimal fix (in `fixes.patch`):** first boot stays Tier 0 and logs a hint. The user opts in through Settings or `marigold.rtx 1|2`. Crash guard, VR logic and capability checks are untouched.
- **Owner decision:** the code cites a 2026-10-20 directive ("max it") for this default. If Wade still wants it, the written rules need updating instead. Either way, both shouldn't stand.
- **Optional second step (`fixes_optional_rt_ini.patch`, NOT in the main patch):** `r.RayTracing=False` in DefaultEngine.ini matches the brief's literal reading. Opting in already handles a restart: `MarigoldRTXSettings.cpp:157-164` writes `r.RayTracing=True` to Saved Engine.ini. **Side effect:** the Graphics page hides the RT options while `r.RayTracing=0` (`Look/MarigoldGraphicsSettings.cpp:136`, `Look/Core/MglGfxCore.h:93-96`), so opt-in becomes console-only. Recommend F1's code fix alone unless Wade wants RT support off at boot entirely.

### F2: Behavior: three `.ps1` files without a BOM. CrashWatchdog almost certainly fails to parse on PowerShell 5.1.
- **Where:** `Build/CrashWatchdog.ps1:175,184,187` and `Build/AnalyzeRenderLog.ps1:74` (em-dash U+2014 inside double-quoted strings), `Build/SendBuildLog.ps1:71` (comment only).
- **Why:** without a BOM, PS 5.1 reads the file as cp1252. The em-dash bytes `E2 80 94` decode as `â€”`, and `0x94` is U+201D, which PowerShell treats as a closing double quote. The string ends early and the whole script fails to parse.
  - `MarigoldUpdater.ps1:236-241` calls the watchdog inside `try/catch` and prints "Watchdog skipped". The hard-crash inference (stale `session.json` heartbeat) and the flush of pending `crash-*.json` never run, and nobody notices.
  - The watchdog header says UpdateMarigold.ps1 also calls it, but no call exists there (grep). On the v3.8 `UpdateMarigold` path it simply doesn't run.
  - `AnalyzeRenderLog.ps1` has no caller in the tree, so it is a latent break. `SendBuildLog.ps1` is OK today, but one future em-dash in a string would break build-log reporting.
- **Fix (in patch):** prepend the UTF-8 BOM `EF BB BF`. No content change. Copy the files from `fixes/MarigoldDemo/Build/` directly rather than relying on a patch tool to keep the BOM. Then check with `file`: it should say "UTF-8 (with BOM)".

### F3: Hygiene/Build: MarigoldBuilder.uplugin doesn't declare the plugins its module depends on.
- **Where:** `Plugins/MarigoldBuilder/MarigoldBuilder.uplugin` ("Plugins" lists only ProceduralMeshComponent) vs `MarigoldBuilder.Build.cs:22` (MarigoldFX) and `:49` (MarigoldPreFlight).
- **Why:** UBT warns "Plugin 'MarigoldBuilder' does not list plugin 'MarigoldFX' as a dependency…". It works today only because the .uproject enables everything.
- **Fix (in patch):** add `{"Enabled":true,"Name":"MarigoldFX"}` and `{"Enabled":true,"Name":"MarigoldPreFlight"}`. The JSON was validated.

### F4: Behavior (needs PC confirm): Telemetry replaces the engine's Windows crash handler.
- **Where:** `MarigoldTelemetry/Private/MarigoldCrashReporter.cpp:692` `FPlatformMisc::SetCrashHandler(&MarigoldTelemetryCrashHandler)`. It is installed at PreDefault in the editor too, and the handler (`:588-600`, `:729-760`) only POSTs JSON or writes to disk.
- **Why (inferred from engine behavior, not verified on 5.7):** on Windows a custom crash handler is called *instead of* the default path (minidump plus CrashReportClient). Editor crashes may then leave no `Saved/Crashes/*/UEMinidump.dmp` or CrashContext. That is the very evidence needed to debug the editor-open crash. The handler also makes a WinHTTP call of up to ~5 s on the crashing thread.
- **Check on PC:** after any crash, does `Saved/Crashes/<id>/` contain a `.dmp`? If not, consider hooking `FCoreDelegates::OnHandleSystemError` (which runs alongside the default handler) instead of `SetCrashHandler`.
- No patch: outside a minimal fix, and the 5.7 behavior is unconfirmed.

### F5: Hygiene: inconsistent PlayDynamicForceFeedback call style (no action).
- **Where:** `Costume/MarigoldCostumeStall.cpp:648,655,666` pass 8 args, with `EDynamicForceFeedbackAction::Start, static_cast<uint64>(0)`.
- **Why:** this is the form the pawn comment (`MarigoldPlayerPawn.cpp:1182-1187`) warns about. It resolves to the public native overload: the enum is an exact match, and the latent overload is private. The build is green, so it compiles. Noted only so a future "harmonize" drop doesn't touch the pawn's protected call. **Do not change.**

### F6: Behavior (low): 4 Relive voice lines are authored but never played.
- **Where:** `MarigoldChapterDialogue.cpp:110` `GetReliveLines()` has no caller. `MarigoldDialogueManager.cpp:234-270` only pulls in Welcome, Offering and FinaleAdditions.
- **Why:** the 55-line count is intact, but the "Relive the Night" button (`MarigoldBootMenuWidget.cpp:166-169`) never uses the alternate lines.
- No patch: this is gameplay wiring, the open "UE5 gameplay systems" lane.

### Warnings (no patch)
- **W1: MarigoldBuilder under commandlets.** `MarigoldBuilderModule.cpp:28-33,81` calls `LoadModuleChecked("LevelEditor")`, `UToolMenus::Get()` and a Slate notification in StartupModule, including in `-run=MarigoldPreFlightCI` (Editor modules load in commandlets). This is usually harmless (`AddNotification` returns null without Slate). If `RunPreFlightCI.bat` ever crashes or hangs at startup, add `if (IsRunningCommandlet()) return;` at the top of StartupModule.
- **W2: Missing UI sfx before the content build.** `MarigoldBootMenuWidget.cpp:53-55` uses ConstructorHelpers on `/Game/Marigold/Audio/sfx_ui_*`. If they aren't imported yet, editor open logs CDO "Failed to find" errors. That is noise, not a crash, but it will show up in the relayed editor log.
- **W3: Comment is wrong but harmless.** `MarigoldRTXSettings.cpp:101-102` says "the editor runs DX11 by default". UE5 on Windows with SM6 defaults to D3D12. It has no effect because MarigoldRTX returns early in the editor.

---

## Files produced
- `audit_round8/AUDIT_ROUND8.md`: this report.
- `audit_round8/fixes.patch`: unified diff with F1 (RTX first boot Off), F2 (BOM on 3 .ps1 files) and F3 (Builder .uplugin deps). `git apply --check` passes against the round-8 tree.
- `audit_round8/fixes_optional_rt_ini.patch`: optional `r.RayTracing=False` in DefaultEngine.ini (owner decision, see F1 side effect).
- `audit_round8/fixes/MarigoldDemo/...`: full patched copies, mirroring paths:
  - `Plugins/MarigoldRTX/Source/MarigoldRTX/Private/MarigoldRTXSettings.cpp`
  - `Build/CrashWatchdog.ps1`, `Build/AnalyzeRenderLog.ps1`, `Build/SendBuildLog.ps1`
  - `Plugins/MarigoldBuilder/MarigoldBuilder.uplugin`
  - `Config/DefaultEngine.ini` (optional fix only)
- `audit_round8/src/` (unzipped source) and `audit_round8/src.zip` (download), plus the fetched `MERGE_PROTOCOL.md` and `AI_COORDINATION.md`.

**Honesty note:** none of the proposed fixes has been compiled. They are small and local: the C++ change only removes a branch's body and keeps the `IsStrongRTXAdapter` use, so there is no unused-function warning. They still need Brio's merge audit and Wade's PC compile per MERGE_PROTOCOL. Nothing was posted to AI_COORDINATION.md, since this pass was read-only. Claiming the "Code audit passes" lane and posting results is Wade's or Brio's call.
