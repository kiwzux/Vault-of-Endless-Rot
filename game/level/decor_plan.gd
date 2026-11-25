class_name DecorPlan
extends RefCounted
## Предметы обстановки уровня (шаг 11.29): неинтерактивный декор биома (BiomeData.decor_wall, decor_open) — высокие
## предметы у стен (клетка пола прямо под стеной: предмет стоит у её подножия), низкие — на открытом полу (все
## восемь соседей проходимы; кучкой — кладбище, грибница). Не встаёт на метки и рядом с ними, у точки появления, на
## мусоре (там разрушаемое) и в недостижимых карманах (тайник выдал бы себя); места — не ближе SPACING клеток у стен
## и OPEN_SPACING на полу.
## План зависит только от карты (сид — контрольная сумма LevelData): у хоста и клиентов он один и тот же, по сети
## ничего не уходит. Проходимость и валидатор (ФТ-04) не меняются: с предметами никто не сталкивается.
## Считается один раз на уровень и хранится в метаданных LevelData — пролом стены тайника его не сдвигает.

const META := &"decor_plan"
## Не ближе этого (клеток, по большей из осей) друг к другу (у стен и на открытом полу) и к меткам карты.
const SPACING := 3
const OPEN_SPACING := 2
const MARKER_GAP := 2
## Не ближе этого числа шагов к точке появления героев.
const SPAWN_GAP := 3


## План уровня: [{"id": StringName, "pos": Vector2 (px мира, опора предмета), "flip": bool}].
static func of(level: LevelData) -> Array:
	if level == null:
		return []
	if level.has_meta(META):
		return level.get_meta(META)
	var plan := build(level)
	level.set_meta(META, plan)
	return plan


## Расчёт заново (проверки сравнивают его с сохранённым).
static func build(level: LevelData) -> Array:
	var biome := LevelLights.biome_of(level)
	if level == null or level.art_style != "" or biome == null:
		return []  # Убежище и тестовые арены — без декора биома
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(level.checksum())
	var spawn := level.find_first(Palette.Tile.PLAYER_SPAWN)
	var reach := LevelValidator.bfs(level, spawn) if spawn != LevelData.INVALID_CELL else PackedInt32Array()
	var blocked := {}
	var walls: Array[Vector2i] = []
	var open: Array[Vector2i] = []
	for y in level.size:
		for x in level.size:
			var cell := Vector2i(x, y)
			var id := level.get_tile(cell)
			if id == Palette.Tile.RUBBLE or (Palette.is_marker(id) and id != Palette.Tile.FLOOR):
				_block(blocked, cell, MARKER_GAP)
			if id != Palette.Tile.FLOOR or reach.is_empty() or reach[level.index_of(cell)] < SPAWN_GAP:
				continue
			if level.in_bounds(cell + Vector2i.UP) and level.get_tile(cell + Vector2i.UP) == Palette.Tile.WALL:
				walls.append(cell)
			elif _is_open(level, cell):
				open.append(cell)
	var plan := []
	_place(plan, rng, walls, biome.decor_wall, biome.decor_wall_count, 1, blocked, true)
	_place(plan, rng, open, biome.decor_open, biome.decor_open_count, biome.decor_cluster, blocked, false)
	return plan


## Подпись плана — для сверки хоста и клиента (сеть).
static func signature(level: LevelData) -> int:
	return hash(var_to_str(of(level)))


## count мест из cells; на месте у стены — один предмет, на открытом полу — кучка от 1 до cluster.
static func _place(plan: Array, rng: RandomNumberGenerator, cells: Array[Vector2i], ids: Array[StringName], count: int,
		cluster: int, blocked: Dictionary, by_wall: bool) -> void:
	if ids.is_empty() or count <= 0:
		return
	var order := cells.duplicate()
	for i in range(order.size() - 1, 0, -1):  # перемешивание своим генератором — тот же порядок у всех участников
		var j := rng.randi_range(0, i)
		var swap: Vector2i = order[i]
		order[i] = order[j]
		order[j] = swap
	var tile := float(Palette.tile_size())
	var placed := 0
	for cell: Vector2i in order:
		if placed >= count:
			break
		if blocked.has(cell):
			continue
		var id: StringName = ids[rng.randi_range(0, ids.size() - 1)]
		if by_wall:
			var spot := Vector2(cell) + Vector2(0.5 + rng.randf_range(-0.3, 0.3), 0.18 + rng.randf_range(0.0, 0.12))
			plan.append({"id": id, "pos": spot * tile, "flip": rng.randf() < 0.5})
		else:
			# Кучка: предметы вокруг середины клетки, не друг на друге (сдвиг по кругу с шагом).
			var many := rng.randi_range(1, maxi(cluster, 1))
			var turn := rng.randf() * TAU
			for k in many:
				var around := Vector2.ZERO if many == 1 else Vector2.RIGHT.rotated(turn + TAU * k / many) * rng.randf_range(0.22, 0.34)
				var spot := Vector2(cell) + Vector2(0.5, 0.5) + around + Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.06, 0.06))
				plan.append({"id": id if k == 0 or rng.randf() < 0.7 else ids[rng.randi_range(0, ids.size() - 1)],
						"pos": spot * tile, "flip": rng.randf() < 0.5})
		_block(blocked, cell, (SPACING if by_wall else OPEN_SPACING) - 1)
		placed += 1


static func _block(blocked: Dictionary, cell: Vector2i, gap: int) -> void:
	for dy in range(-gap, gap + 1):
		for dx in range(-gap, gap + 1):
			blocked[cell + Vector2i(dx, dy)] = true


## Клетка посреди открытого пола: все восемь соседей проходимы и не опасны.
static func _is_open(level: LevelData, cell: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var next := cell + Vector2i(dx, dy)
			if not level.in_bounds(next):
				return false
			var id := level.get_tile(next)
			if not Palette.is_passable(id) or id == Palette.Tile.HAZARD:
				return false
	return true
