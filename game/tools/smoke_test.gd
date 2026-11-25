extends SceneTree
## Быстрая проверка контрактов каркаса без запуска игры.
## Запуск: godot --headless --path game --script res://tools/smoke_test.gd

var _failures := 0


func _init() -> void:
	_check(Palette.class_count() == 12, "в палитре 12 классов (ФТ-02: 8–15)")
	_check(Palette.map_size() in LevelData.ALLOWED_SIZES, "размер карты разрешён ОГР-05")

	var level := TestLevel.make()
	_check(level.is_valid(), "тестовая арена проходит проверку контракта")
	_check(level.find_cells(Palette.Tile.PLAYER_SPAWN).size() == 1, "ровно одна точка спавна игрока")
	_check(level.find_cells(Palette.Tile.EXIT).size() == 1, "ровно один выход")
	_check(level.find_cells(Palette.Tile.ENEMY_SPAWN).size() >= 1, "есть точка спавна врагов (ФТ-03)")
	_check(level.find_cells(Palette.Tile.CHEST).size() >= 1, "есть точка лута (ФТ-03)")

	var bytes := level.to_bytes()
	var copy := LevelData.from_bytes(bytes)
	_check(copy != null and copy.checksum() == level.checksum(), "LevelData переживает сериализацию (ФТ-15)")
	_check(bytes.size() < 4096, "пакет уровня меньше 4 КБ (%d байт)" % bytes.size())

	var broken := level.to_bytes()
	broken.resize(broken.size() / 2)
	_check(LevelData.from_bytes(broken) == null, "обрезанный пакет отклоняется")

	var foreign := TestLevel.make()
	foreign.tiles[0] = 200
	_check(LevelData.from_bytes(foreign.to_bytes()) == null, "тайл вне палитры отклоняется (НФТ-06)")

	var tileset := LevelBuilder.placeholder_tileset()
	_check(tileset.get_source(LevelBuilder.SOURCE_ID).get_tiles_count() == Palette.class_count(),
			"в заглушке TileSet по тайлу на класс")

	var art := TileMapLayer.new()
	LevelArt.build(level, art)
	var art_cells := art.get_used_cells()
	var side := level.size * LevelArt.blocks()
	_check(art_cells.size() == side * side, "графический слой покрывает карту блоками 3×3 (%d тайлов)" % art_cells.size())
	_check(art_cells.all(func(c: Vector2i) -> bool: return art.get_cell_tile_data(c) != null),
			"все тайлы графического слоя есть в атласе")
	art.free()

	# Листы героев (шаг 11.1): раскладка рядом с PNG, все анимации на месте, размер совпадает с сеткой.
	for file in DirAccess.get_files_at("res://data/heroes"):
		if not file.ends_with(".tres"):
			continue
		var hero := load("res://data/heroes/" + file) as HeroData
		var layout := SheetLayout.of(hero.sprite_sheet) if hero != null else null
		# Шаг 11.19: ещё каст, вздрагивание и смерть; кадры каждой анимации помещаются в строку листа.
		var ok := layout != null and [&"idle", &"walk", &"attack", &"attack_walk", &"cast", &"hurt", &"death"].all(
				func(anim: StringName) -> bool: return layout.count(anim) > 0 and layout.count(anim) <= layout.columns)
		ok = ok and hero.sprite_sheet.get_size() == Vector2(layout.frame_size * Vector2i(layout.columns, layout.rows))
		_check(ok, "лист героя %s: покой, ходьба, удар, удар на ходу, каст, вздрагивание, смерть; сетка %s" % [
				file.get_basename(), "%d×%d" % [layout.columns, layout.rows] if layout != null else "—"])
		_check(hero != null and layout != null
				and hero.portrait_region() == layout.region(layout.frame(&"idle", 0, 0, layout.dir_index("s"))),
				"портрет %s — первый кадр покоя лицом к камере" % file.get_basename())
		# 8 направлений (шаг 11.11): 5 блоков листа, влево — отражение.
		_check(layout != null and layout.directions == PackedStringArray(["e", "ne", "n", "se", "s"])
				and layout.rows == layout.dir_rows * layout.directions.size(),
				"лист героя %s: 5 направлений по %d строк" % [file.get_basename(), layout.dir_rows if layout != null else 0])
		# Листы 96 px (шаг 11.3): в мире кадр занимает столько же, сколько прежний 32 px; опора — по середине кадра.
		_check(layout != null and is_equal_approx(layout.frame_size.x * layout.scale, 32.0)
				and is_equal_approx(layout.anchor.x, layout.frame_size.x / 2.0),
				"лист героя %s: кадр в мире 32 px, опора по середине" % file.get_basename())

	# Атлас врагов (шаг 11.2): лист у каждого врага, все анимации, кадры внутри текстуры.
	var skeleton_sheet := EnemyArt.sheet(&"skeleton")  # атлас грузится при первом обращении
	_check(EnemyArt.texture != null and skeleton_sheet != null, "атлас врагов загружен")
	var atlas_size := EnemyArt.texture.get_size() if EnemyArt.texture != null else Vector2.ZERO
	var missing := PackedStringArray()
	for file in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var info := load("res://data/enemies/" + file) as EnemyData
		var sheet := EnemyArt.sheet(info.id) if info != null and EnemyArt.has_sheet(info.id) else null
		var ok := sheet != null and [&"idle", &"walk", &"attack", &"death"].all(
				func(anim: StringName) -> bool: return sheet.count(anim) > 0)
		ok = ok and Rect2(Vector2.ZERO, atlas_size).encloses(sheet.region(sheet.columns * sheet.rows - 1))
		if not ok:
			missing.append(file.get_basename())
	_check(missing.is_empty(), "у каждого врага лист в атласе: покой, ходьба, удар, смерть %s" % ", ".join(missing))

	# Шаг 11.16: шрифт заголовков темы — «Vault Grimoire» с достроенной кириллицей (НФТ-08: русский по умолчанию).
	var theme: Theme = load("res://ui/theme/main_theme.tres")
	var header_font := theme.get_font(&"font", &"HeaderLabel") as FontVariation
	var base_font := header_font.base_font if header_font != null else null
	var letters := "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюяAZaz09"
	_check(base_font != null and Array(letters.split("")).all(func(ch: String) -> bool: return base_font.has_char(ch.unicode_at(0)))
			and theme.get_font(&"font", &"Button") == header_font,
			"шрифт заголовков и кнопок — с кириллицей и латиницей")

	print("Провалено проверок: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  OK   ", description)
	else:
		_failures += 1
		printerr("  FAIL ", description)
