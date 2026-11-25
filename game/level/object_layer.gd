class_name ObjectLayer
extends RefCounted
## Слой объектов поверх меток карты CVAE (шаг 9): объекты HoMM3, испытания, торговцы и интерактивные точки.
## Отдельного генератора нет (ОГР-02): места — метки модели, клетки декора и проходимость её карты; плотность
## и риск — правила биома (ObjectRules). Расчёт детерминирован: тот же сид забега, глубина и карта дают
## тот же слой. Сцену не трогает — работает на хосте до создания объектов (LevelFlow создаёт их по слою).

const MARKER_OBJECTS := {
	Palette.Tile.CHEST: &"chest",
	Palette.Tile.FOUNTAIN: &"fountain",
	Palette.Tile.STATUE: &"statue",
	Palette.Tile.OBELISK: &"obelisk",
}
## Испытания (CR-16): на метке STATUE — одно из трёх; ещё extra_challenges — у меток ENEMY_SPAWN.
const STATUE_CHALLENGES: Array[StringName] = [&"statue", &"trial_altar", &"cursed_totem"]
const EXTRA_CHALLENGES: Array[StringName] = [&"trial_altar", &"cursed_totem"]
const CHALLENGE_RING := 2
const ARTIFACT_MERCHANT := &"artifact_merchant"
const ALCHEMIST := &"alchemist"
## Торговец стоит не ближе этого (в клетках) к метке, у которой встал: не загораживает объект.
const MERCHANT_RING := 2
## Алхимик — не ближе этого числа шагов к точке появления; иначе он встаёт у выхода
## (валидатор ФТ-04 держит выход не ближе 12 шагов).
const MERCHANT_SPREAD := 8
const POINT_RING := 2
const UNREACHABLE := -1

var _plan: MapPlan
var _level: LevelData
var _rules: ObjectRules
var _depth := 0
var _final := false
## BFS-расстояние от точки появления героев до каждой клетки, -1 — недостижима.
var _spawn_dist := PackedInt32Array()


## Слой объектов для карты level по запросу request (биом, глубина, сид).
static func plan(level: LevelData, request: MapRequest, source: String = MapPlan.SOURCE_MODEL) -> MapPlan:
	var layer := ObjectLayer.new()
	layer._plan = MapPlan.create(request, level, source)
	layer._level = level
	layer._rules = request.biome.objects if request.biome != null and request.biome.objects != null else ObjectRules.new()
	layer._depth = request.depth
	layer._final = request.biome != null and request.biome.final_lair
	var spawn := level.find_first(Palette.Tile.PLAYER_SPAWN)
	if spawn == LevelData.INVALID_CELL:
		return layer._plan
	layer._spawn_dist = LevelValidator.bfs(level, spawn)
	layer._map_objects(request)
	layer._merchants()
	layer._points(request)
	layer._secrets(request)
	return layer._plan


## Объекты HoMM3 по меткам модели. В логове обелисков нет: их метка — место Грааля (LevelFlow).
func _map_objects(request: MapRequest) -> void:
	var rng := _rng(request, "challenges")
	var shrines := DataRegistry.interactables_for(&"fountain", _depth)
	for tile: int in MARKER_OBJECTS:
		if _final and tile == Palette.Tile.OBELISK:
			continue
		for cell in _level.find_cells(tile):
			var kind: StringName = MARKER_OBJECTS[tile]
			if tile == Palette.Tile.STATUE:
				kind = STATUE_CHALLENGES[rng.randi_range(0, STATUE_CHALLENGES.size() - 1)]
			if tile == Palette.Tile.FOUNTAIN and not shrines.is_empty() and rng.randf() < _rules.shrine_chance:
				_plan.add(&"interactable", cell, {"type": _pick(shrines, rng).id})  # шаг 8: святилище вместо фонтана
				continue
			var fields := {}
			if kind == &"chest" and _depth >= _rules.mimic_min_depth and rng.randf() < _rules.mimic_chance:
				fields["mimic"] = true  # шаг 8: мимик знает только хост
			_plan.add(kind, cell, fields)
	var spawns := _level.find_cells(Palette.Tile.ENEMY_SPAWN)
	if _final or spawns.is_empty():
		return
	for i in _rules.extra_challenges:
		var near := spawns[rng.randi_range(0, spawns.size() - 1)]
		_plan.add(EXTRA_CHALLENGES[rng.randi_range(0, EXTRA_CHALLENGES.size() - 1)], free_cell_near(near, CHALLENGE_RING))
	_extras(request)


