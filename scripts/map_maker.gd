extends Control

signal return_requested
signal test_requested(data: Dictionary)

const PLATFORM_SCENE: PackedScene = preload("res://scenes/platform.tscn")
const COIN_SCENE: PackedScene = preload("res://scenes/coin.tscn")
const FRUIT_TEXTURE: Texture2D = preload("res://Assets/Items/Fruits/Apple.png")
const CHERRIES_TEXTURE: Texture2D = preload("res://Assets/Items/Fruits/Cherries.png")
const ORANGE_TEXTURE: Texture2D = preload("res://Assets/Items/Fruits/Orange.png")
const STRAWBERRY_TEXTURE: Texture2D = preload("res://Assets/Items/Fruits/Strawberry.png")
const SAW_TEXTURE: Texture2D = preload("res://Assets/Traps/Saw/On (38x38).png")
const TRAMPOLINE_TEXTURE: Texture2D = preload("res://Assets/Traps/Trampoline/Idle.png")
const START_TEXTURE: Texture2D = preload("res://Assets/Items/Checkpoints/Start/Start (Idle).png")
const GOAL_TEXTURE: Texture2D = preload("res://Assets/Items/Checkpoints/End/End (Idle).png")

const WORLD_SIZE := Vector2(960, 540)
const PREVIEW_SCALE := 2.0 / 3.0
const GRID := 24.0
const THEMES := ["ruins", "forest", "desert", "snow"]
const OBJECT_KEYS := ["platforms", "fruits", "coins", "saws", "trampolines"]

@export var api_base_url := "http://127.0.0.1:8000/api"

@onready var canvas_panel: Panel = $CanvasPanel
@onready var preview: Node2D = $CanvasPanel/WorldPreview
@onready var map_name: LineEdit = $EditorPanel/MapName
@onready var theme_option: OptionButton = $EditorPanel/ThemeOption
@onready var tool_option: OptionButton = $EditorPanel/ToolOption
@onready var platform_width: SpinBox = $EditorPanel/PlatformWidth
@onready var platform_height: SpinBox = $EditorPanel/PlatformHeight
@onready var saved_maps: ItemList = $EditorPanel/SavedMaps
@onready var status_label: Label = $Status
@onready var http: HTTPRequest = $HTTPRequest

var map_data: Dictionary = {}
var map_id := -1
var dragging_key := ""
var dragging_index := -1
var drag_offset := Vector2.ZERO
var request_purpose := ""
var request_in_flight := false
var saved_confirmation := ""

func _ready() -> void:
	theme_option.add_item("Ruinas")
	theme_option.add_item("Bosque")
	theme_option.add_item("Desierto")
	theme_option.add_item("Nieve")
	tool_option.add_item("Seleccionar / mover")
	tool_option.add_item("Plataforma")
	tool_option.add_item("Fruta")
	tool_option.add_item("Moneda")
	tool_option.add_item("Sierra")
	tool_option.add_item("Trampolín")
	tool_option.add_item("Inicio")
	tool_option.add_item("Meta")
	tool_option.add_item("Borrar")
	$BackButton.pressed.connect(func() -> void: return_requested.emit())
	$NewButton.pressed.connect(_new_map)
	$SaveButton.pressed.connect(_save_map)
	$TestButton.pressed.connect(_test_map)
	$EditorPanel/RefreshButton.pressed.connect(_refresh_maps)
	$EditorPanel/LoadButton.pressed.connect(_load_selected_map)
	theme_option.item_selected.connect(_on_theme_selected)
	canvas_panel.gui_input.connect(_on_canvas_input)
	http.request_completed.connect(_on_request_completed)
	_new_map()
	_refresh_maps()

func _blank_map() -> Dictionary:
	return {
		"version": 1,
		"width": 960,
		"height": 540,
		"theme": "ruins",
		"spawn": {"x": 60, "y": 445},
		"goal": {"x": 900, "y": 445},
		"platforms": [{"x": 0, "y": 486, "w": 960, "h": 54}],
		"fruits": [], "coins": [], "saws": [], "trampolines": []
	}

func _new_map() -> void:
	map_id = -1
	map_name.text = "Nuevo mapa"
	map_data = _blank_map()
	theme_option.select(0)
	tool_option.select(0)
	_refresh_preview()
	_set_status("Mapa nuevo. Elige una herramienta y haz clic en el lienzo.")

func _on_theme_selected(index: int) -> void:
	map_data["theme"] = THEMES[index]
	_refresh_preview()

