@tool
class_name DatasetGenerators
extends RefCounted
## ОГР-03: процедурные генераторы комнат для обучающей выборки CVAE — BSP, клеточные автоматы,
## лабиринт залов, арена. Используются ТОЛЬКО для датасета: в игре локации создаёт модель (ОГР-02).
## Тип комнаты задаёт алгоритм, биом — устройство опасных клеток и декор (шаг 9), поэтому обе метки
## несут информацию и модель учится их различать. Раньше опасные клетки стояли случайными пятнами,
## и модель их почти не рисовала (DESIGN 2.3); теперь у каждого биома своя крупная структура:
##   Проклятый лес — болотные топи и рощицы на полянах;
##   Затопленный склеп — прямые каналы воды через залы с мостками;
##   Пылающий собор — трещины лавы «лесенкой» и ряды колонн в больших залах;
##   Бездна — округлые провалы посреди залов.
## Тайник: в части комнат — закрытый «карман» пола за стеной в одну клетку (в игре — треснувшая стена
## и бонусная комната, шаг 9).

enum RoomType { ROOMS, CAVES, HALLS, ARENA }  # порядок = room_types в palette.json
enum Biome { FOREST, FLOODED_CRYPT, CATHEDRAL, ABYSS }  # порядок = biomes в palette.json

## hazard — устройство опасных клеток, share — их доля от площади пола (цель, не точное значение);
## rubble — доля проходимого декора (кучками); groves — сколько рощиц (стена кучкой 3–6 клеток);
## pillars — шаг сетки колонн (0 — нет).
## Версия 3 (11.10.2026): мелочь собрана в крупные формы — одиночные деревья, мусор по клетке, сетка колонн
## со случайным сдвигом и рваные трещины были шумом, который CVAE не может восстановить (НФТ-10 83 % < 85 %).
const BIOME_STYLE := {
	Biome.FOREST: {"hazard": "bog", "share": 0.07, "rubble": 0.08, "groves": 3, "pillars": 0},
	Biome.FLOODED_CRYPT: {"hazard": "canals", "share": 0.09, "rubble": 0.04, "groves": 0, "pillars": 0},
	Biome.CATHEDRAL: {"hazard": "fissures", "share": 0.05, "rubble": 0.04, "groves": 0, "pillars": 4},
	Biome.ABYSS: {"hazard": "chasms", "share": 0.14, "rubble": 0.05, "groves": 0, "pillars": 0},
}
## Доля комнат с тайником и размер его стороны в клетках (крупный карман модель сохраняет чаще).
const SECRET_CHANCE := 0.5
const SECRET_SIDE := Vector2i(3, 5)
const SECRET_MIN_AREA := 9
## Колонны собора стоят на клетках (PILLAR_PHASE + k·шаг) — сетка общая для всех карт.
const PILLAR_PHASE := 2
const MIN_EXIT_DISTANCE := 14
const MIN_ENEMY_DISTANCE := 8
const MIN_CHEST_DISTANCE := 5
const MARKER_SPACING := 3
## Порог валидатора — 35 % (ФТ-04); генератор датасета держит запас, чтобы не тратить комнаты впустую.
const MIN_PASSABLE_AFTER_HAZARD := 0.40

const T = Palette.Tile
## Диапазоны сидов разных классов (тип × биом) не пересекаются: сид = номер класса × SEED_STRIDE + номер комнаты.
const SEED_STRIDE := 10_000_000
const REJECTED_FILE := "rejected.txt"


static func class_seed(room_type: int, biome: int, sample: int) -> int:
	return (room_type * Palette.biomes().size() + biome) * SEED_STRIDE + sample


## Папка датасета ml/data рядом с проектом игры.
static func data_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../ml/data").simplify_path()


## Сиды комнат, отбракованных при просмотре (dataset_preview.tscn): по одному в строке, комментарии после #.
static func load_rejected() -> Dictionary:
	var result := {}
	var path := data_dir().path_join(REJECTED_FILE)
	if not FileAccess.file_exists(path):
		return result
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var text := line.get_slice("#", 0).strip_edges()
		if text.is_valid_int():
			result[int(text)] = true
	return result


