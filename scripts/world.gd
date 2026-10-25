extends Node2D

const FruitHero = preload("res://scripts/player.gd")
const Levels = preload("res://scripts/levels.gd")
const LeaderboardStore = preload("res://scripts/leaderboard_store.gd")
const Story = preload("res://scripts/story.gd")
const CustomLevelScene = preload("res://scenes/custom_level.tscn")

var player: FruitHero
# Only living, uncollected fruit belongs in this list.
var fruits: Array[Dictionary] = []
var coins: Array[Node2D] = []
var saws: Array[Dictionary] = []
var trampolines: Array[Rect2] = []
var collected := 0
var collected_coins := 0
var total_fruits := 0
var total_coins := 0
var elapsed := 0.0
var snapshot_elapsed := 0.0
var level_complete := false
var current_level := 0
var level_data: Dictionary
var level_root: Node2D
var goal_area: Rect2
var title: Label
var status: Label
var feedback: Label
var feedback_time := 0.0
var completion_panel: Panel
var completion_title: Label
var completion_score: Label
var next_button: Button
var level_buttons: Array[Button] = []
var menu_overlay: Control
var main_menu: Panel
var leaderboard_panel: Panel
var player_name_input: LineEdit
var category_description: Label
var records_list: Label
var any_percent_button: Button
var all_fruits_button: Button
var screen_mode := "menu"
var run_name := "Jugador"
var active_record_category := LeaderboardStore.ANY_PERCENT
var active_record_level := 0
var record_level_buttons: Array[Button] = []
var api: Node
var story_panel: CanvasLayer
var map_maker: Control
var story_mode := false
var story_phase := ""
var custom_mode := false
var custom_level: Node2D
var custom_level_data: Dictionary = {}
var last_official_level := 0

func _ready() -> void:
	api = get_node("GameApi")
	api.leaderboard_loaded.connect(_on_leaderboard_loaded)
	api.run_synced.connect(_on_run_synced)
	api.run_rejected.connect(_on_run_rejected)
	story_panel = get_node("StoryPanel") as CanvasLayer
	story_panel.continued.connect(_on_story_continued)
	map_maker = get_node("MapMaker") as Control
	map_maker.return_requested.connect(_show_main_menu)
	map_maker.test_requested.connect(_play_custom_map)
	_make_hud()
	_make_menu()
	_load_level(0)
	_show_main_menu()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if screen_mode == "menu":
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_start_game()
		return
	if screen_mode == "leaderboard":
		if event.keycode == KEY_ESCAPE:
			_show_main_menu()
		return
	if screen_mode == "story" or screen_mode == "map_maker":
		return
	if screen_mode != "game":
		return
	if not story_mode and not custom_mode and event.keycode >= KEY_1 and event.keycode <= KEY_4:
		_change_level_from_hud(event.keycode - KEY_1)
	elif event.is_action_pressed("restart"):
		_restart_level()
	elif event.keycode == KEY_ENTER and level_complete:
		_advance_level()

