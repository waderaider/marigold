## gameplay_telemetry.gd — gameplay-event telemetry autoload (autoload: GameplayTelemetry).
##
## Permanent system (2026-10-08): batched, low-overhead gameplay events POSTed
## to the SAME crash-log relay as the crash reporter (POST /report).
## Payloads are tiny; events batch in memory and flush every 60s + on chapter
## end + on app close. Network is fully async — gameplay NEVER blocks on
## telemetry.
##
## PRIVACY (permanent rule): gameplay events ONLY — chapter names, durations,
## counts, input methods, error context. NEVER logged: personal data,
## audio/video, room-scan data, or identifiers beyond device model + app
## version (already present in crash reports).
##
## Event names/fields are documented in TELEMETRY.md (project root) for the
## weekly analysis job. Naming is designed so a digest can answer:
##   - which chapters get quit in <30s
##   - which chapters get replayed (chapter_start with via="restart")
##   - where players pause/quit (pause_open counts, chapter_end.exit)
##   - hands vs controllers vs gaze usage (input_method)
##
## Usage (autoload name "GameplayTelemetry"):
##   GameplayTelemetry.chapter_start("The Ofrenda", "ch1", "menu")
##   GameplayTelemetry.chapter_end("quit_to_menu")
##   GameplayTelemetry.event("pause_open", {"chapter": "The Ofrenda"})
##   GameplayTelemetry.note_input_method("controllers")
##   GameplayTelemetry.error("The Ofrenda", "scene load failed", "res://...")
extends Node

const FLUSH_INTERVAL := 60.0
const MAX_EVENTS := 300
const MANIFEST_URL := "https://raw.githubusercontent.com/waderaider/marigold/main/version.json"
## No-secret fallback (2026-10-09): POST /report needs no key (the read key is
## server-side only). Compiled-in because the async version.json fetch is the
## prime suspect for zero telemetry ever arriving from the headset.
const RELAY_FALLBACK_URL := "https://nexus-log-relay.wade-relay.workers.dev/report"

var _events: Array[Dictionary] = []
var _session_id := ""
## Starts as the compiled-in fallback; the remote version.json may override.
var _report_url := RELAY_FALLBACK_URL
var _http: HTTPRequest = null
var _config_http: HTTPRequest = null
var _flush_timer := 0.0
var _flushing := false
var _ready_done := false
# v0.9.2 diagnostics: last flush outcome so the launcher panel can show
# relay health in plain words (wade reads it back when debugging).
var _last_flush_text := "no send yet"

# Current chapter-session state (owned here so ends are idempotent).
var _chapter := ""
var _chapter_key := ""
var _chapter_start_unix := 0.0
var _chapter_via := ""
var _input_method := ""


func _ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_id = _new_session_id()
	_http = HTTPRequest.new()
	_http.name = "GameplayTelemetryHTTP"
	add_child(_http)
	_http.request_completed.connect(_on_flush_completed)
	_config_http = HTTPRequest.new()
	_config_http.name = "GameplayTelemetryConfigHTTP"
	add_child(_config_http)
	_config_http.request_completed.connect(_on_config_completed)
	_fetch_remote_config()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		chapter_end("app_close")
		_flush_now()


func _process(delta: float) -> void:
	_flush_timer += delta
	if _flush_timer >= FLUSH_INTERVAL:
		_flush_timer = 0.0
		_flush_now()


func _new_session_id() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d%02d%02d%02d_%d" % [d["year"], d["month"], d["day"],
			d["hour"], d["minute"], d["second"], randi() % 100000]


# ------------------------------------------------------------------ API ---

## Start a chapter/experience session. If one is already open it is auto-ended
## first with exit=<via> (defensive: menu paths always end explicitly, but a
## missed end must never corrupt durations).
## via: "menu" | "restart" | "complete".
func chapter_start(chapter_name: String, key: String, via: String = "menu") -> void:
	if _chapter != "":
		chapter_end(via)
	_chapter = chapter_name
	_chapter_key = key
	_chapter_via = via
	_chapter_start_unix = Time.get_unix_time_from_system()
	_input_method = ""
	event("chapter_start", {"chapter": chapter_name, "key": key, "via": via})


## End the current chapter session. No-op when none is open (idempotent).
## exit: "quit_to_menu" | "restart" | "completed" | "app_close".
func chapter_end(exit: String) -> void:
	if _chapter == "":
		return
	var dur := Time.get_unix_time_from_system() - _chapter_start_unix
	event("chapter_end", {
		"chapter": _chapter,
		"key": _chapter_key,
		"duration_s": snappedf(dur, 0.1),
		"exit": exit,
		"input_method": _input_method,
	})
	_chapter = ""
	_chapter_key = ""
	_chapter_via = ""
	_input_method = ""
	_flush_now()


## Display name of the currently open chapter ("" when none). Used by the
## pause overlay to tag pause_open without duplicating session state.
func current_chapter() -> String:
	return _chapter


## Queue a generic gameplay event. Fields are merged with t (unix time).
func event(event_name: String, fields: Dictionary = {}) -> void:
	var e := {"t": Time.get_unix_time_from_system(), "name": event_name}
	for k in fields.keys():
		e[str(k)] = fields[k]
	_events.append(e)
	while _events.size() > MAX_EVENTS:
		_events.remove_at(0)


## Record the first input method used in the current chapter session.
## method: "controllers" | "hands" | "gaze" | "mouse". First wins per session.
func note_input_method(method: String) -> void:
	if _chapter == "" or _input_method != "":
		return
	_input_method = method
	event("input_method", {"chapter": _chapter, "method": method})