## Сверх меток модели (17.10.2026): платные сундуки и святилища-баффы на разнесённых клетках пола карты модели.
func _extras(request: MapRequest) -> void:
	var rng := _rng(request, "extras")
	var free := _scatter_cells()
	for i in _rules.extra_chests:
		var at := _take_scattered(free, rng)
		if at == LevelData.INVALID_CELL:
			return
		var fields := {}
		if _depth >= _rules.mimic_min_depth and rng.randf() < _rules.mimic_chance:
			fields["mimic"] = true
		_plan.add(&"chest", at, fields)
	var shrines := DataRegistry.interactables_for(&"fountain", _depth).filter(
			func(p: InteractableData) -> bool: return p.kind == InteractableData.Kind.SHRINE)
	if shrines.is_empty():
		return
	for i in _rules.extra_shrines:
		var at := _take_scattered(free, rng)
		if at == LevelData.INVALID_CELL:
			return
		_plan.add(&"interactable", at, {"type": _pick(shrines, rng).id})
	_easter_egg(request, free)


## Пасхалка: Золотое ведро — только на первом уровне забега (глубина 0), с шансом golden_bucket_chance.
func _easter_egg(request: MapRequest, free: Array[Vector2i]) -> void:
	var buckets := DataRegistry.interactables_for(&"easter", _depth)
	if _depth != 0 or buckets.is_empty() or _rng(request, "golden_bucket").randf() >= _rules.golden_bucket_chance:
		return
	var at := _take_scattered(free, _rng(request, "golden_bucket_cell"))
	if at != LevelData.INVALID_CELL:
		_plan.add(&"interactable", at, {"type": buckets[0].id})


## Клетки пола, достижимые от точки появления и не ближе scatter_spawn_gap шагов к ней.
func _scatter_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _level.find_cells(Palette.Tile.FLOOR):
		if spawn_distance(cell) >= _rules.scatter_spawn_gap:
			result.append(cell)
	return result