func _load_level(index: int) -> void:
	if index < 0 or index >= Levels.DATA.size():
		return
	if is_instance_valid(custom_level):
		custom_level.queue_free()
		custom_level = null
	# Remove old physics bodies immediately; free their nodes at frame end.
	fruits.clear()
	coins.clear()
	saws.clear()
	trampolines.clear()
	custom_mode = false
	current_level = index
	last_official_level = index
	level_data = Levels.DATA[index]
	collected = 0
	collected_coins = 0
	total_fruits = 0
	total_coins = 0
	elapsed = 0.0
	snapshot_elapsed = 0.0
	level_complete = false
	feedback_time = 0.0
	feedback.text = ""
	completion_panel.hide()
	var collection := get_node("LevelCollection")
	for i in Levels.DATA.size():
		var candidate := collection.get_child(i) as Node2D
		var is_active := i == index
		candidate.visible = is_active
		for shape in candidate.find_children("*", "CollisionShape2D", true, false):
			shape.set_deferred("disabled", not is_active)
		var candidate_player := candidate.get_node("Player") as FruitHero
		candidate_player.set_physics_process(is_active)
		var camera := candidate_player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			camera.enabled = is_active
			if is_active:
				camera.make_current()
	level_root = collection.get_child(index) as Node2D
	_make_level()
	player = level_root.get_node("Player") as FruitHero
	player.world_width = float(Levels.LEVEL_WIDTH)
	player.reset_to_spawn()
	if not player.has_meta("respawn_connected"):
		player.respawned.connect(_on_player_respawned.bind(player))
		player.set_meta("respawn_connected", true)
	if not player.has_meta("jump_connected"):
		player.jumped.connect(_on_player_jumped.bind(player))
		player.set_meta("jump_connected", true)
	if not player.has_meta("death_connected"):
		player.died.connect(_on_player_died.bind(player))
		player.set_meta("death_connected", true)
	title.text = "%d / %d   ·   %s" % [index + 1, Levels.DATA.size(), level_data.name.to_upper()]
	for i in level_buttons.size():
		level_buttons[i].disabled = story_mode or i == index
	_update_counter()
	queue_redraw()
	if screen_mode == "game" or screen_mode == "story":
		api.start_attempt(current_level, "story" if story_mode else "free")
		if screen_mode == "game":
			_log_event("level_started")

func _process(delta: float) -> void:
	if screen_mode != "game" or level_complete:
		return
	elapsed += delta
	snapshot_elapsed += delta
	if snapshot_elapsed >= 0.2:
		snapshot_elapsed = 0.0
		_log_event("position_snapshot", {"x": snappedf(player.global_position.x, 0.1), "y": snappedf(player.global_position.y, 0.1), "vx": snappedf(player.velocity.x, 0.1), "vy": snappedf(player.velocity.y, 0.1)})
	for saw in saws:
		var node: Sprite2D = saw.node
		node.rotation += delta * 5.2
	for fruit in fruits:
		var node: Node2D = fruit.node
		node.position.y = fruit.base_y + sin(elapsed * 3.5 + node.position.x * .02) * 3.0
	_check_interactions()
	_update_counter()
	feedback_time = maxf(0.0, feedback_time - delta)
	if feedback_time == 0.0:
		feedback.text = ""

func _draw() -> void:
	draw_rect(Rect2(12, 12, 936, 516), Color("28313d"), false, 5)
	draw_rect(Rect2(20, 20, 920, 500), level_data.palette[3], false, 2)

func _make_level() -> void:
	for fruit in level_root.get_node("Fruits").get_children():
		fruit.visible = true
		fruit.position.y = fruit.get_meta("base_y", fruit.position.y)
		fruit.set_meta("base_y", fruit.position.y)
		fruits.append({"node": fruit, "base_y": fruit.position.y})
		total_fruits += 1
	for coin in level_root.get_node("Coins").get_children():
		coin.visible = true
		coins.append(coin)
		total_coins += 1
	for saw in level_root.get_node("Saws").get_children():
		saws.append({"node": saw, "area": Rect2(saw.position - Vector2(14, 14), Vector2(28, 28))})
	for trampoline in level_root.get_node("Trampolines").get_children():
		trampolines.append(Rect2(trampoline.position - Vector2(18, 10), Vector2(36, 18)))
	var goal := level_root.get_node("Goal") as Sprite2D
	goal_area = Rect2(goal.position - Vector2(22, 28), Vector2(44, 56))