## v0.7.0: force an immediate POST of queued events (the menu_open boot
## event calls this so a menu-only session is visible in the relay at once).
func flush() -> void:
	_flush_now()


## Error breadcrumb with chapter context (mirrors crash-reporter usage).
func error(chapter_name: String, message: String, context: String = "") -> void:
	var fields := {"chapter": chapter_name, "message": message.left(160)}
	if context != "":
		fields["context"] = context.left(160)
	event("error", fields)


# ----------------------------------------------------------------- flush ---

## v0.9.3 (R1): the batch in flight, kept so a failed send can re-queue
## it instead of dropping a session silently (the old header comment
## claimed events "stay in memory when offline" - sent batches did not).
var _inflight: Array = []


func _requeue_inflight() -> void:
	if _inflight.is_empty():
		return
	_events = _inflight + _events
	_inflight = []
	while _events.size() > MAX_EVENTS:
		_events.remove_at(0)


## POST the current batch to the relay. Tiny payloads, async, never blocking.
## Events stay in memory when offline or URL-less (ring buffer, oldest dropped).
func _flush_now() -> void:
	if _flushing or _events.is_empty() or _report_url == "":
		return
	_flushing = true
	var payload := {
		"app": str(ProjectSettings.get_setting("application/config/name", "MARIGOLD")),
		"kind": "gameplay_telemetry",
		"version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"version_code": int(ProjectSettings.get_setting("application/config/version_code", 0)),
		"device": OS.get_model_name(),
		"platform": _platform_tag(),
		"headset": _detect_headset(),
		"session_id": _session_id,
		"timestamp": _iso_now(),
		"events": _events.duplicate(),
	}
	_inflight = _events.duplicate()
	_events.clear()
	var body := JSON.stringify(payload)
	var err := _http.request(_report_url,
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, body)
	if err != OK:
		# Request never started (no route/DNS): re-queue, unstick the
		# flush flag, and let the next timer retry.
		_requeue_inflight()
		_flushing = false
		_last_flush_text = "FAILED (request error %d)" % err


func _on_flush_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_flushing = false
	var d := Time.get_time_dict_from_system()
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		_inflight = []
		_last_flush_text = "OK %02d:%02d" % [int(d["hour"]), int(d["minute"])]
	else:
		# v0.9.3 (R1): offline/failed batches RE-QUEUE (front of the
		# queue, capped) instead of vanishing - an offline session is
		# exactly the session we most need to see. Bounded by MAX_EVENTS.
		_requeue_inflight()
		_last_flush_text = "QUEUED (%s) %02d:%02d" % [
				("code %d" % response_code) if response_code > 0 else "no connection",
				int(d["hour"]), int(d["minute"])]


## v0.9.2: one-line relay health for the launcher diagnostics panel —
## relay host + the most recent telemetry send outcome.
func relay_status_text() -> String:
	var host := _report_url.trim_prefix("https://").trim_prefix("http://")
	var slash := host.find("/")
	if slash > 0:
		host = host.substr(0, slash)
	return "Relay %s · last send %s" % [host, _last_flush_text]


func _fetch_remote_config() -> void:
	if _config_http == null:
		return
	if _config_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_config_http.request(MANIFEST_URL)


func _on_config_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary:
		var remote := str((data as Dictionary).get("report_url", "")).strip_edges()
		# Only the remote manifest may override the compiled-in fallback;
		# an empty field must never blank a working URL.
		# v0.9.3 (R2): ...and only toward OUR relay host - a poisoned or
		# mistyped manifest must not redirect telemetry to a third party.
		if remote != "" and _relay_host_ok(remote):
			_report_url = remote
		elif remote != "":
			push_warning("gameplay_telemetry: remote report_url host rejected: " + remote)


## v0.9.3 (R2): the only host remote config may point reports at.
const RELAY_HOST := "nexus-log-relay.wade-relay.workers.dev"


static func _relay_host_ok(url: String) -> bool:
	var h := url.trim_prefix("https://").trim_prefix("http://")
	var slash := h.find("/")
	if slash > 0:
		h = h.substr(0, slash)
	return h == RELAY_HOST


## v0.7.0 PC VR (QA §1.11): distinct platform tag so the digest can split
## Quest vs PC sessions. "PCVR-VirtualDesktop" on Windows, OS name otherwise.
func _platform_tag() -> String:
	if OS.has_feature("windows") and not OS.has_feature("android"):
		return "PCVR-VirtualDesktop"
	return OS.get_name()


## v0.7.0: headset model via the XR_META_headset_id extension
## (privacy-safe, zero cost). Falls back to the interface scan on desktop.
func _detect_headset() -> String:
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and (xr as XRInterface).is_initialized() \
			and Engine.has_singleton("OpenXRMetaHeadsetIDExtension"):
		var ext = Engine.get_singleton("OpenXRMetaHeadsetIDExtension")
		if ext != null and ext.has_method("get_headset_id"):
			var hid := str(ext.call("get_headset_id")).strip_edges()
			if hid != "":
				return hid
	for iface in XRServer.get_interfaces():
		var d: Dictionary = iface
		if str(d.get("name", "")).to_lower().find("openxr") >= 0:
			return "OpenXR"
	return "none"


func _iso_now() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [d["year"], d["month"], d["day"],
			d["hour"], d["minute"], d["second"]]