static func generate(room_type: int, biome: int, seed_value: int) -> LevelData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var level := LevelData.create_empty(Palette.map_size(), T.WALL)
	level.biome = biome
	level.room_type = room_type
	level.gen_seed = seed_value
	level.model_hash = "dataset"
	match room_type:
		RoomType.ROOMS:
			_bsp_node(level, rng, Rect2i(1, 1, level.size - 2, level.size - 2), 4)
		RoomType.CAVES:
			_caves(level, rng)
		RoomType.HALLS:
			_halls(level, rng)
		RoomType.ARENA:
			_arena(level, rng)
	_keep_largest_region(level)
	var style: Dictionary = BIOME_STYLE[biome]
	_add_hazards(level, rng, style["hazard"], style["share"])
	_add_pillars(level, style["pillars"])
	_add_groves(level, rng, style["groves"])
	_add_rubble(level, rng, style["rubble"])
	_place_markers(level, rng)
	if rng.randf() < SECRET_CHANCE:
		add_secret(level, rng)
	_mark_void(level)
	return level


# --- Планировка -------------------------------------------------------------------------------

@warning_ignore("integer_division")
## BSP: делим прямоугольник пополам до листьев, в каждом листе комната, соседние поддеревья
## соединяются коридором. Возвращает центры комнат поддерева.
static func _bsp_node(level: LevelData, rng: RandomNumberGenerator, rect: Rect2i, depth: int) -> Array[Vector2i]:
	var can_split_x := rect.size.x >= 12
	var can_split_y := rect.size.y >= 12
	if depth == 0 or not (can_split_x or can_split_y) or (depth <= 2 and rng.randf() < 0.25):
		var w := rng.randi_range(maxi(3, rect.size.x / 2), maxi(3, rect.size.x - 2))
		var h := rng.randi_range(maxi(3, rect.size.y / 2), maxi(3, rect.size.y - 2))
		var room := Rect2i(rect.position.x + rng.randi_range(1, maxi(1, rect.size.x - w - 1)),
				rect.position.y + rng.randi_range(1, maxi(1, rect.size.y - h - 1)), w, h).intersection(rect)
		_fill(level, room, T.FLOOR)
		return [room.get_center()]
	var vertical := can_split_x and (not can_split_y or rect.size.x > rect.size.y or
			(rect.size.x == rect.size.y and rng.randf() < 0.5))
	var a: Rect2i
	var b: Rect2i
	if vertical:
		var cut := rng.randi_range(6, rect.size.x - 6)
		a = Rect2i(rect.position, Vector2i(cut, rect.size.y))
		b = Rect2i(rect.position + Vector2i(cut, 0), Vector2i(rect.size.x - cut, rect.size.y))
	else:
		var cut := rng.randi_range(6, rect.size.y - 6)
		a = Rect2i(rect.position, Vector2i(rect.size.x, cut))
		b = Rect2i(rect.position + Vector2i(0, cut), Vector2i(rect.size.x, rect.size.y - cut))
	var left := _bsp_node(level, rng, a, depth - 1)
	var right := _bsp_node(level, rng, b, depth - 1)
	_corridor(level, rng, left[rng.randi_range(0, left.size() - 1)], right[rng.randi_range(0, right.size() - 1)])
	left.append_array(right)
	return left


## Г-образный коридор шириной 2–3 клетки: узкие коридоры модель воспроизводит с разрывами,
## а при клетке 96 px ширина 2–3 (192–288 px) как раз для орды врагов.
static func _corridor(level: LevelData, rng: RandomNumberGenerator, from: Vector2i, to: Vector2i) -> void:
	var width := rng.randi_range(2, 3)
	var corner := Vector2i(to.x, from.y) if rng.randf() < 0.5 else Vector2i(from.x, to.y)
	for segment: Array in [[from, corner], [corner, to]]:
		var p: Vector2i = segment[0]
		var q: Vector2i = segment[1]
		var r := Rect2i(Vector2i(mini(p.x, q.x), mini(p.y, q.y)), (p - q).abs() + Vector2i(width, width))
		_fill(level, r.intersection(Rect2i(1, 1, level.size - 2, level.size - 2)), T.FLOOR)


