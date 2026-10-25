@tool
class_name GrassPlatform
extends StaticBody2D

@export_enum("ruins", "forest", "desert", "snow") var theme := "ruins":
	set(value):
		theme = value
		palette = _colors_for_theme(value)
@export var platform_size := Vector2(100, 28):
	set(value):
		platform_size = value
		queue_redraw()
		_update_collision()
@export var palette: Array[Color] = [Color("a74f46"), Color("b75a4e"), Color("477e32"), Color("77be45"), Color("913e3d"), Color("c86a57")]:
	set(value):
		palette = value
		queue_redraw()

func setup(rect: Rect2, colors: Array = []) -> void:
	if not colors.is_empty():
		for i in mini(colors.size(), palette.size()):
			palette[i] = colors[i]
	platform_size = rect.size
	position = rect.position
	_update_collision()

func _ready() -> void:
	_update_collision()
	queue_redraw()

func _colors_for_theme(value: String) -> Array[Color]:
	match value:
		"forest":
			return [Color("624934"), Color("79533c"), Color("24704c"), Color("82db70"), Color("463c31"), Color("926849")]
		"desert":
			return [Color("a75a38"), Color("c97c42"), Color("dca34d"), Color("ffe08a"), Color("995136"), Color("edac62")]
		"snow":
			return [Color("476d9b"), Color("608aba"), Color("a8dcec"), Color("effbff"), Color("385b8b"), Color("82b9d5")]
		_:
			return [Color("a74f46"), Color("b75a4e"), Color("477e32"), Color("77be45"), Color("913e3d"), Color("c86a57")]

func _update_collision() -> void:
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape and shape.shape is RectangleShape2D:
		shape.shape.size = platform_size
		shape.position = platform_size / 2.0

func _draw() -> void:
	# Earth body and hand-drawn pixel-like grass edging.
	draw_rect(Rect2(Vector2.ZERO, platform_size), palette[0])
	draw_rect(Rect2(Vector2(0, 8), Vector2(platform_size.x, platform_size.y - 8)), palette[1])
	draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 9)), palette[2])
	draw_rect(Rect2(Vector2(0, 1), Vector2(platform_size.x, 5)), palette[3])
	for y in range(17, int(platform_size.y), 15):
		for x in range(7 + (y % 2) * 4, int(platform_size.x), 18):
			draw_line(Vector2(x, y), Vector2(x + 6, y + 2), palette[4], 2)
		draw_line(Vector2(2, y + 5), Vector2(platform_size.x - 4, y + 5), palette[5], 1)
