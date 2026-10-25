extends SceneTree

# Gameplay regression without writing to the real SQL Server.
class FakeApi:
	extends Node
	signal leaderboard_loaded(level_index: int, category: String, records: Array, error_message: String)
	signal run_synced(level_index: int, category: String)
	signal run_rejected(level_index: int, response_code: int)
	var runs: Array[Dictionary] = []
	var attempts: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	var current_attempt := -1
	var session_names: Array[String] = []
	func start_session(player_name: String) -> void:
		session_names.append(player_name)
		current_attempt = -1
	func start_attempt(level_index: int, mode: String, map_id: int = -1, map_name: String = "", map_data: Dictionary = {}) -> void:
		current_attempt = attempts.size()
		attempts.append({"level": level_index, "mode": mode, "map_id": map_id, "map_name": map_name, "map_data": map_data.duplicate(true)})
	func record_event(level_index: int, event_type: String, elapsed_seconds: float, fruits_collected: int, coins_collected: int, details: Dictionary = {}) -> void:
		events.append({"attempt": current_attempt, "level": level_index, "type": event_type, "seconds": elapsed_seconds, "fruits": fruits_collected, "coins": coins_collected, "details": details.duplicate(true)})
	func record_run(level_index: int, elapsed_seconds: float, fruits_collected: int, fruits_total: int, coins_collected: int) -> void:
		runs.append({"attempt": current_attempt, "level": level_index, "seconds": elapsed_seconds, "fruits": fruits_collected, "total": fruits_total, "coins": coins_collected})
	func request_leaderboard(level_index: int, category: String) -> void:
		leaderboard_loaded.emit(level_index, category, [], "")

