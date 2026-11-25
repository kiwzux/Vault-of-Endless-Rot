@tool
extends Node2D
## Просмотр комнат датасета в редакторе (решение П-1, DESIGN 0): комната создаётся процедурным генератором
## прямо в TileMapLayer, человек её только смотрит и при необходимости отбраковывает — не рисует (ОГР-03).
## Откройте сцену tools/dataset/dataset_preview.tscn, меняйте параметры в инспекторе:
## «Следующая» — следующий сид, «Отбраковать» — сид попадает в ml/data/rejected.txt и в датасет не войдёт.

@export_enum("rooms", "caves", "halls", "arena") var room_type := 0:
	set(value):
		room_type = value
		_render()
@export_enum("forest", "flooded_crypt", "cathedral", "abyss") var biome := 0:
	set(value):
		biome = value
		_render()
## Номер комнаты внутри класса — тот же, что использует build_dataset.gd.
@export var sample := 1:
	set(value):
		sample = maxi(1, value)
		_render()
@export var next_sample := false:
	set(value):
		if value:
			sample += 1
@export var reject_sample := false:
	set(value):
		if value:
			_reject()
## Результат проверки проходимости текущей комнаты (только для чтения).
@export var status := ""


func _ready() -> void:
	_render()


func seed_value() -> int:
	return DatasetGenerators.class_seed(room_type, biome, sample)


func _render() -> void:
	if not is_node_ready():
		return
	var level := DatasetGenerators.generate(room_type, biome, seed_value())
	LevelBuilder.build(level, $Ground, $Markers)
	$Ground.set_meta(&"room_type", room_type)
	$Ground.set_meta(&"biome", biome)
	var report := LevelValidator.new().validate(level)
	var rejected := DatasetGenerators.load_rejected().has(seed_value())
	status = "сид %d: %s%s" % [seed_value(), "проходима" if report.valid else ", ".join(report.errors),
			" — ОТБРАКОВАНА" if rejected else ""]
	notify_property_list_changed()


func _reject() -> void:
	var dir := DatasetGenerators.data_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(DatasetGenerators.REJECTED_FILE)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	file.seek_end()
	file.store_line("%d  # %s × %s, отбраковано при просмотре" % [seed_value(), Palette.room_types()[room_type], Palette.biomes()[biome]])
	file.close()
	_render()
