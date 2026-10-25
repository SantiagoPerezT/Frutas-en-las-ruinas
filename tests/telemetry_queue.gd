extends SceneTree

# Exercise the real payload builder without HTTP requests or SQL writes.
class MemoryApi:
	extends "res://scripts/game_api.gd"
	func _enqueue(item: Dictionary) -> void:
		pending.append(item)

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var api := MemoryApi.new()
	api.start_session("Ada")
	api.start_attempt(2, "story")
	api.record_event(2, "position_snapshot", 1.25, 1, 2, {"x": 384.0, "y": 420.0})
	api.record_run(2, 8.5, 1, 5, 2)
	_check(api.pending.size() == 4, "Expected ordered session, attempt, event and run")
	_check(api.pending[0]["kind"] == "session" and api.pending[1]["kind"] == "attempt" and api.pending[2]["kind"] == "event" and api.pending[3]["kind"] == "run", "Queue order must preserve dependencies")
	var first_id: String = api.pending[1]["payload"]["client_attempt_id"]
	_check(first_id.length() == 36 and api.pending[2]["payload"]["attempt_id"] == first_id and api.pending[3]["payload"]["attempt_id"] == first_id, "Official route and leaderboard must share the attempt ID")
	_check(api.pending[1]["payload"]["level_id"] == 3 and api.pending[1]["payload"]["mode"] == "story", "Story attempt must identify the level")
	var data := {"width": 960, "spawn": {"x": 60, "y": 445}, "fruits": [{"x": 180, "y": 420}]}
	api.start_attempt(-1, "map_test", -1, "Mapa sin guardar", data)
	data["fruits"][0]["x"] = 999
	api.record_event(-1, "map_test_completed", 2.0, 0, 0)
	var custom_id: String = api.pending[4]["payload"]["client_attempt_id"]
	_check(custom_id != first_id and api.pending[4]["payload"]["level_id"] == null and api.pending[4]["payload"]["map_id"] == null, "Map test needs its own attempt without official level")
	_check(api.pending[4]["payload"]["map_data"]["fruits"][0]["x"] == 180, "Map snapshot must not change after editing")
	_check(api.pending[5]["payload"]["attempt_id"] == custom_id and api.pending[5]["payload"]["level_id"] == null, "Custom map events must belong to custom attempt")
	api.free()
	print("Telemetry queue failures: ", failures)
	quit(1 if failures else 0)