## Пещеры: случайное заполнение и 5 шагов клеточного автомата «стена, если вокруг ≥ 5 стен».
static func _caves(level: LevelData, rng: RandomNumberGenerator) -> void:
	var fill := rng.randf_range(0.40, 0.47)
	for y in range(1, level.size - 1):
		for x in range(1, level.size - 1):
			level.set_tile(Vector2i(x, y), T.WALL if rng.randf() < fill else T.FLOOR)
	for step in 5:
		var next := level.tiles.duplicate()
		for y in range(1, level.size - 1):
			for x in range(1, level.size - 1):
				var walls := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if level.get_tile(Vector2i(x + dx, y + dy)) == T.WALL:
							walls += 1
				next[level.index_of(Vector2i(x, y))] = T.WALL if walls >= 5 else T.FLOOR
		level.tiles = next


## Залы: лабиринт «рекурсивный откат» на крупной сетке 6×6 с коридорами шириной 3,
## плюс несколько разрушенных стен (петли) и объединённых больших залов.
static func _halls(level: LevelData, rng: RandomNumberGenerator) -> void:
	const CELLS := 6
	const PITCH := 5
	const WIDTH := 3
	var visited := {}
	var stack: Array[Vector2i] = [Vector2i(rng.randi_range(0, CELLS - 1), rng.randi_range(0, CELLS - 1))]
	visited[stack[0]] = true
	_fill(level, _hall_rect(stack[0], PITCH, WIDTH), T.FLOOR)
	while not stack.is_empty():
		var cell: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := cell + d
			if n.x >= 0 and n.y >= 0 and n.x < CELLS and n.y < CELLS and not visited.has(n):
				options.append(n)
		if options.is_empty():
			stack.pop_back()
			continue
		var next := options[rng.randi_range(0, options.size() - 1)]
		visited[next] = true
		_fill(level, _hall_rect(cell, PITCH, WIDTH).merge(_hall_rect(next, PITCH, WIDTH)), T.FLOOR)
		stack.append(next)
	for i in rng.randi_range(2, 5):  # петли
		var cell := Vector2i(rng.randi_range(0, CELLS - 2), rng.randi_range(0, CELLS - 1))
		_fill(level, _hall_rect(cell, PITCH, WIDTH).merge(_hall_rect(cell + Vector2i.RIGHT, PITCH, WIDTH)), T.FLOOR)
	for i in rng.randi_range(1, 3):  # большие залы 2×2 клетки
		var cell := Vector2i(rng.randi_range(0, CELLS - 2), rng.randi_range(0, CELLS - 2))
		_fill(level, _hall_rect(cell, PITCH, WIDTH).merge(_hall_rect(cell + Vector2i.ONE, PITCH, WIDTH)), T.FLOOR)


static func _hall_rect(cell: Vector2i, pitch: int, width: int) -> Rect2i:
	return Rect2i(Vector2i(1, 1) + cell * pitch + Vector2i.ONE, Vector2i(width, width))