func _make_hud() -> void:
	var hud := get_node("HUD")
	title = hud.get_node("Title") as Label
	status = hud.get_node("Status") as Label
	feedback = hud.get_node("Feedback") as Label
	completion_panel = hud.get_node("CompletionPanel") as Panel
	completion_title = completion_panel.get_node("CompletionTitle") as Label
	completion_score = completion_panel.get_node("CompletionScore") as Label
	next_button = completion_panel.get_node("NextButton") as Button
	next_button.pressed.connect(_advance_level)
	completion_panel.get_node("RetryButton").pressed.connect(_restart_level)
	for i in Levels.DATA.size():
		var button := hud.get_node("Level%d" % (i + 1)) as Button
		button.tooltip_text = Levels.DATA[i].name
		button.pressed.connect(_change_level_from_hud.bind(i))
		level_buttons.append(button)
	completion_panel.get_node("MenuButton").pressed.connect(_show_main_menu)

func _make_menu() -> void:
	menu_overlay = get_node("Menu/Overlay") as Control
	main_menu = menu_overlay.get_node("MainPanel") as Panel
	leaderboard_panel = menu_overlay.get_node("LeaderboardPanel") as Panel
	player_name_input = main_menu.get_node("PlayerName") as LineEdit
	category_description = leaderboard_panel.get_node("CategoryDescription") as Label
	records_list = leaderboard_panel.get_node("RecordsList") as Label
	any_percent_button = leaderboard_panel.get_node("AnyPercentButton") as Button
	all_fruits_button = leaderboard_panel.get_node("AllFruitsButton") as Button
	main_menu.get_node("StartButton").pressed.connect(_start_game)
	main_menu.get_node("StoryButton").pressed.connect(_start_story)
	main_menu.get_node("MapMakerButton").pressed.connect(_show_map_maker)
	main_menu.get_node("LeaderboardButton").pressed.connect(_show_leaderboard)
	main_menu.get_node("QuitButton").pressed.connect(get_tree().quit)
	leaderboard_panel.get_node("BackButton").pressed.connect(_show_main_menu)
	any_percent_button.pressed.connect(_select_record_category.bind(LeaderboardStore.ANY_PERCENT))
	all_fruits_button.pressed.connect(_select_record_category.bind(LeaderboardStore.ALL_FRUITS))
	for i in Levels.DATA.size():
		var level_button := leaderboard_panel.get_node("RecordLevel%d" % (i + 1)) as Button
		level_button.text = "NIVEL %d" % (i + 1)
		level_button.tooltip_text = Levels.DATA[i].name
		level_button.pressed.connect(_select_record_level.bind(i))
		record_level_buttons.append(level_button)
	_select_record_level(0)
	_select_record_category(LeaderboardStore.ANY_PERCENT)

func _show_main_menu() -> void:
	if screen_mode == "game" and not level_complete:
		_log_event("level_abandoned")
	screen_mode = "menu"
	story_mode = false
	story_phase = ""
	story_panel.hide()
	map_maker.hide()
	if is_instance_valid(custom_level):
		custom_level.queue_free()
		custom_level = null
	custom_mode = false
	menu_overlay.show()
	main_menu.show()
	leaderboard_panel.hide()
	completion_panel.hide()
	get_node("HUD").hide()
	for i in Levels.DATA.size():
		var candidate := get_node("LevelCollection").get_child(i) as Node2D
		candidate.visible = false
		var hero := candidate.get_node("Player") as FruitHero
		hero.set_physics_process(false)
		for shape in candidate.find_children("*", "CollisionShape2D", true, false):
			shape.set_deferred("disabled", true)

func _show_leaderboard() -> void:
	screen_mode = "leaderboard"
	main_menu.hide()
	leaderboard_panel.show()
	_select_record_level(last_official_level)

func _select_record_level(index: int) -> void:
	if index < 0 or index >= Levels.DATA.size():
		return
	active_record_level = index
	for i in record_level_buttons.size():
		record_level_buttons[i].disabled = i == index
	_select_record_category(active_record_category)

