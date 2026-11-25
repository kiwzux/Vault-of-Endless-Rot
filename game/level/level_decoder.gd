class_name LevelDecoder
extends RefCounted
## ФТ-02, ФТ-03: выход модели probs[1, C, S, S] (softmax по C каналам палитры) → LevelData.
## Правила декодирования (DESIGN 2.2) — автоматические и детерминированные, без ручной постобработки:
## 1. Рельеф: тайл клетки — argmax по каналам рельефа (VOID, FLOOR, WALL, HAZARD, RUBBLE).
## 2. Метки — пики «тепловой карты» своего канала. Метки редкие и в обучающих данных стоят в случайных
##    клетках пола, поэтому модель выдаёт для них распределение вероятностей, а не уверенный argmax клетки.
##    Кандидаты — клетки пола, достижимые от спавна игрока и не ближе MARKER_SPACING к уже поставленным меткам;
##    берутся по убыванию вероятности канала.
## 3. Число меток k = round(Σ вероятностей канала по карте) — ожидаемое число по модели, в пределах лимитов
##    валидатора (MARKER_COUNTS); у спавна игрока и выхода k = 1.
## 4. Спавн игрока — пик своего канала среди клеток пола; выход — пик среди клеток не ближе
##    min_spawn_exit_distance шагов от спавна.
## 5. spawn_weights — вероятность ENEMY_SPAWN, нормированная на максимум по карте, в 0..255 (ФТ-03).

const TERRAIN: Array[int] = [
	Palette.Tile.VOID, Palette.Tile.FLOOR, Palette.Tile.WALL, Palette.Tile.HAZARD, Palette.Tile.RUBBLE,
]
## Порядок расстановки меток: каждая следующая не встаёт рядом с уже поставленными.
const MARKER_ORDER: Array[int] = [
	Palette.Tile.PLAYER_SPAWN, Palette.Tile.EXIT, Palette.Tile.ENEMY_SPAWN, Palette.Tile.CHEST,
	Palette.Tile.FOUNTAIN, Palette.Tile.STATUE, Palette.Tile.OBELISK,
]
## Как в генераторах датасета: метки не ставятся вплотную друг к другу (расстояние Чебышёва).
const MARKER_SPACING := 3
## Потолок числа меток без лимита в валидаторе (точки врагов, сундуки).
const UNLIMITED_CAP := 8


@warning_ignore("integer_division")
static func decode(probs: PackedFloat32Array, size: int, biome: int, room_type: int,
		gen_seed: int, model_hash: String,
		min_exit_distance: int = LevelValidator.DEFAULT_MIN_SPAWN_EXIT_DISTANCE) -> LevelData:
	var cells := size * size
	assert(probs.size() == Palette.class_count() * cells, "LevelDecoder: размер выхода модели не совпадает с палитрой")
	var level := LevelData.create_empty(size)
	level.biome = biome
	level.room_type = room_type
	level.gen_seed = gen_seed
	level.model_hash = model_hash

	for i in cells:
		var best := TERRAIN[0]
		for id in TERRAIN:
			if probs[id * cells + i] > probs[best * cells + i]:
				best = id
		level.tiles[i] = best

	var taken: Array[int] = []
	var distances := PackedInt32Array()
	for id in MARKER_ORDER:
		var allowed := func(i: int) -> bool: return level.tiles[i] == Palette.Tile.FLOOR
		if id == Palette.Tile.EXIT:
			allowed = func(i: int) -> bool:
				return level.tiles[i] == Palette.Tile.FLOOR and distances[i] >= min_exit_distance
		elif id != Palette.Tile.PLAYER_SPAWN:
			allowed = func(i: int) -> bool: return level.tiles[i] == Palette.Tile.FLOOR and distances[i] >= 0
		for i in _peaks(probs, id, cells, size, marker_count(probs, id, cells), allowed, taken):
			level.tiles[i] = id
			taken.append(i)
		if id == Palette.Tile.PLAYER_SPAWN:
			if taken.is_empty():
				break  # на карте нет пола — валидатор отбракует её
			distances = LevelValidator.bfs(level, Vector2i(taken[0] % size, taken[0] / size))

	var enemy_base := Palette.Tile.ENEMY_SPAWN * cells
	var peak := 0.0
	for i in cells:
		peak = maxf(peak, probs[enemy_base + i])
	if peak > 0.0:
		for i in cells:
			level.spawn_weights[i] = roundi(255.0 * probs[enemy_base + i] / peak)
	return level


## Правило 3: ожидаемое число меток канала по модели, в пределах лимитов валидатора.
static func marker_count(probs: PackedFloat32Array, id: int, cells: int) -> int:
	var limits: Array = LevelValidator.MARKER_COUNTS[id]
	if limits[0] == 1 and limits[1] == 1:
		return 1
	var expected := 0.0
	for i in cells:
		expected += probs[id * cells + i]
	var high: int = limits[1] if limits[1] >= 0 else UNLIMITED_CAP
	return clampi(roundi(expected), limits[0], high)


## Правило 2: count клеток с наибольшей вероятностью канала id среди разрешённых, с отступом от занятых.
## Равные вероятности — по меньшему индексу клетки, ради детерминизма.
@warning_ignore("integer_division")
static func _peaks(probs: PackedFloat32Array, id: int, cells: int, size: int, count: int,
		allowed: Callable, taken: Array[int]) -> Array[int]:
	var base := id * cells
	var candidates: Array[int] = []
	for i in cells:
		if allowed.call(i):
			candidates.append(i)
	candidates.sort_custom(func(a: int, b: int) -> bool:
		return probs[base + a] > probs[base + b] or (probs[base + a] == probs[base + b] and a < b))
	var chosen: Array[int] = []
	for i in candidates:
		if chosen.size() >= count:
			break
		var free := true
		for t in taken + chosen:
			if maxi(absi(i % size - t % size), absi(i / size - t / size)) < MARKER_SPACING:
				free = false
				break
		if free:
			chosen.append(i)
	return chosen
