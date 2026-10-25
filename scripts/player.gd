@tool
class_name FruitHero
extends CharacterBody2D

signal respawned
signal jumped(jump_number: int)
signal died(cause: String)

const SPEED := 245.0
const JUMP_VELOCITY := -440.0
const GRAVITY := 1200.0
@export var world_width := 960.0
var spawn := Vector2.ZERO
var jumps_left := 2
var alive := true
var sprite: AnimatedSprite2D
var respawn_generation := 0
# Prevents a bounce/jump from restoring both jumps while the previous floor contact is still reported.
var floor_reset_locked := false

@onready var jump_buffer_timer: Timer = $JumpBufferTimer
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var camera: DeathShakeCamera = $Camera2D
@onready var jump_sound: AudioStreamPlayer2D = $JumpSound

func _ready() -> void:
	spawn = global_position
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		add_child(collision)
	var shape := collision.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
	shape.size = Vector2(20, 27)
	collision.shape = shape
	collision.position = Vector2(0, 2)
	sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		sprite = AnimatedSprite2D.new()
		sprite.name = "AnimatedSprite2D"
		add_child(sprite)
	sprite.sprite_frames = _make_frames()
	sprite.animation = &"idle"
	if not Engine.is_editor_hint():
		sprite.play()
	sprite.centered = true
	jump_buffer_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	coyote_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	coyote_timer.start()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not alive:
		return
	var on_floor := is_on_floor()
	if on_floor and not floor_reset_locked:
		jumps_left = 2
		coyote_timer.start()
	elif not on_floor:
		floor_reset_locked = false
		# Walking off a ledge eventually costs only the ground jump, not the air jump.
		if coyote_timer.is_stopped() and jumps_left == 2:
			jumps_left = 1
	if not on_floor:
		velocity.y += GRAVITY * delta
	var direction := Input.get_axis("move_left", "move_right")
	velocity.x = move_toward(velocity.x, direction * SPEED, 1700.0 * delta)
	if direction != 0:
		sprite.flip_h = direction < 0
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer.start()
	# A press with no jumps left stays queued until landing, or until this timer expires.
	if not jump_buffer_timer.is_stopped() and jumps_left > 0:
		var jump_number := 3 - jumps_left
		velocity.y = JUMP_VELOCITY if jumps_left == 2 else JUMP_VELOCITY * 0.88
		jumps_left -= 1
		jump_buffer_timer.stop()
		coyote_timer.stop()
		floor_reset_locked = on_floor
		_set_animation("jump")
		jump_sound.pitch_scale = 1.0 if jump_number == 1 else 1.12
		jump_sound.play()
		jumped.emit(jump_number)
	if not is_on_floor() and velocity.y > 80:
		_set_animation("fall")
	elif abs(velocity.x) > 20:
		_set_animation("run")
	elif is_on_floor():
		_set_animation("idle")
	move_and_slide()
	if not is_on_floor():
		floor_reset_locked = false
	global_position.x = clampf(global_position.x, 32.0, maxf(32.0, world_width - 32.0))
	if global_position.y > 590:
		respawn("fall")

func bounce() -> void:
	velocity.y = -590.0
	jumps_left = 1
	jump_buffer_timer.stop()
	coyote_timer.stop()
	floor_reset_locked = is_on_floor()

func respawn(cause: String = "fall") -> void:
	if not alive:
		return
	var generation := respawn_generation
	alive = false
	died.emit(cause)
	jump_sound.stop()
	velocity = Vector2.ZERO
	jump_buffer_timer.stop()
	coyote_timer.stop()
	sprite.animation = &"hit"
	sprite.play()
	await get_tree().create_timer(0.48).timeout
	if generation != respawn_generation:
		return
	global_position = spawn
	jumps_left = 2
	floor_reset_locked = false
	coyote_timer.start()
	alive = true
	_set_animation("idle")
	respawned.emit()

func reset_to_spawn() -> void:
	respawn_generation += 1
	alive = true
	velocity = Vector2.ZERO
	jumps_left = 2
	jump_buffer_timer.stop()
	coyote_timer.start()
	jump_sound.stop()
	camera.clear_shake()
	floor_reset_locked = false
	global_position = spawn
	_set_animation("idle")

func _set_animation(next: StringName) -> void:
	if sprite.animation != next:
		sprite.animation = next
		sprite.play()

func _make_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	var animations := {&"idle": ["Idle (32x32).png", 11, 5.0], &"run": ["Run (32x32).png", 12, 13.0], &"jump": ["Jump (32x32).png", 1, 1.0], &"fall": ["Fall (32x32).png", 1, 1.0], &"hit": ["Hit (32x32).png", 7, 12.0]}
	for name in animations:
		frames.add_animation(name)
		frames.set_animation_speed(name, animations[name][2])
		frames.set_animation_loop(name, name != &"hit")
		var texture: Texture2D = load("res://Assets/Main Characters/Mask Dude/" + animations[name][0])
		for i in animations[name][1]:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * 32, 0, 32, 32)
			frames.add_frame(name, atlas)
	return frames