func _select_record_category(category: String) -> void:
	active_record_category = category
	var any_percent := category == LeaderboardStore.ANY_PERCENT
	any_percent_button.disabled = any_percent
	all_fruits_button.disabled = not any_percent
	var level_name: String = Levels.DATA[active_record_level].name
	var fruit_total: int = Levels.DATA[active_record_level]["fruits"].size()
	category_description.text = "%s: completa este nivel con menos de %d frutas." % [level_name, fruit_total] if any_percent else "%s: recoge sus %d frutas." % [level_name, fruit_total]
	records_list.text = "Consultando SQL Server..."
	api.request_leaderboard(active_record_level, category)

func _on_leaderboard_loaded(level_index: int, category: String, records: Array, error_message: String) -> void:
	if level_index != active_record_level or category != active_record_category:
		return
	if not error_message.is_empty():
		records_list.text = error_message + "\nInicia el servidor local y vuelve a abrir esta tabla."
		return
	var lines := PackedStringArray()
	for i in LeaderboardStore.MAX_RECORDS:
		if i < records.size():
			var record: Dictionary = records[i]
			var display_name := str(record["name"]).left(20).rpad(22)
			lines.append("%02d    %s    %s" % [i + 1, display_name, _format_time(float(record["seconds"]))])
		else:
			lines.append("%02d    —                     —" % (i + 1))
	records_list.text = "\n".join(lines)

func _start_game() -> void:
	_begin_game(false)

func _start_story() -> void:
	_begin_game(true)
	story_phase = "prologue"
	story_panel.show_prologue()

func _begin_game(with_story: bool) -> void:
	run_name = player_name_input.text.strip_edges()
	if run_name.is_empty():
		run_name = "Jugador"
	story_mode = with_story
	story_panel.hide()
	map_maker.hide()
	completion_panel.hide()
	screen_mode = "story" if with_story else "game"
	menu_overlay.hide()
	get_node("HUD").show()
	api.start_session(run_name)
	_load_level(0)
	if with_story:
		player.set_physics_process(false)

func _on_story_continued() -> void:
	match story_phase:
		"prologue":
			story_phase = "intro"
			story_panel.show_chapter(current_level)
		"intro":
			story_phase = ""
			screen_mode = "game"
			player.set_physics_process(true)
			_log_event("level_started", {"story_mode": true, "chapter": current_level + 1})
		"outro":
			if current_level == Levels.DATA.size() - 1:
				story_phase = "epilogue"
				story_panel.show_epilogue()
			else:
				_load_level(current_level + 1)
				player.set_physics_process(false)
				story_phase = "intro"
				story_panel.show_chapter(current_level)
		"epilogue":
			_show_main_menu()

func _show_story_outro() -> void:
	completion_panel.hide()
	screen_mode = "story"
	story_phase = "outro"
	story_panel.show_chapter(current_level, true)

func _restart_level() -> void:
	if custom_mode:
		_reload_custom_map()
	else:
		api.record_event(current_level, "level_restarted", elapsed, collected, collected_coins)
		_load_level(current_level)

func _change_level_from_hud(index: int) -> void:
	if screen_mode != "game" or story_mode or custom_mode or index == current_level:
		return
	if not level_complete:
		_log_event("level_abandoned", {"next_level_id": index + 1})
	_load_level(index)

func _show_map_maker() -> void:
	screen_mode = "map_maker"
	story_mode = false
	story_panel.hide()
	menu_overlay.hide()
	get_node("HUD").hide()
	if is_instance_valid(custom_level):
		custom_level.hide()
		custom_level.get_node("Player").set_physics_process(false)
		custom_level.queue_free()
		custom_level = null
	custom_mode = false
	for i in Levels.DATA.size():
		var candidate := get_node("LevelCollection").get_child(i) as Node2D
		candidate.hide()
		candidate.get_node("Player").set_physics_process(false)
	map_maker.show()