func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		var world_pos := _canvas_to_world(click.position)
		if click.button_index == MOUSE_BUTTON_LEFT and not click.pressed:
			dragging_key = ""
			return
		if not click.pressed:
			return
		if click.button_index == MOUSE_BUTTON_RIGHT:
			_erase_at(world_pos)
			return
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		match tool_option.selected:
			0:
				_start_drag(world_pos)
			1, 2, 3, 4, 5, 6, 7:
				_place_object(world_pos)
			8:
				_erase_at(world_pos)
	elif event is InputEventMouseMotion and not dragging_key.is_empty():
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move_selected(_canvas_to_world(motion.position) - drag_offset)
		else:
			dragging_key = ""

func _canvas_to_world(canvas_position: Vector2) -> Vector2:
	return Vector2(clampf(canvas_position.x / PREVIEW_SCALE, 0, WORLD_SIZE.x), clampf(canvas_position.y / PREVIEW_SCALE, 0, WORLD_SIZE.y))

func _snapped_position(point: Vector2) -> Vector2:
	return Vector2(roundf(point.x / GRID) * GRID, roundf(point.y / GRID) * GRID)

func _place_object(point: Vector2) -> void:
	var position_in_world := _snapped_position(point)
	var key := ""
	match tool_option.selected:
		1: key = "platforms"
		2: key = "fruits"
		3: key = "coins"
		4: key = "saws"
		5: key = "trampolines"
		6: key = "spawn"
		7: key = "goal"
	if key.is_empty():
		return
	if key == "spawn" or key == "goal":
		map_data[key] = _point_dict(Vector2(clampf(position_in_world.x, 16, WORLD_SIZE.x - 16), clampf(position_in_world.y, 16, WORLD_SIZE.y - 16)))
	elif key == "platforms":
		var width := platform_width.value
		var height := platform_height.value
		var placed := Vector2(clampf(position_in_world.x, 0, WORLD_SIZE.x - width), clampf(position_in_world.y, 0, WORLD_SIZE.y - height))
		var platform := _point_dict(placed)
		platform["w"] = width
		platform["h"] = height
		(map_data[key] as Array).append(platform)
	else:
		var placed := Vector2(clampf(position_in_world.x, 16, WORLD_SIZE.x - 16), clampf(position_in_world.y, 16, WORLD_SIZE.y - 16))
		(map_data[key] as Array).append(_point_dict(placed))
	_refresh_preview()
	_set_status("%s colocado. Usa Seleccionar / mover para ajustar su posición." % tool_option.get_item_text(tool_option.selected))

func _start_drag(point: Vector2) -> void:
	var selection := _find_object_at(point)
	if selection.is_empty():
		return
	dragging_key = str(selection["key"])
	dragging_index = int(selection["index"])
	var origin := _position_of(dragging_key, dragging_index)
	drag_offset = point - origin

func _move_selected(point: Vector2) -> void:
	var snapped := _snapped_position(point)
	if dragging_key == "spawn" or dragging_key == "goal":
		map_data[dragging_key] = _point_dict(Vector2(clampf(snapped.x, 16, WORLD_SIZE.x - 16), clampf(snapped.y, 16, WORLD_SIZE.y - 16)))
	else:
		var entries: Array = map_data[dragging_key]
		if dragging_index < 0 or dragging_index >= entries.size():
			return
		var entry: Dictionary = entries[dragging_index]
		var maximum := WORLD_SIZE - Vector2(float(entry.get("w", 16)), float(entry.get("h", 16))) if dragging_key == "platforms" else WORLD_SIZE - Vector2(16, 16)
		entry["x"] = clampf(snapped.x, 0, maximum.x)
		entry["y"] = clampf(snapped.y, 0, maximum.y)
	_refresh_preview()

func _erase_at(point: Vector2) -> void:
	var selection := _find_object_at(point)
	if selection.is_empty():
		return
	var key := str(selection["key"])
	if key == "spawn" or key == "goal":
		_set_status("Inicio y meta son obligatorios; puedes moverlos con Seleccionar / mover.")
		return
	(map_data[key] as Array).remove_at(int(selection["index"]))
	_refresh_preview()
	_set_status("Objeto eliminado.")

func _find_object_at(point: Vector2) -> Dictionary:
	for key in ["spawn", "goal"]:
		if _position_of(key, -1).distance_to(point) <= 22.0:
			return {"key": key, "index": -1}
	for key in ["fruits", "coins", "saws", "trampolines", "platforms"]:
		var entries: Array = map_data[key]
		for i in range(entries.size() - 1, -1, -1):
			var entry: Dictionary = entries[i]
			var position_in_world := Vector2(float(entry["x"]), float(entry["y"]))
			if key == "platforms":
				if Rect2(position_in_world, Vector2(float(entry["w"]), float(entry["h"]))).grow(5).has_point(point):
					return {"key": key, "index": i}
			elif position_in_world.distance_to(point) <= 22.0:
				return {"key": key, "index": i}
	return {}

