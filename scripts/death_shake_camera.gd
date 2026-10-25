class_name DeathShakeCamera
extends Camera2D

@export_range(0.0, 24.0, 0.5) var shake_strength := 11.0
@export_range(0.05, 1.0, 0.01) var shake_duration := 0.28

var _remaining := 0.0
var _random := RandomNumberGenerator.new()

func _ready() -> void:
	_random.randomize()
	set_process(false)

func _process(delta: float) -> void:
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining <= 0.0:
		clear_shake()
		return
	var intensity := shake_strength * _remaining / shake_duration
	offset = Vector2(_random.randf_range(-intensity, intensity),
		_random.randf_range(-intensity, intensity))

func _on_player_died(_cause: String) -> void:
	_remaining = shake_duration
	set_process(true)

func clear_shake() -> void:
	_remaining = 0.0
	offset = Vector2.ZERO
	set_process(false)