func _play_custom_map(data: Dictionary) -> void:
	var first_test := screen_mode == "map_maker"
	if is_instance_valid(custom_level):
		custom_level.hide()
		custom_level.get_node("Player").set_physics_process(false)
		custom_level.queue_free()
		custom_level = null
	var new_level := CustomLevelScene.instantiate() as Node2D
	add_child(new_level)
	if not new_level.build_from_data(data):
		new_level.queue_free()
		return
	custom_level = new_level
	custom_level_data = data.duplicate(true)
	custom_mode = true
	story_mode = false
	current_level = -1
	level_root = custom_level
	level_data = Levels.DATA[0].duplicate()
	level_data["name"] = map_maker.map_name.text
	fruits.clear()
	coins.clear()
	saws.clear()
	trampolines.clear()
	collected = 0
	collected_coins = 0
	total_fruits = 0
	total_coins = 0
	elapsed = 0.0
	snapshot_elapsed = 0.0
	level_complete = false
	completion_panel.hide()
	_make_level()
	player = level_root.get_node("Player") as FruitHero
	player.world_width = float(data.get("width", 960))
	player.reset_to_spawn()
	if not player.has_meta("jump_connected"):
		player.jumped.connect(_on_player_jumped.bind(player))
		player.set_meta("jump_connected", true)
	if not player.has_meta("death_connected"):
		player.died.connect(_on_player_died.bind(player))
		player.set_meta("death_connected", true)
	if not player.has_meta("respawn_connected"):
		player.respawned.connect(_on_player_respawned.bind(player))
		player.set_meta("respawn_connected", true)
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = true
		camera.make_current()
	if first_test:
		run_name = player_name_input.text.strip_edges()
		if run_name.is_empty():
			run_name = "Jugador"
		api.start_session(run_name)
	api.start_attempt(-1, "map_test", map_maker.map_id, map_maker.map_name.text.strip_edges(), custom_level_data)
	map_maker.hide()
	menu_overlay.hide()
	get_node("HUD").show()
	screen_mode = "game"
	title.text = "PRUEBA · %s" % level_data["name"].to_upper()
	for button in level_buttons:
		button.disabled = true
	_update_counter()
	queue_redraw()
	_log_event("map_test_started")

func _reload_custom_map() -> void:
	_log_event("map_test_restarted")
	_play_custom_map(custom_level_data)

func _check_interactions() -> void:
	if not player.alive or level_complete:
		return
	var player_box := Rect2(player.global_position - Vector2(10, 14), Vector2(20, 28))
	# Reverse removal keeps freed fruit out of animation and handles simultaneous pickups.
	for i in range(fruits.size() - 1, -1, -1):
		var fruit: Node2D = fruits[i].node
		if player_box.grow(5).has_point(fruit.global_position):
			fruits.remove_at(i)
			fruit.visible = false
			collected += 1
			_log_event("fruit_collected", {"item": fruit.name, "x": fruit.global_position.x, "y": fruit.global_position.y})
			_set_status("¡Fruta recogida!")
	for i in range(coins.size() - 1, -1, -1):
		var coin: Node2D = coins[i]
		if player_box.grow(5).has_point(coin.global_position):
			coins.remove_at(i)
			coin.visible = false
			collected_coins += 1
			_log_event("coin_collected", {"item": coin.name, "x": coin.global_position.x, "y": coin.global_position.y})
			_set_status("¡Moneda recogida!")
	for saw in saws:
		if player_box.intersects(saw.area):
			player.respawn("saw")
			return
	for trampoline in trampolines:
		if player_box.intersects(trampoline) and player.velocity.y >= 0:
			player.bounce()
			var trampoline_center := trampoline.position + trampoline.size * 0.5
			_log_event("trampoline_bounce", {"x": player.global_position.x, "y": player.global_position.y,
				"trampoline_x": trampoline_center.x, "trampoline_y": trampoline_center.y})
			_set_status("¡Boing!")
	if player_box.intersects(goal_area):
		_finish_level()

func _set_status(message: String) -> void:
	feedback.text = message
	feedback_time = 1.8

