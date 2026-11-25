extends SceneTree
## Обучающая выборка CVAE (бланк задания: «создание комнат в TileMap, разметка по типам и биомам»; ОГР-03).
## Каждая комната создаётся процедурным генератором (DatasetGenerators), раскладывается на TileMapLayer
## тайлами палитры и метками, размечается типом и биомом (метаданные слоя), считывается обратно из TileMap
## и проверяется валидатором (ФТ-04): в выборку попадают только проходимые комнаты.
## Комнаты, отбракованные при просмотре (tools/dataset/dataset_preview.tscn), пропускаются.
## Результат: ml/data/levels.npz + levels_meta.json. Пополнение выборки не меняет игровой код (ФТ-11).
## Запуск: godot --headless --path game --script res://tools/build_dataset.gd [-- --per-class=750]

const DEFAULT_PER_CLASS := 750
## 3 (11.10.2026): мелочь биомов кучками, колонны на общей сетке, трещины «лесенкой», крупные тайники.
const GENERATOR_VERSION := 3


var _done := false


func _init() -> void:
	# Ошибка скрипта прерывает _init без quit(), и процесс висел бы вечно — сторож завершит его с кодом 1.
	process_frame.connect(func() -> void:
		if not _done:
			printerr("Сборка датасета прервана ошибкой скрипта")
			quit(1), CONNECT_ONE_SHOT)
	_build()
	_done = true


func _build() -> void:
	var per_class := DEFAULT_PER_CLASS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--per-class="):
			per_class = int(arg.trim_prefix("--per-class="))
	var out_dir := DatasetGenerators.data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rejected := DatasetGenerators.load_rejected()

	var ground := TileMapLayer.new()
	var markers := TileMapLayer.new()
	var validator := LevelValidator.new()
	var size := Palette.map_size()
	var tiles := PackedByteArray()
	var biomes := PackedByteArray()
	var types := PackedByteArray()
	var seeds := PackedInt64Array()
	var invalid := 0
	var skipped := 0
	var started := Time.get_ticks_msec()

	for room_type in Palette.room_types().size():
		for biome in Palette.biomes().size():
			var made := 0
			var seed_value := DatasetGenerators.class_seed(room_type, biome, 0)
			while made < per_class:
				seed_value += 1
				if rejected.has(seed_value):
					skipped += 1
					continue
				var level := DatasetGenerators.generate(room_type, biome, seed_value)
				var sample := through_tilemap(level, ground, markers)
				if sample.tiles != level.tiles:
					printerr("TileMap исказил комнату %d — проверьте TileSet" % seed_value)
					quit(1)
					return
				if not validator.validate(sample).valid:
					invalid += 1
					continue
				tiles.append_array(sample.tiles)
				biomes.append(sample.biome)
				types.append(sample.room_type)
				seeds.append(seed_value)
				made += 1
			print("  %-6s × %-10s: %d комнат" % [Palette.room_types()[room_type], Palette.biomes()[biome], made])
	ground.free()
	markers.free()

	var count := seeds.size()
	var npz := NpzWriter.new()
	npz.add("tiles", "|u1", [count, size, size], tiles)
	npz.add("biome", "|u1", [count], biomes)
	npz.add("room_type", "|u1", [count], types)
	npz.add("seed", "<i8", [count], seeds.to_byte_array())
	var npz_path := out_dir.path_join("levels.npz")
	if npz.save(npz_path) != OK:
		printerr("Не удалось записать ", npz_path)
		quit(1)
		return

	var frequency := {}
	for id in Palette.class_count():
		frequency[Palette.name_of(id)] = 0
	for id in tiles:
		frequency[Palette.name_of(id)] += 1
	for key: String in frequency:
		frequency[key] = snappedf(float(frequency[key]) / tiles.size(), 0.0001)
	var meta := {
		"generator_version": GENERATOR_VERSION,
		"palette_sha256": FileAccess.get_sha256(Palette.PATH),
		"map_size": size,
		"classes": Array(range(Palette.class_count()).map(func(id: int) -> String: return Palette.name_of(id))),
		"biomes": Array(Palette.biomes()),
		"room_types": Array(Palette.room_types()),
		"per_class": per_class,
		"count": count,
		"rejected_by_validator": invalid,
		"skipped_by_review": skipped,
		"tile_frequency": frequency,
		"built_at": Time.get_datetime_string_from_system(true),
	}
	var meta_file := FileAccess.open(out_dir.path_join("levels_meta.json"), FileAccess.WRITE)
	meta_file.store_string(JSON.stringify(meta, "\t", false))
	meta_file.close()

	print("Комнат: %d, отбраковано валидатором: %d, пропущено после просмотра: %d, %.1f с"
			% [count, invalid, skipped, (Time.get_ticks_msec() - started) / 1000.0])
	print("Частоты тайлов: ", frequency)
	print("Записано: ", npz_path)
	quit(0)


## Комната проходит через TileMap: раскладывается на слои, метки типа и биома пишутся в метаданные слоя,
## а образец для датасета считывается обратно из клеток TileMapLayer.
static func through_tilemap(level: LevelData, ground: TileMapLayer, markers: TileMapLayer) -> LevelData:
	LevelBuilder.build(level, ground, markers)
	ground.set_meta(&"room_type", level.room_type)
	ground.set_meta(&"biome", level.biome)
	var sample := LevelData.create_empty(level.size)
	sample.room_type = ground.get_meta(&"room_type")
	sample.biome = ground.get_meta(&"biome")
	sample.gen_seed = level.gen_seed
	for y in level.size:
		for x in level.size:
			var cell := Vector2i(x, y)
			var marker := markers.get_cell_atlas_coords(cell)
			sample.set_tile(cell, marker.x if marker.x >= 0 else ground.get_cell_atlas_coords(cell).x)
	return sample
