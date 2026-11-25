extends Node
## Журнал генерации локаций (ФТ-17): одна JSON-строка на попытку генерации.
## В сетевой игре журнал ведёт только хост. Персональных данных не содержит.

const PATH := "user://genlog.jsonl"
const REQUIRED_FIELDS := LevelGenerator.LOG_FIELDS
const KEEP_IN_MEMORY := 32

## Последние записи — для отладочного оверлея F3.
var recent: Array[Dictionary] = []


## Выход из игры: модель генератора освобождается, пока расширение ONNX ещё загружено.
func _exit_tree() -> void:
	LevelService.release()


func write(entry: Dictionary) -> void:
	for field in REQUIRED_FIELDS:
		if not entry.has(field):
			push_error("GenLog: в записи нет обязательного поля «%s» (ФТ-17)" % field)
	var record := {}
	for key: String in entry:
		var value: Variant = entry[key]
		record[key] = Array(value) if value is PackedFloat32Array else value
	record["time"] = Time.get_datetime_string_from_system(true)
	record["game_version"] = ProjectSettings.get_setting("application/config/version", "")

	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(PATH) else FileAccess.WRITE
	var file := FileAccess.open(PATH, mode)
	if file == null:
		push_error("GenLog: не удалось открыть %s: %s" % [PATH, error_string(FileAccess.get_open_error())])
	else:
		file.seek_end()
		# full_precision: z должен восстанавливаться бит-в-бит для воспроизведения карты
		file.store_line(JSON.stringify(record, "", false, true))

	recent.append(record)
	if recent.size() > KEEP_IN_MEMORY:
		recent.pop_front()
	Events.generation_logged.emit(record)
