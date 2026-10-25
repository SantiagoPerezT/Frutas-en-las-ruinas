@tool
extends Node2D

@export_enum("ruins", "forest", "desert", "snow") var theme := "ruins":
	set(value):
		theme = value
		queue_redraw()
@export var background_texture: Texture2D:
	set(value):
		background_texture = value
		queue_redraw()
@export var level_width := 960.0:
	set(value):
		level_width = maxf(960.0, value)
		queue_redraw()

func _draw() -> void:
	for section in ceili(level_width / 960.0):
		draw_set_transform(Vector2(section * 960.0, 0))
		_draw_section()
	draw_set_transform(Vector2.ZERO)

func _draw_section() -> void:
	if background_texture:
		draw_texture_rect(background_texture, Rect2(0, 0, 960, 540), true)
	match theme:
		"forest":
			draw_rect(Rect2(0, 0, 960, 540), Color(0.03, 0.18, 0.16, 0.35))
			for x in range(-30, 1000, 115):
				var y := 160 + (x * 7 % 65)
				draw_rect(Rect2(x + 39, y, 27, 370), Color("315c49"))
				draw_rect(Rect2(x + 47, y, 7, 370), Color("3c7052"))
				for branch in range(3):
					draw_rect(Rect2(x - branch * 14, y + branch * 40, 104 + branch * 28, 52), Color("397951"))
			for x in range(45, 960, 91):
				draw_rect(Rect2(x, 180 + x * 13 % 250, 3, 3), Color("d4e79a"))
		"desert":
			draw_rect(Rect2(0, 0, 960, 540), Color(0.76, 0.36, 0.13, 0.15))
			draw_circle(Vector2(770, 145), 43, Color("ffe8a2"))
			for x in range(-160, 1100, 260):
				draw_colored_polygon(PackedVector2Array([Vector2(x, 485), Vector2(x + 155, 245), Vector2(x + 345, 485)]), Color("d6a15f"))
				draw_colored_polygon(PackedVector2Array([Vector2(x + 155, 245), Vector2(x + 205, 485), Vector2(x + 345, 485)]), Color("c98b54"))
			for x in [98, 605, 790]:
				draw_rect(Rect2(x, 355, 12, 130), Color("8e9462"))
				draw_rect(Rect2(x - 19, 385, 22, 10), Color("8e9462"))
				draw_rect(Rect2(x - 19, 368, 9, 22), Color("8e9462"))
				draw_rect(Rect2(x + 10, 402, 23, 10), Color("8e9462"))
				draw_rect(Rect2(x + 25, 382, 8, 26), Color("8e9462"))
		"snow":
			draw_rect(Rect2(0, 0, 960, 540), Color(0.12, 0.2, 0.45, 0.24))
			for x in range(-100, 1100, 230):
				draw_colored_polygon(PackedVector2Array([Vector2(x, 490), Vector2(x + 145, 155), Vector2(x + 330, 490)]), Color("8cb4d2"))
				draw_colored_polygon(PackedVector2Array([Vector2(x + 103, 252), Vector2(x + 145, 155), Vector2(x + 199, 252), Vector2(x + 158, 231), Vector2(x + 139, 250), Vector2(x + 123, 233)]), Color("d9eff4"))
			for i in range(65):
				draw_rect(Rect2(28 + i * 137 % 905, 100 + i * 71 % 383, 3, 3), Color("d3edf5"))
		_:
			for x in [90, 310, 580, 820]:
				draw_rect(Rect2(x, 230, 40, 280), Color("967467"))
				draw_rect(Rect2(x - 8, 225, 56, 16), Color("b08671"))
				for y in range(260, 510, 32):
					draw_line(Vector2(x, y), Vector2(x + 40, y), Color("82685e"), 2)
