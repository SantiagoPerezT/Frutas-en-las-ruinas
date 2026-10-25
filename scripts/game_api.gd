extends Node

signal leaderboard_loaded(level_index: int, category: String, records: Array, error_message: String)
signal run_synced(level_index: int, category: String)
signal run_rejected(level_index: int, response_code: int)
signal connection_changed(available: bool)

@export var api_base_url := "http://127.0.0.1:8000/api"

const QUEUE_PATH := "user://sql_sync_queue.json"
const REJECTED_PATH := "user://sql_rejected_queue.json"

@onready var queue_request: HTTPRequest = $QueueRequest
@onready var leaderboard_request: HTTPRequest = $LeaderboardRequest
@onready var retry_timer: Timer = $RetryTimer

var pending: Array[Dictionary] = []
var session_ids: Dictionary = {}
var current_session_key := ""
var current_attempt_id := ""
var request_busy := false
var leaderboard_level := 0
var leaderboard_category := "any_percent"
var available := false

func _ready() -> void:
	queue_request.request_completed.connect(_on_queue_completed)
	leaderboard_request.request_completed.connect(_on_leaderboard_completed)
	retry_timer.timeout.connect(_drain_queue)
	_load_queue()
	_drain_queue()

func _exit_tree() -> void:
	_save_queue()

func start_session(player_name: String) -> void:
	current_session_key = _new_id()
	current_attempt_id = ""
	_enqueue({
		"kind": "session",
		"session_key": current_session_key,
		"payload": {"client_session_id": current_session_key, "player_name": player_name}
	})

func start_attempt(level_index: int, mode: String, map_id: int = -1, map_name: String = "", map_data: Dictionary = {}) -> void:
	if current_session_key.is_empty():
		return
	current_attempt_id = _new_id()
	var level_id: Variant = level_index + 1 if level_index >= 0 else null
	var saved_map_id: Variant = map_id if map_id > 0 else null
	var snapshot: Variant = map_data.duplicate(true) if level_index < 0 else null
	_enqueue({
		"kind": "attempt",
		"session_key": current_session_key,
		"payload": {
			"client_attempt_id": current_attempt_id,
			"level_id": level_id,
			"map_id": saved_map_id,
			"mode": mode,
			"map_name": map_name if level_index < 0 else null,
			"map_data": snapshot
		}
	})

func record_event(level_index: int, event_type: String, elapsed_seconds: float, fruits_collected: int, coins_collected: int, details: Dictionary = {}) -> void:
	if current_session_key.is_empty() or current_attempt_id.is_empty():
		return
	var level_id: Variant = level_index + 1 if level_index >= 0 else null
	_enqueue({
		"kind": "event",
		"session_key": current_session_key,
		"payload": {
			"client_event_id": _new_id(),
			"attempt_id": current_attempt_id,
			"level_id": level_id,
			"event_type": event_type,
			"elapsed_seconds": snappedf(elapsed_seconds, 0.001),
			"fruits_collected": fruits_collected,
			"coins_collected": coins_collected,
			"details": details
		}
	})

func record_run(level_index: int, elapsed_seconds: float, fruits_collected: int, fruits_total: int, coins_collected: int) -> void:
	if current_session_key.is_empty() or current_attempt_id.is_empty():
		return
	_enqueue({
		"kind": "run",
		"session_key": current_session_key,
		"payload": {
			"client_run_id": _new_id(),
			"attempt_id": current_attempt_id,
			"level_id": level_index + 1,
			"elapsed_seconds": snappedf(elapsed_seconds, 0.001),
			"fruits_collected": fruits_collected,
			"fruits_total": fruits_total,
			"coins_collected": coins_collected
		}
	})

func request_leaderboard(level_index: int, category: String) -> void:
	leaderboard_level = level_index
	leaderboard_category = category
	if leaderboard_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		leaderboard_request.cancel_request()
	var url := "%s/leaderboards?level_id=%d&category=%s" % [api_base_url, level_index + 1, category]
	var error := leaderboard_request.request(url)
	if error != OK:
		_set_available(false)
		leaderboard_loaded.emit(level_index, category, [], "No se pudo consultar SQL Server.")

func _new_id() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

func _enqueue(item: Dictionary) -> void:
	pending.append(item)
	_save_queue()
	_drain_queue()

