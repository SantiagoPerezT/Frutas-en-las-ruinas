extends SceneTree

# Keep the browser's official map drawings in sync with the Godot level data.
const Levels = preload("res://scripts/levels.gd")
const OUTPUT_PATH := "res://backend/wwwroot/official_levels.json"

func _initialize() -> void:
	call_deferred("_export")

func _export() -> void:
	var layouts: Array[Dictionary] = []
	for i in Levels.DATA.size():
		var source: Dictionary = Levels.DATA[i]
		var layout := {
			"level_id": i + 1,
			"name": source["name"],
			"width": int(Levels.LEVEL_WIDTH),
			"height": int(Levels.LEVEL_HEIGHT),
			"theme": source["theme"],
			"background": source["background"],
			"fruit": source["fruit"],
			"spawn": _point(source["spawn"]),
			"goal": _point(source["goal"]),
			"platforms": [],
			"fruits": [],
			"coins": [],
			"saws": [],
			"trampolines": []
		}
		for platform_variant in source["platforms"]:
			var platform: Rect2 = platform_variant
			layout["platforms"].append({"x": platform.position.x, "y": platform.position.y, "w": platform.size.x, "h": platform.size.y})
		for key in ["fruits", "coins", "saws", "trampolines"]:
			for point_variant in source[key]:
				layout[key].append(_point(point_variant))
		layouts.append(layout)
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo exportar la geometría web: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	file.store_string(JSON.stringify(layouts, "  ") + "\n")
	file.close()
	print("Exportados %d mapas oficiales para la landing." % layouts.size())
	quit()

func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