## Случайная клетка из free не ближе scatter_gap к занятым слоем; INVALID_CELL — такой не нашлось.
func _take_scattered(free: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	for attempt in 40:
		if free.is_empty():
			break
		var cell := free[rng.randi_range(0, free.size() - 1)]
		var crowded := false
		for other: Vector2i in _plan.occupied:
			if maxi(absi(other.x - cell.x), absi(other.y - cell.y)) < _rules.scatter_gap:
				crowded = true
				break
		if not crowded:
			free.erase(cell)
			return cell
	return LevelData.INVALID_CELL


## CR-14: торговец артефактами — у точки появления героев, алхимик — у самой дальней по пути от неё метки
## объекта; в логове — только алхимик у входа.
func _merchants() -> void:
	var spawn := _level.find_first(Palette.Tile.PLAYER_SPAWN)
	var plan := [[ALCHEMIST, spawn]] if _final else [[ARTIFACT_MERCHANT, spawn], [ALCHEMIST, _farthest_object_marker()]]
	for entry: Array in plan:
		_plan.add(&"merchant", free_cell_near(entry[1], MERCHANT_RING), {"merchant": entry[0]})


## Шаг 8: интерактивные точки. Разрушаемое — на клетках декора RUBBLE подальше от точки появления; лор
## и алтарь проклятий — рядом с метками объектов; пленник — у метки появления врагов. В логове — только
## разрушаемое и лор.
func _points(request: MapRequest) -> void:
	var rng := _rng(request, "interactables")
	var breakables := DataRegistry.interactables_for(&"rubble", _depth)
	var rubble := _level.find_cells(Palette.Tile.RUBBLE).filter(func(c: Vector2i) -> bool:
		return spawn_distance(c) >= _rules.breakable_spawn_gap and not c in _plan.occupied)
	_shuffle(rubble, rng)
	for i in mini(rubble.size(), _rules.breakables_max if not breakables.is_empty() else 0):
		_plan.add(&"interactable", rubble[i], {"type": _pick(breakables, rng).id})
	var markers := _object_markers()
	var near_marker := DataRegistry.interactables_for(&"near_marker", _depth)
	var lore_sites := near_marker.filter(func(p: InteractableData) -> bool: return p.kind == InteractableData.Kind.LORE)
	var entries: Array = DataRegistry.LORE.duplicate()
	_shuffle(entries, rng)
	for i in mini(_rules.lore_per_level, entries.size()):
		if lore_sites.is_empty() or markers.is_empty():
			break
		var at := free_cell_near(markers[rng.randi_range(0, markers.size() - 1)], POINT_RING)
		_plan.add(&"interactable", at, {"type": _pick(lore_sites, rng).id, "lore": (entries[i] as LoreData).id})
	if _final:
		return
	var altars := near_marker.filter(func(p: InteractableData) -> bool: return p.kind == InteractableData.Kind.CURSE_ALTAR)
	if not altars.is_empty() and not markers.is_empty() and rng.randf() < _rules.risk(_rules.curse_altar_chance, _depth):
		var at := free_cell_near(markers[rng.randi_range(0, markers.size() - 1)], POINT_RING)
		_plan.add(&"interactable", at, {"type": _pick(altars, rng).id})
	var prisoners := DataRegistry.interactables_for(&"enemy_spawn", _depth)
	var spawns := _level.find_cells(Palette.Tile.ENEMY_SPAWN)
	for i in _rules.prisoner_tries:
		if not prisoners.is_empty() and not spawns.is_empty() and rng.randf() < _rules.risk(_rules.prisoner_chance, _depth):
			var at := free_cell_near(spawns[rng.randi_range(0, spawns.size() - 1)], POINT_RING)
			_plan.add(&"interactable", at, {"type": _pick(prisoners, rng).id})


## Шаг 9: тайники — карманы, которые нарисовала модель (SecretRooms). На двери — треснувшая стена (её бьют по E),
## внутри — клад и иногда святилище. Карманы и их содержимое — тоже из карты модели, без своего генератора.
func _secrets(request: MapRequest) -> void:
	var rng := _rng(request, "secrets")
	var walls := DataRegistry.interactables_for(&"secret_door", _depth)
	var hoards := DataRegistry.interactables_for(&"secret", _depth)
	if walls.is_empty() or hoards.is_empty():
		return
	var shrines := DataRegistry.interactables_for(&"fountain", _depth).filter(
			func(p: InteractableData) -> bool: return p.kind == InteractableData.Kind.SHRINE)
	var rooms := SecretRooms.find(_level)
	for room in rooms.slice(0, _rules.secret_rooms_max):
		var doors: Array[Vector2i] = room["doors"]
		var center: Vector2i = room["center"]
		var door := doors[rng.randi_range(0, doors.size() - 1)]
		_plan.add(&"interactable", door, {"type": _pick(walls, rng).id, "room": center})
		_plan.add(&"interactable", center, {"type": _pick(hoards, rng).id})
		var cells: Array[Vector2i] = room["cells"]
		if cells.size() >= 6 and not shrines.is_empty() and rng.randf() < _rules.secret_shrine_chance:
			var far := cells[0]
			for c in cells:
				if Vector2(c).distance_squared_to(center) > Vector2(far).distance_squared_to(center):
					far = c
			_plan.add(&"interactable", far, {"type": _pick(shrines, rng).id})


# --- Карта -------------------------------------------------------------------------------------

func spawn_distance(cell: Vector2i) -> int:
	return _spawn_dist[_level.index_of(cell)] if _level.in_bounds(cell) else UNREACHABLE


## Ближайшая к cell клетка простого пола (без меток), достижимая от точки появления героев, не ближе
## min_ring клеток и не занятая слоем. Нет такой — любая свободная клетка пола; совсем нет — сама cell.
func free_cell_near(cell: Vector2i, min_ring: int) -> Vector2i:
	for require_reachable in [true, false]:
		for ring in range(min_ring, _level.size):
			for dy in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dy)) != ring:
						continue
					var c := cell + Vector2i(dx, dy)
					if not _level.in_bounds(c) or c in _plan.occupied:
						continue
					var tile := _level.get_tile(c)
					if tile != Palette.Tile.FLOOR and tile != Palette.Tile.RUBBLE:
						continue
					if require_reachable and spawn_distance(c) == UNREACHABLE:
						continue
					return c
	return cell


func _object_markers() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for tile: int in MARKER_OBJECTS:
		result.append_array(_level.find_cells(tile))
	return result


## Метка объекта (сундук, фонтан, статуя, обелиск), дальше всех по пути от точки появления;
## если все объекты ближе MERCHANT_SPREAD шагов — выход.
func _farthest_object_marker() -> Vector2i:
	var best := _level.find_first(Palette.Tile.EXIT)
	var best_d := MERCHANT_SPREAD - 1
	for cell in _object_markers():
		var d := spawn_distance(cell)
		if d > best_d:
			best_d = d
			best = cell
	return best


func _rng(request: MapRequest, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([request.run_seed, request.depth, salt])
	return rng


## Точка по весам InteractableData.weight.
static func _pick(options: Array, rng: RandomNumberGenerator) -> InteractableData:
	var weights := PackedFloat32Array()
	for option: InteractableData in options:
		weights.append(option.weight)
	return options[rng.rand_weighted(weights)]


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
