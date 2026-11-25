extends SceneTree
## Проверки генерации уровня: валидатор (ФТ-04), декодер (ФТ-02, ФТ-03), цикл попыток (ФТ-05),
## журнал и воспроизводимость (ФТ-17), работа из фонового потока (НФТ-05).
## Цикл генерации проверяется на модели-заготовке с интерфейсом декодера CVAE (tools/make_spike_model.gd).
## Запуск: godot --headless --path game --script res://tools/levelgen_test.gd

const SPIKE_MODEL := "res://models/spike/levelgen_spike.onnx"
const T = Palette.Tile

var _failures := 0


func _init() -> void:
	# Ошибка скрипта прерывает только текущую функцию, и тест мог бы «пройти» без половины проверок.
	# Поэтому каждый раздел обязан дойти до конца и вернуть true.
	for section: Array in [
		["Валидатор:", _check_validator],
		["Декодер:", _check_decoder],
		["Генератор (модель-заготовка):", _check_generator],
	]:
		print(section[0])
		_check(section[1].call() == true, "раздел выполнен до конца")
	print("Провалено проверок: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_validator() -> bool:
	var validator := LevelValidator.new()
	var arena := TestLevel.make()
	var report := validator.validate(arena)
	_check(report.valid, "тестовая арена проходит проверку (%s)" % ", ".join(report.errors))
	_check(report.spawn_exit_distance >= LevelValidator.DEFAULT_MIN_SPAWN_EXIT_DISTANCE,
			"расстояние спавн → выход %d клеток" % report.spawn_exit_distance)

	var level := TestLevel.make()
	level.set_tile(level.find_first(T.PLAYER_SPAWN), T.FLOOR)
	_expect_error(validator, level, "player_spawn_count", "нет спавна игрока")

	level = TestLevel.make()
	level.set_tile(Vector2i(3, 10), T.EXIT)
	_expect_error(validator, level, "exit_count", "два выхода")

	level = TestLevel.make()
	_wall_around(level, level.find_first(T.EXIT))
	_expect_error(validator, level, "exit_unreachable", "выход замурован")

	level = TestLevel.make()
	_wall_around(level, level.find_first(T.CHEST))
	_expect_error(validator, level, "chest_unreachable", "сундук замурован")

	level = TestLevel.make()
	_wall_around(level, level.find_first(T.FOUNTAIN))
	_expect_error(validator, level, "fountain_unreachable", "фонтан замурован")

	level = TestLevel.make()
	for cell in level.find_cells(T.ENEMY_SPAWN):
		_wall_around(level, cell)
	_expect_error(validator, level, "enemy_spawn_unreachable", "все точки врагов замурованы")

	level = TestLevel.make()
	var spawn := level.find_first(T.PLAYER_SPAWN)
	level.set_tile(level.find_first(T.EXIT), T.FLOOR)
	level.set_tile(spawn + Vector2i(2, 0), T.EXIT)
	_expect_error(validator, level, "exit_too_close", "выход в 2 клетках от спавна")

	level = TestLevel.make()
	level.set_tile(level.find_first(T.CHEST), T.FLOOR)
	_expect_error(validator, level, "chest_count", "нет точки лута (ФТ-03)")

	level = TestLevel.make()
	for cell in level.find_cells(T.ENEMY_SPAWN):
		level.set_tile(cell, T.FLOOR)
	_expect_error(validator, level, "enemy_spawn_count", "нет точки врагов (ФТ-03)")

	level = TestLevel.make()
	level.set_tile(Vector2i(4, 4), T.FOUNTAIN)
	_expect_error(validator, level, "fountain_count", "два фонтана при лимите 1")

	level = LevelData.create_empty(32, T.WALL)
	for x in 20:
		level.set_tile(Vector2i(x, 5), T.FLOOR)
	level.set_tile(Vector2i(0, 5), T.PLAYER_SPAWN)
	_expect_error(validator, level, "too_few_passable", "почти вся карта — стены")

	level = TestLevel.make()
	_fill_rect(level, Rect2i(1, 1, 30, 30), T.FLOOR)
	_fill_rect(level, Rect2i(1, 4, 30, 1), T.WALL)  # отрезанная от спавна большая часть карты
	level.set_tile(Vector2i(2, 2), T.PLAYER_SPAWN)
	_expect_error(validator, level, "too_few_reachable", "игровая зона — узкая полоса, остальное отрезано")
	var distances := LevelValidator.bfs(level, Vector2i(0, 5))
	_check(distances[level.index_of(Vector2i(19, 5))] == 19 and distances[level.index_of(Vector2i(0, 6))] == -1,
			"BFS: расстояние по коридору 19, стена недостижима")
	return true


func _check_decoder() -> bool:
	var cells := 32 * 32
	var probs := PackedFloat32Array()
	probs.resize(Palette.class_count() * cells)
	var p := func(id: int, x: int, y: int, value: float) -> void: probs[id * cells + y * 32 + x] = value
	for y in 32:
		for x in 32:
			var edge := x == 0 or y == 0 or x == 31 or y == 31
			p.call(T.FLOOR, x, y, 0.5)
			p.call(T.WALL, x, y, 0.9 if edge else 0.1)
	p.call(T.WALL, 10, 10, 0.9)
	for c: Vector2i in [Vector2i(24, 25), Vector2i(26, 25), Vector2i(25, 24), Vector2i(25, 26),
			Vector2i(24, 24), Vector2i(26, 26), Vector2i(24, 26), Vector2i(26, 24)]:
		p.call(T.WALL, c.x, c.y, 0.9)  # замкнутый карман: клетка (25, 25) — недостижимый пол
	p.call(T.PLAYER_SPAWN, 5, 5, 0.4)
	p.call(T.EXIT, 7, 5, 0.9)  # самый вероятный, но в 2 шагах от спавна
	p.call(T.EXIT, 25, 5, 0.5)
	for e: Array in [[20, 20, 0.8], [21, 20, 0.79], [15, 20, 0.7], [15, 10, 0.6], [25, 25, 0.15]]:
		p.call(T.ENEMY_SPAWN, e[0], e[1], e[2])  # Σ = 3.04 → 3 точки
	p.call(T.CHEST, 10, 10, 0.9)  # на стене
	p.call(T.CHEST, 12, 12, 0.05)  # Σ = 0.95 → 1 сундук
	p.call(T.FOUNTAIN, 3, 20, 0.2)  # Σ = 0.2 → 0 фонтанов
	for s: Array in [[8, 25, 0.95], [4, 12, 0.9], [18, 4, 0.9], [28, 10, 0.9], [12, 28, 0.9]]:
		p.call(T.STATUE, s[0], s[1], s[2])  # Σ = 4.55, но статуя одна
	for o: Array in [[28, 28, 0.8], [28, 15, 0.7], [5, 28, 0.6]]:
		p.call(T.OBELISK, o[0], o[1], o[2])  # Σ = 2.1 → 2 обелиска

	var level := LevelDecoder.decode(probs, 32, 1, 2, 99, "hash")
	var at := func(x: int, y: int) -> int: return level.get_tile(Vector2i(x, y))
	_check(at.call(0, 0) == T.WALL and at.call(10, 10) == T.WALL and at.call(25, 25) == T.FLOOR,
			"рельеф — argmax по каналам рельефа")
	_check(_only(level, T.PLAYER_SPAWN, Vector2i(5, 5)), "спавн игрока — пик канала")
	_check(_only(level, T.EXIT, Vector2i(25, 5)),
			"выход — пик среди клеток не ближе 12 шагов от спавна")
	var enemies := level.find_cells(T.ENEMY_SPAWN)
	_check(enemies.size() == 3 and Vector2i(20, 20) in enemies and Vector2i(15, 20) in enemies
			and Vector2i(15, 10) in enemies, "точек врагов 3 = round(Σ p); соседняя (21, 20) и карман пропущены")
	_check(_only(level, T.CHEST, Vector2i(12, 12)),
			"сундук не на стене; Σ p < 1, но минимум 1 по ФТ-03")
	_check(level.find_cells(T.FOUNTAIN).is_empty(), "фонтана нет: Σ p = 0.2 → 0")
	_check(_only(level, T.STATUE, Vector2i(8, 25)), "статуя одна — лимит валидатора")
	_check(level.find_cells(T.OBELISK).size() == 2 and Vector2i(5, 28) not in level.find_cells(T.OBELISK),
			"обелисков 2 = round(Σ p), самые вероятные")
	_check(level.get_spawn_weight(Vector2i(20, 20)) == 255 and level.get_spawn_weight(Vector2i(15, 20)) == 223
			and level.get_spawn_weight(Vector2i(0, 0)) == 0, "веса спавна врагов нормированы на максимум: 255 / 223 / 0")
	_check(level.biome == 1 and level.room_type == 2 and level.gen_seed == 99 and level.model_hash == "hash",
			"метаданные уровня заполнены")
	_check(level.is_valid(), "результат декодера проходит контракт LevelData")
	return true


func _check_generator() -> bool:
	var missing := LevelGenerator.new("res://models/spike/missing.onnx")
	_check(not missing.is_ready() and missing.get_error() != "", "нет файла модели → генератор не готов, причина известна")
	_check(missing.generate(LevelGenerator.Request.new()).level == null, "генерация без модели не падает")

	var gen := LevelGenerator.new(SPIKE_MODEL)
	_check(gen.is_ready(), "генератор принял модель-заготовку (%s)" % gen.get_error())
	if not gen.is_ready():
		return true
	_check(gen.model_hash == FileAccess.get_sha256(SPIKE_MODEL), "хэш модели совпадает с SHA-256 файла")

	var cond := LevelGenerator.make_cond(1, 2, 0.3, 3)
	_check(is_equal_approx(cond[1], 0.7) and is_equal_approx(cond[3], 0.3) and cond[4 + 2] == 1.0,
			"cond: затопленный склеп 0.7 + бездна 0.3, тип комнаты 2")
	var deep := LevelGenerator.make_request(7, 5, 1, 3)
	var lair := LevelGenerator.make_request(7, 3, 3, 3)
	_check(is_equal_approx(deep.rot, 0.6) and deep.rot_biome == 3 and lair.rot == 0.0,
			"«Бесконечная гниль»: с глубиной условие уходит к биому логова (потолок 0.6), у самого логова — нет")

	var accepted: LevelGenerator.Result
	var accepted_request: LevelGenerator.Request
	var all_records: Array[Dictionary] = []
	var structure_ok := true
	for run_seed in range(1, 41):
		var request := LevelGenerator.make_request(run_seed, 0, run_seed % 4)
		var result := gen.generate(request)
		all_records.append_array(result.attempts)
		structure_ok = structure_ok and _attempts_well_formed(result)
		if accepted == null and result.level != null:
			accepted = result
			accepted_request = request
	_check(structure_ok, "в каждой генерации 1–5 попыток, исходы rejected… → accepted/exhausted")
	var fields_ok := true
	for record in all_records:
		for field in LevelGenerator.LOG_FIELDS:
			fields_ok = fields_ok and record.has(field)
	_check(fields_ok, "у всех %d записей есть поля журнала ФТ-17" % all_records.size())

	_check(accepted != null, "хотя бы одна из 40 генераций принята валидатором")
	if accepted != null:
		var level := accepted.level
		var report := gen.validator.validate(level)
		_check(report.valid and level.is_valid(), "принятая карта валидна и проходит контракт LevelData")
		_check(level.checksum() == accepted.attempts[-1]["checksum"], "контрольная сумма в журнале = сумме карты")
		var spawns_reachable := true
		for i in level.spawn_weights.size():
			if level.spawn_weights[i] > 0 and report.distances[i] < 0:
				spawns_reachable = false
		_check(spawns_reachable, "враги появляются только в достижимых клетках")

		var again := gen.generate(accepted_request)
		_check(again.level != null and again.level.checksum() == level.checksum()
				and again.attempts.size() == accepted.attempts.size(), "тот же запрос → та же карта (код забега)")

		var box := {}
		var task := WorkerThreadPool.add_task(func() -> void: box["result"] = gen.generate(accepted_request))
		WorkerThreadPool.wait_for_task_completion(task)
		_check(box["result"].level != null and box["result"].level.checksum() == level.checksum(),
				"генерация из WorkerThreadPool даёт ту же карту (НФТ-05)")

	var reproduced := 0
	for record in all_records:
		if not record.has("checksum"):
			continue
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(_json_ready(record), "", false, true))
		var copy := gen.reproduce(parsed)
		if copy != null and copy.checksum() == record["checksum"]:
			reproduced += 1
	_check(reproduced == all_records.size(), "все %d/%d попыток воспроизводятся по записи журнала после JSON (ФТ-17)"
			% [reproduced, all_records.size()])
	var foreign := all_records[0].duplicate()
	foreign["model_hash"] = "other-model"
	_check(gen.reproduce(foreign) == null, "запись от другой версии модели не воспроизводится")

	var strict := LevelGenerator.new(SPIKE_MODEL)
	strict.validator.min_passable_ratio = 1.01
	var exhausted := strict.generate(LevelGenerator.make_request(1, 0, 0))
	_check(exhausted.level == null and exhausted.attempts.size() == LevelGenerator.MAX_ATTEMPTS
			and exhausted.attempts[-1]["outcome"] == "exhausted" and exhausted.error != "",
			"все 5 попыток отбракованы → нет карты, исход exhausted, причина (ФТ-05)")
	return true