func _position_of(key: String, index: int) -> Vector2:
	var entry: Dictionary = map_data[key] if index < 0 else (map_data[key] as Array)[index]
	return Vector2(float(entry["x"]), float(entry["y"]))

func _point_dict(point: Vector2) -> Dictionary:
	return {"x": int(point.x), "y": int(point.y)}

func _refresh_preview() -> void:
	var theme: String = str(map_data.get("theme", "ruins"))
	var colors := {
		"ruins": Color("534041"), "forest": Color("234c40"),
		"desert": Color("845b39"), "snow": Color("426887")
	}
	canvas_panel.field_color = colors.get(theme, colors["ruins"])
	for bucket in preview.get_children():
		for old_node in bucket.get_children():
			bucket.remove_child(old_node)
			old_node.queue_free()
	var platform_bucket: Node2D = preview.get_node("Platforms")
	for entry in map_data["platforms"]:
		var platform: GrassPlatform = PLATFORM_SCENE.instantiate()
		platform.theme = theme
		# The editor preview shares the game tree, so its bodies must not affect play.
		platform.collision_layer = 0
		platform.collision_mask = 0
		platform.platform_size = Vector2(float(entry["w"]), float(entry["h"]))
		platform.position = Vector2(float(entry["x"]), float(entry["y"]))
		platform_bucket.add_child(platform)
	for entry in map_data["fruits"]:
		_add_atlas_sprite(preview.get_node("Fruits"), _fruit_for_theme(theme), entry, Vector2(32, 32))
	for entry in map_data["saws"]:
		_add_atlas_sprite(preview.get_node("Saws"), SAW_TEXTURE, entry, Vector2(38, 38))
	for entry in map_data["trampolines"]:
		_add_atlas_sprite(preview.get_node("Trampolines"), TRAMPOLINE_TEXTURE, entry, Vector2(28, 28))
	for entry in map_data["coins"]:
		_add_coin(preview.get_node("Coins"), entry)
	_add_atlas_sprite(preview.get_node("Markers"), START_TEXTURE, map_data["spawn"], Vector2(64, 64))
	_add_atlas_sprite(preview.get_node("Markers"), GOAL_TEXTURE, map_data["goal"], Vector2(64, 64))

func _add_atlas_sprite(bucket: Node2D, texture: Texture2D, entry: Dictionary, frame_size: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, frame_size)
	sprite.position = Vector2(float(entry["x"]), float(entry["y"]))
	bucket.add_child(sprite)

func _add_coin(bucket: Node2D, entry: Dictionary) -> void:
	var coin := COIN_SCENE.instantiate() as Area2D
	coin.collision_layer = 0
	coin.collision_mask = 0
	coin.position = Vector2(float(entry["x"]), float(entry["y"]))
	bucket.add_child(coin)

func _fruit_for_theme(theme: String) -> Texture2D:
	match theme:
		"forest": return CHERRIES_TEXTURE
		"desert": return ORANGE_TEXTURE
		"snow": return STRAWBERRY_TEXTURE
		_: return FRUIT_TEXTURE

func _save_map() -> void:
	var name := map_name.text.strip_edges()
	if name.is_empty():
		_set_status("Escribe un nombre antes de guardar el mapa.")
		map_name.grab_focus()
		return
	var payload := {"name": name, "data": map_data.duplicate(true)}
	if map_id < 0:
		_send_request("save", HTTPClient.METHOD_POST, "/maps", payload)
	else:
		_send_request("save", HTTPClient.METHOD_PUT, "/maps/%d" % map_id, payload)

func _test_map() -> void:
	_set_status("Abriendo el mapa de prueba.")
	test_requested.emit(map_data.duplicate(true))

func _refresh_maps() -> void:
	_send_request("list", HTTPClient.METHOD_GET, "/maps")

func _load_selected_map() -> void:
	var selected := saved_maps.get_selected_items()
	if selected.is_empty():
		_set_status("Selecciona un mapa de la lista y pulsa CARGAR.")
		return
	var selected_id := int(saved_maps.get_item_metadata(selected[0]))
	_send_request("load", HTTPClient.METHOD_GET, "/maps/%d" % selected_id)