func _on_player_jumped(jump_number: int, source: FruitHero) -> void:
	if screen_mode == "game" and source == player:
		_log_event("jump", {"jump_number": jump_number, "x": player.global_position.x, "y": player.global_position.y})

func _on_player_died(cause: String, source: FruitHero) -> void:
	if screen_mode == "game" and source == player:
		_log_event("death", {"cause": cause, "x": player.global_position.x, "y": player.global_position.y})

func _on_player_respawned(source: FruitHero) -> void:
	if source != player:
		return
	_set_status("¡Cuidado! Regresas al inicio.")
	if screen_mode == "game":
		_log_event("respawn")

func _log_event(event_type: String, details: Dictionary = {}) -> void:
	if screen_mode != "game":
		return
	details = details.duplicate()
	if is_instance_valid(player):
		if not details.has("x"):
			details["x"] = snappedf(player.global_position.x, 0.1)
		if not details.has("y"):
			details["y"] = snappedf(player.global_position.y, 0.1)
	if custom_mode:
		details["map_id"] = map_maker.map_id
		details["map_name"] = map_maker.map_name.text
	api.record_event(current_level, event_type, elapsed, collected, collected_coins, details)

func _update_counter() -> void:
	status.text = "Frutas %d/%d · Monedas %d/%d · %05.1fs" % [collected, total_fruits, collected_coins, total_coins, elapsed]

func _finish_level() -> void:
	if level_complete:
		return
	level_complete = true
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	player._set_animation(&"idle")
	var last := not custom_mode and current_level == Levels.DATA.size() - 1
	completion_title.text = "¡MAPA COMPLETADO!" if custom_mode else "¡ÚLTIMO NIVEL COMPLETADO!" if last else "¡NIVEL COMPLETADO!"
	_log_event("map_test_completed" if custom_mode else "level_completed", {"fruits_total": total_fruits, "coins_total": total_coins})
	var classification := _save_level_records()
	completion_score.text = "%s\nTiempo: %s · Frutas: %d/%d · Monedas: %d/%d\n%s" % [level_data.name, _format_time(elapsed), collected, total_fruits, collected_coins, total_coins, classification]
	next_button.text = "Volver al creador · ENTER" if custom_mode else "Volver al menú · ENTER" if last else "Siguiente nivel · ENTER"
	completion_panel.show()

func _advance_level() -> void:
	if level_complete:
		if custom_mode:
			_show_map_maker()
		elif story_mode:
			_show_story_outro()
		elif current_level == Levels.DATA.size() - 1:
			_show_main_menu()
		else:
			_load_level(current_level + 1)

func _save_level_records() -> String:
	if custom_mode:
		return "Prueba del mapa completada."
	api.record_run(current_level, elapsed, collected, total_fruits, collected_coins)
	if collected < total_fruits:
		return "Any%% · Nivel %d · %s · pendiente de SQL Server." % [current_level + 1, run_name]
	if collected == total_fruits:
		return "Todas las frutas · Nivel %d · %s · pendiente de SQL Server." % [current_level + 1, run_name]
	return "Tiempo pendiente de SQL Server."

func _on_run_synced(level_index: int, _category: String) -> void:
	if screen_mode == "game" and level_complete and current_level == level_index:
		completion_score.text = completion_score.text.replace("pendiente de SQL Server", "guardado en SQL Server")

func _on_run_rejected(level_index: int, response_code: int) -> void:
	if screen_mode == "game" and level_complete and current_level == level_index:
		completion_score.text = completion_score.text.replace("pendiente de SQL Server", "rechazado (HTTP %d)" % response_code)

func _format_time(seconds: float) -> String:
	var total_milliseconds := roundi(seconds * 1000.0)
	var minutes := floori(float(total_milliseconds) / 60000.0)
	var seconds_part := floori(float(total_milliseconds) / 1000.0) % 60
	var milliseconds := total_milliseconds % 1000
	return "%02d:%02d.%03d" % [minutes, seconds_part, milliseconds]