var failures := 0
var world: Node2D
var fake_api: FakeApi

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	world = load("res://main.tscn").instantiate()
	var real_api := world.get_node("GameApi")
	world.remove_child(real_api)
	real_api.free()
	fake_api = FakeApi.new()
	fake_api.name = "GameApi"
	world.add_child(fake_api)
	world.get_node("MapMaker").api_base_url = "http://127.0.0.1:1/api"
	root.add_child(world)
	world.set_process(false)
	_check(world.main_menu.get_node("StoryButton").text == "MODO HISTORIA", "Story button label")
	_check(world.player_name_input.text == "Jugador", "Name input label")
	world._start_game()
	_check(world.screen_mode == "game" and world.current_level == 0, "New game must start at level 1")
	_check(fake_api.attempts.size() == 1 and fake_api.attempts[0]["mode"] == "free", "Free game must create a level attempt")
	world._process(0.21)
	_check(fake_api.events.back()["type"] == "position_snapshot" and fake_api.events.back()["attempt"] == 0, "Position sample belongs to first attempt")

	for index in range(4):
		if world.current_level != index:
			world._load_level(index)
		world.player.set_physics_process(false)
		var expected: int = world.total_fruits
		var real_goal_area: Rect2 = world.goal_area
		var real_saws: Array[Dictionary] = world.saws
		var no_saws: Array[Dictionary] = []
		world.goal_area = Rect2(-100, -100, 1, 1)
		world.saws = no_saws
		while not world.fruits.is_empty():
			var fruit: Node2D = world.fruits[0].node
			var before: int = world.collected
			world.player.global_position = fruit.global_position
			world._check_interactions()
			_check(world.collected > before, "Fruit was not picked up in level %d" % (index + 1))
			if world.collected <= before:
				break
			await process_frame
		_check(world.collected == expected, "Wrong fruit total in level %d" % (index + 1))
		for fruit in world.level_root.get_node("Fruits").get_children():
			_check(not fruit.visible, "Picked fruit should be hidden")
		if not world.coins.is_empty():
			var first_coin: Node2D = world.coins[0]
			world.player.global_position = first_coin.global_position
			world._check_interactions()
			_check(world.collected_coins > 0 and not first_coin.visible, "Coin pickup failed")
		world.goal_area = real_goal_area
		world.saws = real_saws
		world.player.global_position = world.level_root.get_node("Goal").global_position
		world._check_interactions()
		_check(world.level_complete and world.completion_panel.visible, "Goal did not complete level %d" % (index + 1))
		_check(fake_api.runs.back()["attempt"] == fake_api.current_attempt and fake_api.events.back()["type"] == "level_completed", "Completion and leaderboard must share attempt")
		_check(not world.player.is_physics_processing(), "Player moved after completion")
		if index == 3:
			world._restart_level()
			_check(world.current_level == 3 and not world.level_complete and world.collected == 0, "Retry after final level failed")
			world.player.set_physics_process(false)
			world.player.global_position = world.level_root.get_node("Goal").global_position
			world._check_interactions()
		world._advance_level()
		if index < 3:
			_check(world.current_level == index + 1 and not world.level_complete, "Next level failed")
		else:
			_check(world.screen_mode == "menu", "Final level must return to menu")
		print("PASS level ", index + 1, ": pickups, goal, progression")

	world.player_name_input.text = "Otra persona"
	world._start_game()
	_check(world.run_name == "Otra persona" and world.current_level == 0 and not world.level_complete, "New player could not restart campaign")
	_check(fake_api.session_names == ["Jugador", "Otra persona"], "Player names were not attached to fresh sessions")
	_check(fake_api.runs.size() == 5, "Expected one saved run per level plus final-level retry")
	for index in range(4):
		_check(int(fake_api.runs[index]["level"]) == index, "Run saved under the wrong level")
	world.player.set_physics_process(false)
	world.player.global_position = world.saws[0].area.get_center()
	world._check_interactions()
	_check(not world.player.alive, "Saw did not trigger death")
	var death_attempt: int = fake_api.current_attempt
	var death_seconds: float = world.elapsed
	_check(fake_api.events.back()["type"] == "death" and fake_api.events.back()["attempt"] == death_attempt, "Death must be part of current attempt")
	world._process(0.21)
	_check(world.elapsed > death_seconds, "Timer must keep running while player waits to respawn")
	await create_timer(0.55).timeout
	_check(world.player.alive and world.player.global_position == world.player.spawn, "Respawn failed")
	_check(fake_api.events.back()["type"] == "respawn" and fake_api.events.back()["attempt"] == death_attempt, "Respawn must continue same attempt")
	_check(fake_api.events.back()["seconds"] > death_seconds, "Respawn must keep elapsed time after death")
	world.player.global_position = world.trampolines[0].get_center()
	world.player.velocity = Vector2.ZERO
	world._check_interactions()
	_check(world.player.velocity.y < -500.0, "Trampoline failed")
	world._restart_level()
	_check(world.collected == 0 and world.elapsed == 0.0, "Restart failed")
	_check(fake_api.current_attempt != death_attempt and fake_api.events.back()["type"] == "level_started", "Restart must create a new attempt")
	world._show_map_maker()
	var test_map: Dictionary = world.map_maker.map_data.duplicate(true)
	world._play_custom_map(test_map)
	_check(fake_api.attempts.back()["mode"] == "map_test" and fake_api.attempts.back()["map_data"] == test_map, "Map test must keep exact map snapshot")
	var map_attempt: int = fake_api.current_attempt
	world.player.set_physics_process(false)
	world.player.global_position = world.level_root.get_node("Goal").global_position
	world._check_interactions()
	_check(fake_api.events.back()["type"] == "map_test_completed" and fake_api.events.back()["attempt"] == map_attempt, "Custom map completion must stay in its attempt")
	world._reload_custom_map()
	_check(fake_api.current_attempt != map_attempt and fake_api.attempts.back()["mode"] == "map_test", "Custom map retry must create new attempt")
	world._show_main_menu()
	world._start_story()
	_check(world.story_phase == "prologue" and not world.player.is_physics_processing(), "Story prologue should pause player")
	world.story_panel._continue()
	_check(world.story_phase == "intro" and not world.player.is_physics_processing(), "First chapter intro should pause player")
	world.story_panel._continue()
	_check(world.screen_mode == "game" and world.player.is_physics_processing(), "Story chapter did not begin")
	world._finish_level()
	world._advance_level()
	world.story_panel._continue()
	_check(world.current_level == 1 and world.story_phase == "intro" and not world.player.is_physics_processing(), "Next chapter intro should pause player")
	world.queue_free()
	await process_frame
	print("Regression failures: ", failures)
	quit(1 if failures else 0)