func _send_request(purpose: String, method: int, path: String, payload: Dictionary = {}) -> void:
	if request_in_flight:
		_set_status("Espera a que termine la solicitud anterior.")
		return
	var headers := PackedStringArray(["Accept: application/json"])
	var body := ""
	if method != HTTPClient.METHOD_GET:
		headers.append("Content-Type: application/json")
		body = JSON.stringify(payload)
	var result := http.request(api_base_url.trim_suffix("/") + path, headers, method, body)
	if result != OK:
		_set_status("No se pudo iniciar la conexión con el servidor: %s." % error_string(result))
		return
	request_purpose = purpose
	request_in_flight = true
	_set_status("Consultando mapas en SQL Server…" if purpose == "list" or purpose == "load" else "Guardando mapa en SQL Server…")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	request_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("No se pudo conectar con la API local. Inicia el servidor y vuelve a intentarlo.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300:
		var detail := "HTTP %d" % response_code
		if parsed is Dictionary:
			detail = str(parsed.get("detail", parsed.get("error", detail)))
		_set_status("La base de datos rechazó la operación: %s." % detail)
		return
	match request_purpose:
		"list":
			_show_map_list(parsed)
		"load":
			if parsed is Dictionary:
				_apply_remote_map(parsed)
			else:
				_set_status("El servidor devolvió un mapa inválido.")
		"save":
			if parsed is Dictionary:
				map_id = int(parsed.get("id", map_id))
			saved_confirmation = "Mapa guardado en la base de datos: %s." % map_name.text.strip_edges()
			_refresh_maps()

func _show_map_list(response: Variant) -> void:
	var entries: Variant = response
	if response is Dictionary:
		entries = response.get("maps", [])
	if not entries is Array:
		_set_status("La lista de mapas recibida no tiene el formato esperado.")
		return
	saved_maps.clear()
	for entry in entries:
		if not entry is Dictionary:
			continue
		var id := int(entry.get("id", -1))
		if id < 0:
			continue
		var item := saved_maps.add_item(str(entry.get("name", "Mapa %d" % id)))
		saved_maps.set_item_metadata(item, id)
	if saved_confirmation.is_empty():
		_set_status("%d mapa(s) disponibles. Selecciona uno para cargarlo." % saved_maps.item_count)
	else:
		_set_status(saved_confirmation)
		saved_confirmation = ""

func _apply_remote_map(record: Dictionary) -> void:
	var incoming: Variant = record.get("data", {})
	if incoming is String:
		incoming = JSON.parse_string(incoming)
	if not incoming is Dictionary:
		_set_status("El mapa recibido no tiene datos válidos.")
		return
	map_data = _normalized_map(incoming)
	map_id = int(record.get("id", -1))
	map_name.text = str(record.get("name", "Mapa %d" % map_id))
	theme_option.select(maxi(0, THEMES.find(str(map_data["theme"]))))
	tool_option.select(0)
	_refresh_preview()
	_set_status("Mapa cargado: %s. Puedes editarlo y guardarlo otra vez." % map_name.text)

func _normalized_map(incoming: Dictionary) -> Dictionary:
	var normalized := _blank_map()
	var theme := str(incoming.get("theme", "ruins"))
	normalized["theme"] = theme if THEMES.has(theme) else "ruins"
	for marker in ["spawn", "goal"]:
		var value: Variant = incoming.get(marker, {})
		if value is Dictionary:
			normalized[marker] = _point_dict(Vector2(clampf(float(value.get("x", 0)), 16, WORLD_SIZE.x - 16), clampf(float(value.get("y", 0)), 16, WORLD_SIZE.y - 16)))
	for key in OBJECT_KEYS:
		var raw_entries: Variant = incoming.get(key, [])
		if not raw_entries is Array:
			continue
		normalized[key] = []
		for entry in raw_entries.slice(0, 300):
			if not entry is Dictionary:
				continue
			var safe := _point_dict(Vector2(clampf(float(entry.get("x", 0)), 0, WORLD_SIZE.x), clampf(float(entry.get("y", 0)), 0, WORLD_SIZE.y)))
			if key == "platforms":
				safe["w"] = clampi(int(entry.get("w", 24)), 24, 960)
				safe["h"] = clampi(int(entry.get("h", 24)), 24, 540)
				safe["x"] = mini(int(safe["x"]), 960 - int(safe["w"]))
				safe["y"] = mini(int(safe["y"]), 540 - int(safe["h"]))
			(normalized[key] as Array).append(safe)
	return normalized

func _set_status(message: String) -> void:
	status_label.text = message
