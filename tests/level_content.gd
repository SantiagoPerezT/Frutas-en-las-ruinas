extends SceneTree

const Levels = preload("res://scripts/levels.gd")
const Story = preload("res://scripts/story.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	if Levels.DATA.size() != Story.CHAPTERS.size():
		push_error("Cada nivel necesita un capítulo.")
		quit(1)
		return
	var layout_file := FileAccess.open("res://backend/wwwroot/official_levels.json", FileAccess.READ)
	if layout_file == null:
		push_error("Falta el dibujo de mapas oficiales para la landing.")
		quit(1)
		return
	var parsed_layouts: Variant = JSON.parse_string(layout_file.get_as_text())
	if not parsed_layouts is Array or parsed_layouts.size() != Levels.DATA.size():
		push_error("La landing no tiene los cuatro mapas oficiales exportados.")
		quit(1)
		return
	for i in Levels.DATA.size():
		var layout: Dictionary = parsed_layouts[i]
		if int(layout.get("level_id", 0)) != i + 1 or str(layout.get("name", "")) != str(Levels.DATA[i]["name"]):
			push_error("Identidad web obsoleta en nivel %d." % (i + 1))
			quit(1)
			return
		if str(layout.get("theme", "")) != str(Levels.DATA[i]["theme"]) or str(layout.get("background", "")) != str(Levels.DATA[i]["background"]) or str(layout.get("fruit", "")) != str(Levels.DATA[i]["fruit"]):
			push_error("Texturas web obsoletas en nivel %d." % (i + 1))
			quit(1)
			return
		if int(layout.get("width", 0)) != int(Levels.LEVEL_WIDTH) or int(layout.get("height", 0)) != int(Levels.LEVEL_HEIGHT):
			push_error("Dimensiones web obsoletas en nivel %d." % (i + 1))
			quit(1)
			return
		for point_key in ["spawn", "goal"]:
			if not _matches_point(layout.get(point_key, {}), Levels.DATA[i][point_key]):
				push_error("Coordenadas web obsoletas en nivel %d: %s." % [i + 1, point_key])
				quit(1)
				return
		for key in ["platforms", "fruits", "coins", "saws", "trampolines"]:
			if layout.get(key, []).size() != Levels.DATA[i][key].size():
				push_error("Geometría web obsoleta en nivel %d: %s." % [i + 1, key])
				quit(1)
				return
			for item_index in Levels.DATA[i][key].size():
				var exported_item: Dictionary = layout[key][item_index]
				var source_item: Variant = Levels.DATA[i][key][item_index]
				if key == "platforms":
					var rect: Rect2 = source_item
					if not _matches_point(exported_item, rect.position) or not is_equal_approx(float(exported_item.get("w", NAN)), rect.size.x) or not is_equal_approx(float(exported_item.get("h", NAN)), rect.size.y):
						push_error("Plataforma web obsoleta en nivel %d, elemento %d." % [i + 1, item_index])
						quit(1)
						return
				elif not _matches_point(exported_item, source_item):
					push_error("Objeto web obsoleto en nivel %d: %s, elemento %d." % [i + 1, key, item_index])
					quit(1)
					return
		if absf(Levels.DATA[i].goal.x - Levels.DATA[i].spawn.x) < 2000.0:
			push_error("El nivel %d no ocupa las tres secciones." % (i + 1))
			quit(1)
			return
		var scene: PackedScene = load("res://scenes/level_%02d.tscn" % (i + 1))
		if scene == null:
			push_error("No se pudo abrir el nivel %d" % (i + 1))
			quit(1)
			return
		var instance := scene.instantiate()
		root.add_child(instance)
		for key in ["Platforms", "Trampolines", "Saws", "Fruits", "Coins"]:
			var expected: int = Levels.DATA[i][key.to_lower()].size()
			var actual: int = instance.get_node(key).get_child_count()
			if actual != expected:
				push_error("Nivel %d, %s: %d nodos; se esperaban %d" % [i + 1, key, actual, expected])
				quit(1)
				return
		var camera: Camera2D = instance.get_node("Player/Camera2D")
		if camera.limit_right != int(Levels.LEVEL_WIDTH):
			push_error("Límite de cámara incorrecto en nivel %d" % (i + 1))
			quit(1)
			return
		if instance.get_node("Scenery").level_width != Levels.LEVEL_WIDTH:
			push_error("El fondo no cubre el nivel %d completo." % (i + 1))
			quit(1)
			return
		instance.queue_free()
		await process_frame
	var panel: CanvasLayer = load("res://scenes/story_panel.tscn").instantiate()
	root.add_child(panel)
	panel.show_chapter(2)
	if panel.get_node("Overlay/Card/VBox/Body").text != Story.CHAPTERS[2].intro:
		push_error("El panel no muestra la historia del capítulo.")
		quit(1)
		return
	panel.queue_free()
	print("PASS: cuatro mapas largos, monedas, cámaras e historia")
	quit()

func _matches_point(exported: Dictionary, source: Vector2) -> bool:
	return is_equal_approx(float(exported.get("x", NAN)), source.x) and is_equal_approx(float(exported.get("y", NAN)), source.y)
