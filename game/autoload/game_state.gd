extends Node
## Состояние забега. На хосте — источник истины; клиенты получают его через сетевой модуль (game/net/).

const LEVEL_DURATION := 300.0  # ФТ-09: по истечении — босс

var current_level: LevelData
var level_index := 0
var level_time_left := 0.0
var running := false


func begin_level(level: LevelData) -> void:
	current_level = level
	level_time_left = LEVEL_DURATION
	running = true
	Events.level_loaded.emit(level)


func end_run() -> void:
	running = false
	current_level = null
	level_index = 0


func _process(delta: float) -> void:
	if not running or not multiplayer.is_server():
		return
	level_time_left = maxf(level_time_left - delta, 0.0)
	if level_time_left == 0.0:
		running = false
		Events.level_timer_expired.emit()
