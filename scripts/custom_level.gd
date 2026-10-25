extends Node2D

const PLATFORM_SCENE: PackedScene = preload("res://scenes/platform.tscn")
const COIN_SCENE: PackedScene = preload("res://scenes/coin.tscn")
const APPLE_TEXTURE: Texture2D = preload("res://Assets/Items/Fruits/Apple.png")
const CHERRIES_TEXTURE: Texture2D = preload("res://Assets/Items/Fruits/Cherries.png")
const ORANGE_TEXTURE: Texture2D = preload("res://Assets/Items/Fruits/Orange.png")
const STRAWBERRY_TEXTURE: Texture2D = preload("res://Assets/Items/Fruits/Strawberry.png")
const SAW_TEXTURE: Texture2D = preload("res://Assets/Traps/Saw/On (38x38).png")
const TRAMPOLINE_TEXTURE: Texture2D = preload("res://Assets/Traps/Trampoline/Idle.png")
const RUINS_BACKGROUND: Texture2D = preload("res://Assets/Background/Brown.png")
const FOREST_BACKGROUND: Texture2D = preload("res://Assets/Background/Green.png")
const DESERT_BACKGROUND: Texture2D = preload("res://Assets/Background/Yellow.png")
const SNOW_BACKGROUND: Texture2D = preload("res://Assets/Background/Blue.png")

const MAP_WIDTH := 960.0
const MAP_HEIGHT := 540.0

var current_data: Dictionary = {}

func build_from_data(data: Dictionary) -> bool:
	if not data.get("spawn") is Dictionary or not data.get("goal") is Dictionary:
		push_warning("El mapa personalizado necesita inicio y meta.")
		return false
	var theme := str(data.get("theme", "ruins"))
	if theme not in ["ruins", "forest", "desert", "snow"]:
		theme = "ruins"
	current_data = data.duplicate(true)
	var scenery: Node2D = $Scenery
	scenery.theme = theme
	scenery.level_width = MAP_WIDTH
	scenery.background_texture = _background_for_theme(theme)
	_clear_objects()
	_add_platforms(data.get("platforms", []), theme)
	_add_sprites(data.get("fruits", []), $Fruits, _fruit_for_theme(theme), Vector2(32, 32), "Fruit", "fruit")
	_add_sprites(data.get("saws", []), $Saws, SAW_TEXTURE, Vector2(38, 38), "Saw", "saw")
	_add_sprites(data.get("trampolines", []), $Trampolines, TRAMPOLINE_TEXTURE, Vector2(28, 28), "Trampoline", "trampoline")
	_add_coins(data.get("coins", []))
	$Goal.position = _safe_point(data["goal"])
	var hero := $Player as FruitHero
	hero.position = _safe_point(data["spawn"])
	hero.spawn = hero.global_position
	if hero.is_node_ready():
		hero.reset_to_spawn()
	var camera := hero.get_node_or_null("Camera2D") as Camera2D
	if camera:
		camera.limit_right = int(MAP_WIDTH)
	return true

func _clear_objects() -> void:
	for bucket_name in ["Platforms", "Fruits", "Coins", "Saws", "Trampolines"]:
		var bucket := get_node(bucket_name)
		for child in bucket.get_children():
			bucket.remove_child(child)
			child.queue_free()

func _add_platforms(entries: Variant, theme: String) -> void:
	if not entries is Array:
		return
	var index := 0
	for entry in entries:
		if not entry is Dictionary:
			continue
		var width := clampf(float(entry.get("w", 24)), 24, MAP_WIDTH)
		var height := clampf(float(entry.get("h", 24)), 24, MAP_HEIGHT)
		var platform: GrassPlatform = PLATFORM_SCENE.instantiate()
		platform.name = "Platform%02d" % (index + 1)
		platform.theme = theme
		platform.position = Vector2(clampf(float(entry.get("x", 0)), 0, MAP_WIDTH - width), clampf(float(entry.get("y", 0)), 0, MAP_HEIGHT - height))
		platform.platform_size = Vector2(width, height)
		$Platforms.add_child(platform)
		index += 1

func _add_sprites(entries: Variant, bucket: Node2D, texture: Texture2D, frame: Vector2, prefix: String, group: String) -> void:
	if not entries is Array:
		return
	var index := 0
	for entry in entries:
		if not entry is Dictionary:
			continue
		var sprite := Sprite2D.new()
		sprite.name = "%s%02d" % [prefix, index + 1]
		sprite.texture = texture
		sprite.region_enabled = true
		sprite.region_rect = Rect2(Vector2.ZERO, frame)
		sprite.position = _safe_point(entry)
		sprite.add_to_group(group)
		bucket.add_child(sprite)
		index += 1

func _add_coins(entries: Variant) -> void:
	if not entries is Array:
		return
	var index := 0
	for entry in entries:
		if not entry is Dictionary:
			continue
		var coin := COIN_SCENE.instantiate() as Area2D
		coin.name = "Coin%02d" % (index + 1)
		coin.position = _safe_point(entry)
		$Coins.add_child(coin)
		index += 1

func _safe_point(entry: Dictionary) -> Vector2:
	return Vector2(clampf(float(entry.get("x", 0)), 0, MAP_WIDTH), clampf(float(entry.get("y", 0)), 0, MAP_HEIGHT))

func _fruit_for_theme(theme: String) -> Texture2D:
	match theme:
		"forest": return CHERRIES_TEXTURE
		"desert": return ORANGE_TEXTURE
		"snow": return STRAWBERRY_TEXTURE
		_: return APPLE_TEXTURE

func _background_for_theme(theme: String) -> Texture2D:
	match theme:
		"forest": return FOREST_BACKGROUND
		"desert": return DESERT_BACKGROUND
		"snow": return SNOW_BACKGROUND
		_: return RUINS_BACKGROUND
