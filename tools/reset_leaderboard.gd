extends SceneTree

const LeaderboardStore = preload("res://scripts/leaderboard_store.gd")

func _initialize() -> void:
	var result: Error = LeaderboardStore.reset_data()
	if result != OK:
		push_error("No se pudo restablecer la tabla local: %s" % error_string(result))
		quit(1)
		return
	print("Tabla de tiempos restablecida. Se guardará al terminar otra partida.")
	quit()
