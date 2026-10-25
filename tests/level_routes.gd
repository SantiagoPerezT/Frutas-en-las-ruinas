extends SceneTree

# Real CharacterBody2D movement across the three sections of each level.
# Waypoints identify platform tops. Hazards are Sprite2D-only in the scenes;
# gameplay's world.gd handles their collisions separately.
const Levels = preload("res://scripts/levels.gd")
const ROUTES := [
	[Vector2(220, 370), Vector2(400, 234), Vector2(620, 180), Vector2(870, 220)],
	[Vector2(190, 360), Vector2(365, 290), Vector2(530, 180), Vector2(673, 270), Vector2(874, 190)],
	[Vector2(185, 365), Vector2(356, 295), Vector2(525, 225), Vector2(750, 285), Vector2(879, 175)],
	[Vector2(790, 360), Vector2(608, 280), Vector2(437, 170), Vector2(220, 260), Vector2(80, 175)],
]

func _initialize() -> void:
	call_deferred("_run")

func _release() -> void:
	for action in ["move_left", "move_right", "jump"]:
		Input.action_release(action)

func _expanded_route(index: int) -> Array[Vector2]:
	var route: Array[Vector2] = []
	var reverse := index == 3
	for section_step in Levels.SECTION_COUNT:
		var section := Levels.SECTION_COUNT - 1 - section_step if reverse else section_step
		var points: Array = ROUTES[index].duplicate()
		if section == 1:
			points.reverse()
		for point_variant in points:
			var point: Vector2 = point_variant
			var x := Levels.SECTION_WIDTH * float(section) + (Levels.SECTION_WIDTH - point.x if section == 1 else point.x)
			if index == 0 and section == 1 and point.x == 220.0:
				x = 1740.0 # Clear the upper ledge before landing on the lower one.
			var surface := _surface_y(index, x)
			var target_y := minf(point.y, surface) if section == 1 else point.y
			route.append(Vector2(x, target_y))
		if section == 1:
			if reverse:
				route.append(Vector2(1030, _surface_y(index, 1030)))
				route.append(Vector2(880, _surface_y(index, 880)))
			else:
				route.append(Vector2(1850, _surface_y(index, 1850)))
				route.append(Vector2(2000, _surface_y(index, 2000)))
	return route

func _surface_y(index: int, x: float) -> float:
	var result := Levels.LEVEL_HEIGHT
	for rect_variant in Levels.DATA[index].platforms:
		var rect: Rect2 = rect_variant
		if x >= rect.position.x and x <= rect.end.x:
			result = minf(result, rect.position.y)
	return result

func _run() -> void:
	for index in Levels.DATA.size():
		var stage: Node2D = load("res://scenes/level_%02d.tscn" % (index + 1)).instantiate()
		root.add_child(stage)
		var hero: FruitHero = stage.get_node("Player")
		var saw_nodes := stage.get_node("Saws").get_children()
		hero.world_width = Levels.LEVEL_WIDTH
		for frame in 30:
			await physics_frame
		for target in _expanded_route(index):
			var launched := false
			var second_jump := false
			var reached := false
			for frame in 240:
				_release()
				if not hero.alive:
					push_error("Muerte en nivel %d, camino a %s; jugador en %s" % [index + 1, target, hero.position])
					quit(1)
					return
				var player_box := Rect2(hero.global_position - Vector2(10, 14), Vector2(20, 28))
				for saw in saw_nodes:
					if player_box.intersects(Rect2(saw.position - Vector2(14, 14), Vector2(28, 28))):
						push_error("La ruta toca una sierra en nivel %d cerca de %s" % [index + 1, saw.position])
						quit(1)
						return
				if launched and hero.is_on_floor() and absf(hero.position.x - target.x) < 10 and absf(hero.position.y + 15.5 - target.y) < 3:
					reached = true
					break
				if hero.position.x < target.x - 4:
					Input.action_press("move_right")
				elif hero.position.x > target.x + 4:
					Input.action_press("move_left")
				if not launched:
					Input.action_press("jump")
					launched = true
				elif not second_jump and hero.velocity.y >= -30 and not hero.is_on_floor():
					Input.action_press("jump")
					second_jump = true
				await physics_frame
			if not reached:
				push_error("No se llegó a %s del nivel %d; jugador en %s" % [target, index + 1, hero.position])
				quit(1)
				return
			_release()
			await physics_frame
		var goal: Node2D = stage.get_node("Goal")
		var final_box := Rect2(hero.global_position - Vector2(10, 14), Vector2(20, 28))
		if not final_box.intersects(Rect2(goal.global_position - Vector2(22, 28), Vector2(44, 56))):
			push_error("El recorrido no llegó a la meta del nivel %d" % (index + 1))
			quit(1)
			return
		print("PASS recorrido físico: ", Levels.DATA[index].name)
		stage.queue_free()
		await process_frame
	_release()
	quit()