func _attempts_well_formed(result: LevelGenerator.Result) -> bool:
	var count := result.attempts.size()
	if count < 1 or count > LevelGenerator.MAX_ATTEMPTS:
		return false
	for i in count:
		var record := result.attempts[i]
		if record["attempt"] != i + 1:
			return false
		var last := i == count - 1
		var expected := "rejected"
		if last:
			expected = "accepted" if result.level != null else "exhausted"
		if record["outcome"] != expected or record["valid"] != (last and result.level != null):
			return false
	return true


## Так же, как GenLog: packed-массивы → обычные массивы.
func _json_ready(record: Dictionary) -> Dictionary:
	var copy := {}
	for key: String in record:
		var value: Variant = record[key]
		copy[key] = Array(value) if value is PackedFloat32Array else value
	return copy


## На карте ровно одна метка id, и она в клетке cell.
func _only(level: LevelData, id: int, cell: Vector2i) -> bool:
	var found := level.find_cells(id)
	return found.size() == 1 and found[0] == cell


func _fill_rect(level: LevelData, rect: Rect2i, id: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			level.set_tile(Vector2i(x, y), id)


func _wall_around(level: LevelData, cell: Vector2i) -> void:
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if level.in_bounds(cell + offset):
			level.set_tile(cell + offset, T.WALL)


func _expect_error(validator: LevelValidator, level: LevelData, code: String, description: String) -> void:
	var report := validator.validate(level)
	_check(not report.valid and code in report.errors, "%s → %s" % [description, code])


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  OK   ", description)
	else:
		_failures += 1
		printerr("  FAIL ", description)
