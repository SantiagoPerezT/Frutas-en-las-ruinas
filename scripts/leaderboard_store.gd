extends RefCounted

## The records are stored in Godot's per-user data folder, outside the project.
const DATA_PATH := "user://leaderboard.cfg"
const MAX_RECORDS := 10
const ANY_PERCENT := "any_percent"
const ALL_FRUITS := "all_fruits"

static func _storage_key(level_index: int, category: String) -> String:
	if level_index < 0 or category not in [ANY_PERCENT, ALL_FRUITS]:
		return ""
	return "level_%02d_%s" % [level_index + 1, category]

static func get_records(level_index: int, category: String) -> Array[Dictionary]:
	var key := _storage_key(level_index, category)
	if key.is_empty():
		var empty_records: Array[Dictionary] = []
		return empty_records
	var config := ConfigFile.new()
	var error := config.load(DATA_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("No se pudo leer la tabla de tiempos: %s" % error_string(error))
	var saved: Array = config.get_value("leaderboards", key, [])
	var records: Array[Dictionary] = []
	for record in saved:
		if record is Dictionary and record.has("seconds"):
			records.append({"name": str(record.get("name", "Jugador")), "seconds": float(record["seconds"])})
	return records

static func record_run(level_index: int, category: String, player_name: String, seconds: float) -> bool:
	var key := _storage_key(level_index, category)
	if key.is_empty():
		push_error("No se pudo guardar el tiempo: nivel o categoría inválidos.")
		return false
	var records := get_records(level_index, category)
	var clean_name := player_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Jugador"
	clean_name = clean_name.left(20)
	records.append({"name": clean_name, "seconds": snappedf(seconds, 0.001)})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["seconds"]) < float(b["seconds"]))
	if records.size() > MAX_RECORDS:
		records.resize(MAX_RECORDS)
	var config := ConfigFile.new()
	var error := config.load(DATA_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_error("No se pudo abrir la tabla de tiempos: %s" % error_string(error))
		return false
	config.set_value("leaderboards", key, records)
	error = config.save(DATA_PATH)
	if error != OK:
		push_error("No se pudo guardar la tabla de tiempos: %s" % error_string(error))
		return false
	return true

## Call from editor code or a maintenance script, never from a gameplay button.
static func reset_data() -> Error:
	var config := ConfigFile.new()
	return config.save(DATA_PATH)