## Арена: открытое поле разной формы с крупными постройками внутри — простор для орды врагов.
## Крупные черты (форма поля, кольцо стен, сетка колонн) модель способна выучить, поэтому арены
## получаются разными; одни только мелкие случайные колонны она усреднила бы в пустое поле.
@warning_ignore("integer_division")
static func _arena(level: LevelData, rng: RandomNumberGenerator) -> void:
	var s := level.size
	var center := Vector2i(s / 2, s / 2)
	var shape := rng.randi_range(0, 3)
	var border := rng.randi_range(1, 3)
	var cut := rng.randi_range(5, 9)
	var band := rng.randi_range(12, 18)
	var radius := Vector2(rng.randf_range(11.0, 14.5), rng.randf_range(11.0, 14.5))
	for y in range(1, s - 1):
		for x in range(1, s - 1):
			var in_box := x >= border and y >= border and x < s - border and y < s - border
			var inside := in_box
			match shape:
				1:  # восьмиугольник
					inside = in_box and mini(x - border, s - 1 - border - x) + mini(y - border, s - 1 - border - y) >= cut
				2:  # крест
					inside = in_box and (absi(x - center.x) <= band / 2 or absi(y - center.y) <= band / 2)
				3:  # эллипс
					inside = pow((x - center.x) / radius.x, 2) + pow((y - center.y) / radius.y, 2) <= 1.0
			if inside:
				level.set_tile(Vector2i(x, y), T.FLOOR)

	var features := [0, 1, 2, 3]
	for i in range(features.size() - 1, 0, -1):  # перемешивание Фишера — Йетса тем же rng
		var j := rng.randi_range(0, i)
		var tmp: int = features[i]
		features[i] = features[j]
		features[j] = tmp
	for f: int in features.slice(0, rng.randi_range(1, 2)):
		match f:
			0:  # центральный блок
				var w := rng.randi_range(3, 7)
				var h := rng.randi_range(3, 7)
				_fill(level, Rect2i(center.x - w / 2, center.y - h / 2, w, h), T.WALL)
			1:  # кольцо стен с воротами шириной 3 посередине каждой стороны
				var r := rng.randi_range(5, 8)
				for k in range(-r, r + 1):
					if absi(k) > 1:
						for p: Vector2i in [Vector2i(k, -r), Vector2i(k, r), Vector2i(-r, k), Vector2i(r, k)]:
							level.set_tile(center + p, T.WALL)
			2:  # уголки стен по четвертям
				var d := rng.randi_range(5, 9)
				var length := rng.randi_range(3, 6)
				for sx in [-1, 1]:
					for sy in [-1, 1]:
						var corner := center + Vector2i(sx * d, sy * d)
						_fill(level, Rect2i(corner.x if sx < 0 else corner.x - length + 1, corner.y, length, 1), T.WALL)
						_fill(level, Rect2i(corner.x, corner.y if sy < 0 else corner.y - length + 1, 1, length), T.WALL)
			3:  # регулярная сетка колонн
				var step := rng.randi_range(4, 6)
				var pillar := rng.randi_range(1, 2)
				var offset := rng.randi_range(2, step)
				for y in range(offset, s - 2, step):
					for x in range(offset, s - 2, step):
						if level.get_tile(Vector2i(x, y)) == T.FLOOR:
							_fill(level, Rect2i(x, y, pillar, pillar), T.WALL)
	for i in rng.randi_range(0, 4):
		var size := rng.randi_range(1, 2)
		_fill(level, Rect2i(rng.randi_range(3, s - 5), rng.randi_range(3, s - 5), size, size), T.WALL)


# --- Стиль биома -------------------------------------------------------------------------------

## Опасные клетки по устройству биома, пока их доля не дойдёт до share площади пола. Каждая правка, которая
## разрывает проходимую область или оставляет проходимых клеток меньше MIN_PASSABLE_AFTER_HAZARD, откатывается.
static func _add_hazards(level: LevelData, rng: RandomNumberGenerator, kind: String, share: float) -> void:
	var target := int(share * level.find_cells(T.FLOOR).size())
	var placed := 0
	var tries := 0
	while placed < target and tries < 40:
		tries += 1
		var cells: Array[Vector2i] = []
		match kind:
			"bog":
				cells = _blob(level, rng, rng.randi_range(10, 24), 0.6)
			"canals":
				cells = _canal(level, rng)
			"fissures":
				cells = _fissure(level, rng)
			"chasms":
				cells = _blob(level, rng, rng.randi_range(10, 30), 0.85)
		placed += _try_set(level, cells, T.HAZARD)


