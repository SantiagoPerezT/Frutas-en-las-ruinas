extends SceneTree

const LEVELS = preload("res://scripts/levels.gd")
const PLATFORM_PATH = "res://scenes/platform.tscn"
const PLAYER_PATH = "res://scenes/player.tscn"
const COIN_PATH = "res://scenes/coin.tscn"
const SCENERY_SCRIPT = "res://scripts/scenery.gd"

func _initialize() -> void:
	call_deferred("_generate")

func _generate() -> void:
	# Regenerate level scenes without replacing editor changes in main.tscn.
	for i in LEVELS.DATA.size():
		_write_level(i, LEVELS.DATA[i])
	print("Generated %d editor-visible Godot level scenes." % LEVELS.DATA.size())
	quit()

func _write_level(index: int, data: Dictionary) -> void:
	var header := "[gd_scene load_steps=11 format=3 uid=\"uid://ch2iwnh5esmvy\"]" if index == 0 else "[gd_scene load_steps=11 format=3]"
	var lines := PackedStringArray([header, ""])
	lines.append_array([
		"[ext_resource type=\"PackedScene\" path=\"%s\" id=\"platform\"]" % PLATFORM_PATH,
		"[ext_resource type=\"PackedScene\" path=\"%s\" id=\"player\"]" % PLAYER_PATH,
		"[ext_resource type=\"PackedScene\" path=\"%s\" id=\"coin\"]" % COIN_PATH,
		"[ext_resource type=\"Script\" path=\"%s\" id=\"scenery\"]" % SCENERY_SCRIPT,
		"[ext_resource type=\"Texture2D\" path=\"res://Assets/Background/%s.png\" id=\"background\"]" % data.background,
		"[ext_resource type=\"Texture2D\" path=\"res://Assets/Items/Fruits/%s.png\" id=\"fruit\"]" % data.fruit,
		"[ext_resource type=\"Texture2D\" path=\"res://Assets/Traps/Trampoline/Idle.png\" id=\"trampoline\"]",
		"[ext_resource type=\"Texture2D\" path=\"res://Assets/Traps/Saw/On (38x38).png\" id=\"saw\"]",
		"[ext_resource type=\"Texture2D\" path=\"res://Assets/Items/Checkpoints/End/End (Idle).png\" id=\"goal\"]",
		"",
		"[sub_resource type=\"AtlasTexture\" id=\"SawAtlas\"]",
		"atlas = ExtResource(\"saw\")",
		"region = Rect2(0, 0, 38, 38)",
		"",
		"[node name=\"%s\" type=\"Node2D\"]" % data.name.replace(" ", ""),
		"",
		"[node name=\"Scenery\" type=\"Node2D\" parent=\".\"]",
		"z_index = -10",
		"script = ExtResource(\"scenery\")",
		"theme = \"%s\"" % data.theme,
		"background_texture = ExtResource(\"background\")",
		"level_width = %s" % LEVELS.LEVEL_WIDTH,
		"",
		"[node name=\"Platforms\" type=\"Node2D\" parent=\".\"]",
	])
	for j in data.platforms.size():
		var rect: Rect2 = data.platforms[j]
		lines.append_array([
			"",
			"[node name=\"Platform%02d\" parent=\"Platforms\" instance=ExtResource(\"platform\")]" % (j + 1),
			"position = Vector2(%s, %s)" % [rect.position.x, rect.position.y],
			"platform_size = Vector2(%s, %s)" % [rect.size.x, rect.size.y],
			"theme = \"%s\"" % data.theme,
		])
	lines.append_array(["", "[node name=\"Trampolines\" type=\"Node2D\" parent=\".\"]"])
	for j in data.trampolines.size():
		var pos: Vector2 = data.trampolines[j]
		lines.append_array(["", "[node name=\"Trampoline%02d\" type=\"Sprite2D\" parent=\"Trampolines\" groups=[\"trampoline\"]]" % (j + 1), "position = Vector2(%s, %s)" % [pos.x, pos.y], "texture = ExtResource(\"trampoline\")", "scale = Vector2(1.1, 1.1)"])
	lines.append_array(["", "[node name=\"Saws\" type=\"Node2D\" parent=\".\"]"])
	for j in data.saws.size():
		var pos: Vector2 = data.saws[j]
		lines.append_array(["", "[node name=\"Saw%02d\" type=\"Sprite2D\" parent=\"Saws\" groups=[\"saw\"]]" % (j + 1), "position = Vector2(%s, %s)" % [pos.x, pos.y], "texture = SubResource(\"SawAtlas\")"])
	lines.append_array(["", "[node name=\"Fruits\" type=\"Node2D\" parent=\".\"]"])
	for j in data.fruits.size():
		var pos: Vector2 = data.fruits[j]
		lines.append_array(["", "[node name=\"Fruit%02d\" type=\"Sprite2D\" parent=\"Fruits\" groups=[\"fruit\"]]" % (j + 1), "position = Vector2(%s, %s)" % [pos.x, pos.y], "texture = ExtResource(\"fruit\")", "region_enabled = true", "region_rect = Rect2(%s, 0, 32, 32)" % ((j % 17) * 32)])
	lines.append_array(["", "[node name=\"Coins\" type=\"Node2D\" parent=\".\"]"])
	for j in data.coins.size():
		var coin_pos: Vector2 = data.coins[j]
		lines.append_array(["", "[node name=\"Coin%02d\" parent=\"Coins\" instance=ExtResource(\"coin\")]" % (j + 1), "position = Vector2(%s, %s)" % [coin_pos.x, coin_pos.y]])
	lines.append_array([
		"", "[node name=\"Goal\" type=\"Sprite2D\" parent=\".\" groups=[\"goal\"]]",
		"position = Vector2(%s, %s)" % [data.goal.x, data.goal.y],
		"texture = ExtResource(\"goal\")",
		"scale = Vector2(0.7, 0.7)",
		"", "[node name=\"Player\" parent=\".\" instance=ExtResource(\"player\") ]",
		"position = Vector2(%s, %s)" % [data.spawn.x, data.spawn.y],
	])
	_write("res://scenes/level_%02d.tscn" % (index + 1), lines)

func _write(path: String, lines: PackedStringArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % path)
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()