func _drain_queue() -> void:
	if request_busy or pending.is_empty():
		return
	var item: Dictionary = pending[0]
	var kind: String = item.get("kind", "")
	var payload: Dictionary = item.get("payload", {}).duplicate(true)
	if kind != "session":
		var session_key: String = item.get("session_key", "")
		if not session_ids.has(session_key):
			# The corresponding session request must be delivered first.
			retry_timer.start()
			return
		payload["session_id"] = session_ids[session_key]
	var endpoint := ""
	match kind:
		"session": endpoint = "sessions"
		"attempt": endpoint = "attempts"
		"event": endpoint = "events"
		"run": endpoint = "runs"
		_:
			pending.remove_at(0)
			_save_queue()
			_drain_queue()
			return
	var error := queue_request.request("%s/%s" % [api_base_url, endpoint], ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_set_available(false)
		retry_timer.start()
		return
	request_busy = true

func _on_queue_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	request_busy = false
	if pending.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code == 408 or response_code == 429 or response_code >= 500 or response_code < 400 and response_code >= 300:
		_set_available(false)
		retry_timer.start()
		return
	if response_code >= 400 and response_code < 500:
		# A permanent validation error must not block every later run forever.
		# Keep the rejected payload on disk before removing it from the live queue.
		if not _archive_rejected(response_code, body.get_string_from_utf8()):
			_set_available(false)
			retry_timer.start()
			return
		_save_queue()
		_drain_queue()
		return
	if response_code < 200 or response_code >= 300:
		_set_available(false)
		retry_timer.start()
		return
	var item: Dictionary = pending[0]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if item.get("kind") == "session":
		if not parsed is Dictionary or not parsed.has("id"):
			_set_available(false)
			retry_timer.start()
			return
		session_ids[item["session_key"]] = str(parsed["id"])
	if item.get("kind") == "run" and parsed is Dictionary:
		var category: String = str(parsed.get("category", ""))
		run_synced.emit(int(item["payload"].get("level_id", 1)) - 1, category)
	pending.remove_at(0)
	_prune_session_ids()
	_save_queue()
	_set_available(true)
	_drain_queue()

func _archive_rejected(response_code: int, response_body: String) -> bool:
	var first: Dictionary = pending[0]
	var failed_items: Array[Dictionary] = [first]
	var failed_key: String = first.get("session_key", "")
	var failed_attempt: String = str(first.get("payload", {}).get("client_attempt_id", "")) if first.get("kind") == "attempt" else ""
	if first.get("kind") == "session":
		for i in range(1, pending.size()):
			if pending[i].get("session_key", "") == failed_key:
				failed_items.append(pending[i])
	elif not failed_attempt.is_empty():
		for i in range(1, pending.size()):
			if pending[i].get("payload", {}).get("attempt_id", "") == failed_attempt:
				failed_items.append(pending[i])
	var archived: Array = []
	if FileAccess.file_exists(REJECTED_PATH):
		var existing := FileAccess.open(REJECTED_PATH, FileAccess.READ)
		if existing == null:
			return false
		var loaded: Variant = JSON.parse_string(existing.get_as_text())
		if loaded is Array:
			archived = loaded
	for item in failed_items:
		archived.append({"item": item, "http_status": response_code, "response": response_body.left(1000), "rejected_at_unix": Time.get_unix_time_from_system()})
	var file := FileAccess.open(REJECTED_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(archived))
	file.flush()
	if file.get_error() != OK:
		return false
	for item in failed_items:
		if item.get("kind") == "run":
			run_rejected.emit(int(item["payload"].get("level_id", 1)) - 1, response_code)
	for i in range(pending.size() - 1, -1, -1):
		if i == 0 or (first.get("kind") == "session" and pending[i].get("session_key", "") == failed_key) or (not failed_attempt.is_empty() and pending[i].get("payload", {}).get("attempt_id", "") == failed_attempt):
			pending.remove_at(i)
	_prune_session_ids()
	return true

func _prune_session_ids() -> void:
	var needed := {current_session_key: true}
	for item in pending:
		needed[item.get("session_key", "")] = true
	for key in session_ids.keys():
		if not needed.has(key):
			session_ids.erase(key)

func _on_leaderboard_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_set_available(false)
		leaderboard_loaded.emit(leaderboard_level, leaderboard_category, [], "Servidor de tiempos no disponible.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Array:
		leaderboard_loaded.emit(leaderboard_level, leaderboard_category, [], "Respuesta inválida del servidor.")
		return
	_set_available(true)
	leaderboard_loaded.emit(leaderboard_level, leaderboard_category, parsed, "")

func _set_available(value: bool) -> void:
	if available == value:
		return
	available = value
	connection_changed.emit(value)

func _load_queue() -> void:
	if not FileAccess.file_exists(QUEUE_PATH):
		return
	var file := FileAccess.open(QUEUE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	for item in parsed.get("pending", []):
		if item is Dictionary:
			pending.append(item)
	if parsed.get("session_ids", {}) is Dictionary:
		session_ids = parsed["session_ids"]

func _save_queue() -> void:
	var file := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("No se pudo guardar la cola de sincronización: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({"pending": pending, "session_ids": session_ids}))