## Записать id в клетки пола, если карта останется связной и достаточно проходимой; сколько записано.
static func _try_set(level: LevelData, cells: Array[Vector2i], id: int) -> int:
	if cells.is_empty():
		return 0
	var before := level.tiles.duplicate()
	var floor_count := level.find_cells(T.FLOOR).size()
	var changed := 0
	for c in cells:
		if level.get_tile(c) == T.FLOOR:
			level.set_tile(c, id)
			changed += 1
	if floor_count - changed < int(MIN_PASSABLE_AFTER_HAZARD * level.tiles.size()) or _region_count(level) > 1:
		level.tiles = before
		return 0
	return changed


## Пятно, растущее от случайной клетки пола: roundness 0 — рваное (топь), 1 — округлое (провал): новая клетка
## чаще берётся там, где у неё больше соседей из пятна.
static func _blob(level: LevelData, rng: RandomNumberGenerator, size: int, roundness: float) -> Array[Vector2i]:
	var floor_cells := level.find_cells(T.FLOOR)
	if floor_cells.is_empty():
		return []
	var start := floor_cells[rng.randi_range(0, floor_cells.size() - 1)]
	var cells: Array[Vector2i] = [start]
	var inside := {start: true}
	var guard := 0
	while cells.size() < size and guard < size * 20:
		guard += 1
		var c := cells[rng.randi_range(0, cells.size() - 1)]
		var n: Vector2i = c + [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN][rng.randi_range(0, 3)]
		if inside.has(n) or not level.in_bounds(n) or level.get_tile(n) != T.FLOOR:
			continue
		var around := 0
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if inside.has(n + d):
				around += 1
		if around < 2 and rng.randf() < roundness:
			continue
		inside[n] = true
		cells.append(n)
	return cells


