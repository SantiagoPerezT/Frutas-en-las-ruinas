extends SceneTree

# Real CharacterBody2D collisions and input on a small platform, without SQL.
const HeroScene := preload("res://scenes/player.tscn")

var hero: FruitHero
var jump_numbers: Array[int] = []
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _on_jumped(jump_number: int) -> void:
	jump_numbers.append(jump_number)

func _step(count: int = 1) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _wait_for_floor() -> bool:
	for i in 90:
		await _step()
		if hero.is_on_floor():
			return true
	return false

func _walk_off() -> bool:
	Input.action_press("move_right")
	for i in 100:
		await _step()
		if not hero.is_on_floor() and hero.global_position.x > 330.0:
			Input.action_release("move_right")
			return true
	Input.action_release("move_right")
	return false

func _press_jump() -> void:
	Input.action_press("jump")
	await _step()
	Input.action_release("jump")

func _run() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var ground := StaticBody2D.new()
	ground.position = Vector2(200, 250)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(240, 20)
	collision.shape = shape
	ground.add_child(collision)
	arena.add_child(ground)
	hero = HeroScene.instantiate() as FruitHero
	hero.position = Vector2(200, 180)
	arena.add_child(hero)
	hero.jumped.connect(_on_jumped)
	_check(await _wait_for_floor(), "El jugador no aterrizó en la plataforma de prueba")

	# A recently departed platform still grants the full first jump and a later air jump.
	_check(await _walk_off(), "El jugador no abandonó la plataforma")
	await _press_jump()
	_check(jump_numbers.size() == 1 and jump_numbers.back() == 1,
		"Coyote time no conservó el salto de suelo")
	await _step(5)
	await _press_jump()
	_check(jump_numbers.size() == 2 and jump_numbers.back() == 2,
		"El salto de coyote consumió indebidamente el doble salto")

	# After the grace window, only the air jump remains.
	hero.reset_to_spawn()
	_check(await _wait_for_floor(), "No volvió al suelo tras reiniciar")
	_check(await _walk_off(), "No pudo abandonar la plataforma por segunda vez")
	await _step(10)
	await _press_jump()
	_check(jump_numbers.size() == 3 and jump_numbers.back() == 2,
		"El salto de suelo siguió disponible después del coyote time")

	# An exhausted jump pressed shortly before landing fires on the next grounded tick.
	hero.reset_to_spawn()
	_check(await _wait_for_floor(), "No volvió al suelo antes de probar el buffer")
	hero.set_physics_process(false)
	hero.global_position = Vector2(200, 195)
	hero.velocity = Vector2(0, 330)
	hero.set_physics_process(true)
	await _step()
	hero.jumps_left = 0
	var before_buffer := jump_numbers.size()
	await _press_jump()
	_check(jump_numbers.size() == before_buffer, "El salto sin cargas se ejecutó antes de aterrizar")
	for i in 12:
		await _step()
		if jump_numbers.size() > before_buffer:
			break
	_check(jump_numbers.size() == before_buffer + 1 and jump_numbers.back() == 1,
		"El salto almacenado no se ejecutó al aterrizar")

	# An old input must not execute after the buffer has expired.
	hero.reset_to_spawn()
	_check(await _wait_for_floor(), "No volvió al suelo antes de probar la expiración")
	hero.set_physics_process(false)
	hero.global_position = Vector2(200, 120)
	hero.velocity = Vector2.ZERO
	hero.set_physics_process(true)
	await _step()
	hero.jumps_left = 0
	var before_expired := jump_numbers.size()
	await _press_jump()
	await _step(45)
	_check(hero.is_on_floor() and jump_numbers.size() == before_expired,
		"Un salto almacenado ya vencido se ejecutó al aterrizar")

	# A trampoline keeps one air jump, even when the player bounced from the floor.
	hero.bounce()
	await _step()
	_check(hero.jumps_left == 1 and hero.velocity.y < -400,
		"El trampolín restauró incorrectamente el salto de suelo")
	await _press_jump()
	_check(jump_numbers.size() == before_expired + 1 and jump_numbers.back() == 2,
		"El trampolín no conservó el salto aéreo")

	Input.action_release("move_right")
	Input.action_release("jump")
	arena.queue_free()
	await process_frame
	print("Jump assist failures: ", failures)
	quit(1 if failures else 0)
