extends SceneTree

const HeroScene := preload("res://scenes/player.tscn")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var hero := HeroScene.instantiate() as FruitHero
	hero.position = Vector2(100, 100)
	root.add_child(hero)
	var camera := hero.get_node("Camera2D") as DeathShakeCamera
	var sound := hero.get_node("JumpSound") as AudioStreamPlayer2D
	_check(sound.stream != null and sound.stream.get_length() > 0.0,
		"Falta el audio del salto")
	_check(camera.offset == Vector2.ZERO, "La cámara inició desplazada")

	Input.action_press("jump")
	await physics_frame
	await process_frame
	Input.action_release("jump")
	_check(sound.playing, "El sonido no se reprodujo al ejecutar un salto")

	hero.respawn("test")
	_check(camera.is_processing(), "La muerte no activó la sacudida")
	await process_frame
	_check(camera.offset.length() > 0.0, "La cámara no se desplazó al morir")
	await create_timer(0.35).timeout
	_check(camera.offset == Vector2.ZERO, "La cámara no volvió a su posición normal")

	hero.reset_to_spawn()
	hero.respawn("test")
	hero.reset_to_spawn()
	_check(camera.offset == Vector2.ZERO and not camera.is_processing(),
		"Reiniciar el nivel dejó la sacudida activa")
	Input.action_release("jump")
	hero.queue_free()
	await process_frame
	print("Player feedback failures: ", failures)
	quit(1 if failures else 0)