## Канал: прямая полоса шириной 1–2 вдоль строки или столбца через пол, с мостками шириной 2 через каждые 4–7 клеток.
static func _canal(level: LevelData, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var horizontal := rng.randf() < 0.5
	var width := rng.randi_range(1, 2)
	var line := rng.randi_range(3, level.size - 4 - width)
	var cells: Array[Vector2i] = []
	var run := 0
	var bridge_at := rng.randi_range(4, 7)
	for k in range(1, level.size - 1):
		var cross: Array[Vector2i] = []
		for w in width:
			cross.append(Vector2i(k, line + w) if horizontal else Vector2i(line + w, k))
		var open := cross.all(func(c: Vector2i) -> bool: return level.get_tile(c) == T.FLOOR)
		if not open:
			run = 0
			continue
		run += 1
		if run >= bridge_at and run < bridge_at + 2:
			if run == bridge_at + 1:
				run = 0
				bridge_at = rng.randi_range(4, 7)
			continue  # мосток
		cells.append_array(cross)
	if cells.size() < 6:
		cells.clear()
	return cells


## Трещина: ровная «лесенка» шириной 2 по диагонали через пол — шаг вбок, шаг вниз (форма предсказуема,
## случайны только начало, направление и длина).
static func _fissure(level: LevelData, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var floor_cells := level.find_cells(T.FLOOR)
	if floor_cells.is_empty():
		return []
	var c := floor_cells[rng.randi_range(0, floor_cells.size() - 1)]
	var dir := Vector2i([-1, 1][rng.randi_range(0, 1)], [-1, 1][rng.randi_range(0, 1)])
	var cells: Array[Vector2i] = []
	for step in rng.randi_range(6, 14):
		if not level.in_bounds(c) or level.get_tile(c) != T.FLOOR:
			break
		cells.append(c)
		cells.append(c + Vector2i(dir.x, 0))
		c += Vector2i(dir.x, 0) if step % 2 == 0 else Vector2i(0, dir.y)
	return cells


## Колонны собора: общая сетка с шагом step там, где вокруг клетки весь пол (одиночная колонна связность не рвёт).
static func _add_pillars(level: LevelData, step: int) -> void:
	if step <= 0:
		return
	for c in level.find_cells(T.FLOOR):
		if c.x % step == PILLAR_PHASE and c.y % step == PILLAR_PHASE and _open_around(level, c):
			level.set_tile(c, T.WALL)


## Рощицы леса — кучка деревьев (стена 3–6 клеток) посреди поляны; связность карты не рвётся.
static func _add_groves(level: LevelData, rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var cells := _blob(level, rng, rng.randi_range(3, 6), 0.8)
		if cells.size() >= 3 and cells.all(func(c: Vector2i) -> bool: return _open_around(level, c) or cells.has(c)):
			_try_set(level, cells, T.WALL)


## Все 8 соседей клетки — пол.
static func _open_around(level: LevelData, cell: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := cell + Vector2i(dx, dy)
			if (dx != 0 or dy != 0) and (not level.in_bounds(n) or level.get_tile(n) != T.FLOOR):
				return false
	return true

## Проходимый декор кучками по 3–8 клеток, пока не наберётся share пола (мусор по одной клетке был шумом).
static func _add_rubble(level: LevelData, rng: RandomNumberGenerator, share: float) -> void:
	var target := int(share * level.find_cells(T.FLOOR).size())
	var placed := 0
	for attempt in 40:
		if placed >= target:
			return
		for c in _blob(level, rng, rng.randi_range(3, 8), 0.6):
			level.set_tile(c, T.RUBBLE)
			placed += 1


# --- Метки -------------------------------------------------------------------------------------

## Метки ставятся только на пол, достижимый от спавна; выход — далеко от спавна.
static func _place_markers(level: LevelData, rng: RandomNumberGenerator) -> void:
	var floor_cells := level.find_cells(T.FLOOR)
	if floor_cells.is_empty():
		return
	var spawn := floor_cells[rng.randi_range(0, floor_cells.size() - 1)]
	level.set_tile(spawn, T.PLAYER_SPAWN)
	var dist := LevelValidator.bfs(level, spawn)
	var taken: Array[Vector2i] = [spawn]

	var far := _candidates(level, dist, maxi(MIN_EXIT_DISTANCE, int(_max_distance(dist) * 0.6)), taken)
	_put(level, rng, far, T.EXIT, 1, taken)
	_put(level, rng, _candidates(level, dist, MIN_ENEMY_DISTANCE, taken), T.ENEMY_SPAWN, rng.randi_range(3, 6), taken)
	_put(level, rng, _candidates(level, dist, MIN_CHEST_DISTANCE, taken), T.CHEST, rng.randi_range(1, 3), taken)
	if rng.randf() < 0.6:
		_put(level, rng, _candidates(level, dist, 4, taken), T.FOUNTAIN, 1, taken)
	if rng.randf() < 0.5:
		_put(level, rng, _candidates(level, dist, 6, taken), T.STATUE, 1, taken)
	var obelisks: int = [0, 1, 1, 2][rng.randi_range(0, 3)]
	if obelisks > 0:
		_put(level, rng, _candidates(level, dist, 6, taken), T.OBELISK, obelisks, taken)


## Тайник: прямоугольник пола SECRET_SIDE в толще стены, отделённый от проходимой области стеной ровно в одну
## клетку хотя бы в одном месте («дверь»), а в остальных — не тоньше одной клетки. Ставится после меток:
## метки и точка появления в тайник не попадают, он недостижим от спавна (валидатор держит долю
## достижимых ≥ 75 %, карман в 6–16 клеток её не нарушает). Нет подходящего места — тайника нет.
static func add_secret(level: LevelData, rng: RandomNumberGenerator) -> bool:
	for attempt in 240:
		var w := rng.randi_range(SECRET_SIDE.x, SECRET_SIDE.y)
		var h := rng.randi_range(SECRET_SIDE.x, SECRET_SIDE.y)
		if w * h < SECRET_MIN_AREA:
			continue  # мелкий карман модель сглаживает в стену
		var rect := Rect2i(rng.randi_range(1, level.size - 1 - w), rng.randi_range(1, level.size - 1 - h), w, h)
		if _solid_rect(level, rect.grow(1)) and not secret_doors(level, rect).is_empty():
			_fill(level, rect, T.FLOOR)
			return true
	return false


## Клетки-«двери» тайника rect: стена вплотную к нему, за которой (по той же прямой) проходимая клетка.
static func secret_doors(level: LevelData, rect: Rect2i) -> Array[Vector2i]:
	var doors: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var door := Vector2i(x, y) + d
				var beyond := door + d
				if rect.has_point(door) or not level.in_bounds(beyond):
					continue
				if level.get_tile(door) == T.WALL and Palette.is_passable(level.get_tile(beyond)):
					doors.append(door)
	return doors


static func _solid_rect(level: LevelData, rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not level.in_bounds(Vector2i(x, y)) or level.get_tile(Vector2i(x, y)) != T.WALL:
				return false
	return true

static func _candidates(level: LevelData, dist: PackedInt32Array, min_distance: int, taken: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c in level.find_cells(T.FLOOR):
		if dist[level.index_of(c)] >= min_distance and _far_from(c, taken):
			result.append(c)
	return result


static func _put(level: LevelData, rng: RandomNumberGenerator, candidates: Array[Vector2i], id: int,
		count: int, taken: Array[Vector2i]) -> void:
	for k in count:
		var free := candidates.filter(func(c: Vector2i) -> bool: return _far_from(c, taken))
		if free.is_empty():
			return
		var cell: Vector2i = free[rng.randi_range(0, free.size() - 1)]
		level.set_tile(cell, id)
		taken.append(cell)


static func _far_from(cell: Vector2i, taken: Array[Vector2i]) -> bool:
	for t in taken:
		if maxi(absi(cell.x - t.x), absi(cell.y - t.y)) < MARKER_SPACING:
			return false
	return true


static func _max_distance(dist: PackedInt32Array) -> int:
	var best := 0
	for d in dist:
		best = maxi(best, d)
	return best


# --- Служебное ---------------------------------------------------------------------------------

## Стены, не касающиеся проходимых клеток (по 8 соседям), становятся пустотой — «толща породы».
static func _mark_void(level: LevelData) -> void:
	var next := level.tiles.duplicate()
	for y in level.size:
		for x in level.size:
			var cell := Vector2i(x, y)
			if level.get_tile(cell) != T.WALL:
				continue
			var touches := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := cell + Vector2i(dx, dy)
					if level.in_bounds(n) and Palette.is_passable(level.get_tile(n)):
						touches = true
			if not touches:
				next[level.index_of(cell)] = T.VOID
	level.tiles = next


## Острова пола, кроме самого большого, заливаются стеной (только при создании датасета).
static func _keep_largest_region(level: LevelData) -> void:
	var regions := _regions(level)
	if regions.size() <= 1:
		return
	regions.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	for i in range(1, regions.size()):
		for index: int in regions[i]:
			level.tiles[index] = T.WALL


static func _region_count(level: LevelData) -> int:
	return _regions(level).size()


@warning_ignore("integer_division")
static func _regions(level: LevelData) -> Array:
	var seen := PackedByteArray()
	seen.resize(level.tiles.size())
	var regions := []
	for start in level.tiles.size():
		if seen[start] == 1 or not Palette.is_passable(level.tiles[start]):
			continue
		var dist := LevelValidator.bfs(level, Vector2i(start % level.size, start / level.size))
		var region := []
		for i in dist.size():
			if dist[i] >= 0:
				seen[i] = 1
				region.append(i)
		regions.append(region)
	return regions


static func _fill(level: LevelData, rect: Rect2i, id: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if level.in_bounds(Vector2i(x, y)):
				level.set_tile(Vector2i(x, y), id)
