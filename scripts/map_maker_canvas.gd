@tool
extends Panel

@export var field_color := Color("273849"):
	set(value):
		field_color = value
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), field_color)
	for x in range(0, int(size.x) + 1, 16):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.075), 1.0)
	for y in range(0, int(size.y) + 1, 16):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.075), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color("c8d9ec"), false, 2.0)
