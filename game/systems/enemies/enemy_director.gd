class_name EnemyDirector
extends Node
## Хост: навигация врагов и пространственные запросы для оружия.
## Поле потока — BFS по проходимым клеткам LevelData от всех живых игроков: враг шагает в соседнюю
## клетку с меньшим расстоянием и так обходит стены. Сетка врагов (перестраивается каждый кадр)
## нужна для разведения толпы (steering) и для поиска ближайшей цели без перебора всех врагов.
##
## Шаг 5 (оптимизация): следующая клетка пути считается один раз на клетку за обновление поля и берётся
## из кэша (раньше — 8 соседей на каждого врага каждый тик, 3 мс из 7 при 300 врагах); стены — по логической
## сетке клеток (slide), без физического тела у врага; в сетке врагов нет пустых массивов на каждый запрос.

const FLOW_REFRESH := 0.25
const GRID_CELL := 32.0
## Не меньше самого большого радиуса врага: запросы смотрят соседние ячейки с этим запасом.
const MAX_ENEMY_RADIUS := 20.0
const MAX_NEIGHBOURS := 6
const UNREACHABLE := -1
## Кэш следующей клетки пути: ещё не посчитана; -1 (UNREACHABLE) — шагать некуда.
const NEXT_UNKNOWN := -2
## Зазор, на котором враг останавливается у стены, px.
const WALL_GAP := 0.01
const DIRS4: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const DIRS8: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _world: World
var _level: LevelData
var _tile := 32.0
var _passable := PackedByteArray()
var _size := 0
var _flow := PackedInt32Array()
## Клетка → индекс следующей клетки пути к ближайшему игроку (NEXT_UNKNOWN — посчитать при запросе).
var _next := PackedInt32Array()
## Шагов от точки появления героев до клетки (BFS при загрузке уровня); UNREACHABLE — не дойти.
var _spawn_dist := PackedInt32Array()
var _flow_timer := 0.0
var _grid := {}  # Vector2i -> Array[Enemy]
## Упёрся ли последний slide в стену.
var blocked_last := false
var _hostile_count := 0
var _players: Array[Player] = []


func _ready() -> void:
	process_physics_priority = -10  # сетка и поле готовы до того, как враги начнут двигаться
	_world = World.of(self)
	Events.level_loaded.connect(_on_level_loaded)
	Events.level_cell_changed.connect(_on_level_cell_changed)


func _on_level_loaded(level: LevelData) -> void:
	if not multiplayer.is_server():
		return
	_level = level
	_size = level.size
	_tile = float(Palette.tile_size())
	_passable.resize(level.tiles.size())
	for i in level.tiles.size():
		_passable[i] = 1 if Palette.is_passable(level.tiles[i]) else 0
	_flow.resize(level.tiles.size())
	_flow.fill(UNREACHABLE)
	_next.resize(level.tiles.size())
	_next.fill(NEXT_UNKNOWN)
	_flow_timer = 0.0
	_grid.clear()
	_spawn_dist = _bfs([level.find_first(Palette.Tile.PLAYER_SPAWN)])


## Шаг 9: проломлена стена тайника — клетка стала проходимой; кэш пути и расстояния от точки появления заново.
func _on_level_cell_changed(cell: Vector2i, tile: int) -> void:
	if _level == null or not multiplayer.is_server() or not _level.in_bounds(cell):
		return
	_passable[_level.index_of(cell)] = 1 if Palette.is_passable(tile) else 0
	_next.fill(NEXT_UNKNOWN)
	_flow_timer = 0.0
	_spawn_dist = _bfs([_level.find_first(Palette.Tile.PLAYER_SPAWN)])


func _physics_process(delta: float) -> void:
	if _level == null or not multiplayer.is_server():
		return
	var started := PerfProbe.begin()
	_players.clear()
	for node in _world.players.get_children():
		if node is Player and node.alive:
			_players.append(node)
	_rebuild_grid()
	_flow_timer -= delta
	if _flow_timer <= 0.0:
		_flow_timer = FLOW_REFRESH
		_rebuild_flow()
	PerfProbe.add(&"director", started)


# --- Игроки ---

func players_alive() -> Array[Player]:
	return _players


func nearest_player(pos: Vector2) -> Player:
	var best: Player = null
	var best_d := INF
	for p in _players:
		var d := pos.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func distance_to_nearest_player(pos: Vector2) -> float:
	var p := nearest_player(pos)
	return INF if p == null else pos.distance_to(p.global_position)


# --- Враги ---

## Враги, чей круг пересекает круг (pos, radius).
func enemies_in_radius(pos: Vector2, radius: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	var reach := Vector2.ONE * (radius + MAX_ENEMY_RADIUS)
	var lo := _grid_key(pos - reach)
	var hi := _grid_key(pos + reach)
	for gy in range(lo.y, hi.y + 1):
		for gx in range(lo.x, hi.x + 1):
			var bucket: Variant = _grid.get(Vector2i(gx, gy))
			if bucket == null:
				continue
			for e: Enemy in bucket:
				var r := radius + e.radius
				if not e.dead and pos.distance_squared_to(e.global_position) <= r * r:
					result.append(e)
	return result


func nearest_enemy(pos: Vector2, radius: float, exclude: Dictionary = {}) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for e in enemies_in_radius(pos, radius):
		if exclude.has(e.get_instance_id()):
			continue
		var d := pos.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func nearest_enemies(pos: Vector2, radius: float, count: int) -> Array[Enemy]:
	var found := enemies_in_radius(pos, radius)
	found.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return pos.distance_squared_to(a.global_position) < pos.distance_squared_to(b.global_position))
	return found.slice(0, count)


## Сила расталкивания от соседей: враги не слипаются в одну точку (steering: separation).
func separation(enemy: Enemy) -> Vector2:
	var push := Vector2.ZERO
	var found := 0
	var pos := enemy.global_position
	var key := _grid_key(pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var bucket: Variant = _grid.get(Vector2i(key.x + dx, key.y + dy))
			if bucket == null:
				continue
			for other: Enemy in bucket:
				if other == enemy:
					continue
				var diff := pos - other.global_position
				var min_d := enemy.radius + other.radius + 2.0
				var d2 := diff.length_squared()
				if d2 >= min_d * min_d:
					continue
				if d2 < 0.01:  # точное совпадение: разводим в сторону, зависящую от id
					diff = Vector2.RIGHT.rotated(float(enemy.get_instance_id() % 628) / 100.0)
				push += diff.normalized() * (1.0 - sqrt(d2) / min_d)
				found += 1
				if found >= MAX_NEIGHBOURS:
					return push
	return push


# --- Карта ---

## Направление к ближайшему игроку в обход стен; ZERO — враг уже в клетке игрока или путь не найден.
## Следующая клетка берётся из кэша _next: её считает первый враг, зашедший в клетку после обновления поля.
func flow_direction(pos: Vector2) -> Vector2:
	var cx := floori(pos.x / _tile)
	var cy := floori(pos.y / _tile)
	if cx < 0 or cy < 0 or cx >= _size or cy >= _size:
		return Vector2.ZERO
	var i := cy * _size + cx
	var next := _next[i]
	if next == NEXT_UNKNOWN:
		next = _best_next(cx, cy)
		_next[i] = next
	if next < 0:
		return Vector2.ZERO
	@warning_ignore("integer_division")
	var center := Vector2(float(next % _size) + 0.5, float(next / _size) + 0.5) * _tile
	return (center - pos).normalized()


## Соседняя клетка (8-связность) с наименьшим расстоянием поля потока; по диагонали угол стены не срезается.
## UNREACHABLE — клетка игрока, недостижимая или шагать некуда.
func _best_next(cx: int, cy: int) -> int:
	var here := _flow[cy * _size + cx]
	if here <= 0:
		return UNREACHABLE
	var best := UNREACHABLE
	var best_d := here
	for d in DIRS8:
		var nx := cx + d.x
		var ny := cy + d.y
		if not _open(nx, ny):
			continue
		if d.x != 0 and d.y != 0 and not (_open(nx, cy) and _open(cx, ny)):
			continue
		var nd := _flow[ny * _size + nx]
		if nd != UNREACHABLE and nd < best_d:
			best_d = nd
			best = ny * _size + nx
	return best


## Сдвиг круга (pos, radius) на motion со скольжением вдоль стен — вместо move_and_slide: стены — целые
## непроходимые логические клетки и край карты, поэтому хватает сетки (круг считается квадратом 2·radius).
## Сначала по x, затем по y. Проверяется передний край по ходу шага: упёрся — встаёт вплотную к стене;
## если враг уже задевает стену сзади или сбоку (появился вплотную), отойти от неё он может.
## Возвращает новую позицию; blocked_last — упёрся ли (рывок врага на этом заканчивается).
func slide(pos: Vector2, motion: Vector2, radius: float) -> Vector2:
	blocked_last = false
	if _level == null:
		return pos + motion
	var x := pos.x
	if motion.x != 0.0:
		x += motion.x
		var lead := floori((x + radius if motion.x > 0.0 else x - radius) / _tile)
		if _column_blocked(lead, pos.y - radius, pos.y + radius):
			blocked_last = true
			if motion.x > 0.0:
				x = maxf(pos.x, lead * _tile - radius - WALL_GAP)
			else:
				x = minf(pos.x, (lead + 1) * _tile + radius + WALL_GAP)
	var y := pos.y
	if motion.y != 0.0:
		y += motion.y
		var lead := floori((y + radius if motion.y > 0.0 else y - radius) / _tile)
		if _row_blocked(lead, x - radius, x + radius):
			blocked_last = true
			if motion.y > 0.0:
				y = maxf(pos.y, lead * _tile - radius - WALL_GAP)
			else:
				y = minf(pos.y, (lead + 1) * _tile + radius + WALL_GAP)
	return Vector2(x, y)


## Есть ли стена в столбце клеток gx на отрезке [from_y, to_y].
func _column_blocked(gx: int, from_y: float, to_y: float) -> bool:
	for gy in range(floori(from_y / _tile), floori(to_y / _tile) + 1):
		if not _open(gx, gy):
			return true
	return false


## Есть ли стена в строке клеток gy на отрезке [from_x, to_x].
func _row_blocked(gy: int, from_x: float, to_x: float) -> bool:
	for gx in range(floori(from_x / _tile), floori(to_x / _tile) + 1):
		if not _open(gx, gy):
			return true
	return false


func _open(gx: int, gy: int) -> bool:
	return gx >= 0 and gy >= 0 and gx < _size and gy < _size and _passable[gy * _size + gx] == 1


## Шагов от точки появления героев до клетки; UNREACHABLE — не дойти.
func spawn_distance(cell: Vector2i) -> int:
	if _level == null or not _level.in_bounds(cell):
		return UNREACHABLE
	return _spawn_dist[_level.index_of(cell)]


## Ближайшая к cell клетка простого пола (без меток), достижимая от точки появления героев, не ближе
## min_ring клеток и не из exclude. Нужна, чтобы поставить порталы, место Грааля и торговцев,
## не перекрывая объекты карты.
func free_cell_near(cell: Vector2i, min_ring: int, exclude: Array[Vector2i] = []) -> Vector2i:
	for require_reachable in [true, false]:
		for ring in range(min_ring, _level.size):
			for dy in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dy)) != ring:
						continue
					var c := cell + Vector2i(dx, dy)
					if not _level.in_bounds(c) or c in exclude:
						continue
					var tile := _level.get_tile(c)
					if tile != Palette.Tile.FLOOR and tile != Palette.Tile.RUBBLE:
						continue
					if require_reachable and _spawn_dist[_level.index_of(c)] == UNREACHABLE:
						continue
					return c
	return cell


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / _tile).floor())


func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * _tile


func _is_open(cell: Vector2i) -> bool:
	return _level.in_bounds(cell) and _passable[_level.index_of(cell)] == 1


func _grid_key(pos: Vector2) -> Vector2i:
	return Vector2i((pos / GRID_CELL).floor())


## Живые враждебные враги (без союзников Некроманта): для предела max_alive.
func hostile_count() -> int:
	return _hostile_count


## Сетка только враждебных врагов: союзники не цели для оружия и не участвуют в расталкивании.
func _rebuild_grid() -> void:
	_grid.clear()
	_hostile_count = 0
	for node in _world.enemies.get_children():
		var e := node as Enemy
		if e == null or e.dead or e.ally:
			continue
		_hostile_count += 1
		var key := _grid_key(e.global_position)
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(e)


## Поле потока: многоисточниковый BFS от клеток всех живых игроков.
func _rebuild_flow() -> void:
	var sources: Array[Vector2i] = []
	for p in _players:
		sources.append(world_to_cell(p.global_position))
	_flow = _bfs(sources)
	_next.fill(NEXT_UNKNOWN)


## BFS по проходимым клеткам от нескольких источников (4-связность, как у валидатора ФТ-04).
func _bfs(sources: Array[Vector2i]) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(_level.tiles.size())
	dist.fill(UNREACHABLE)
	var queue := PackedInt32Array()
	for cell in sources:
		if _level.in_bounds(cell) and dist[_level.index_of(cell)] == UNREACHABLE:
			dist[_level.index_of(cell)] = 0
			queue.append(_level.index_of(cell))
	var size := _level.size
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		@warning_ignore("integer_division")
		var cell := Vector2i(i % size, i / size)
		for d in DIRS4:
			var next := cell + d
			if not _is_open(next):
				continue
			var j := _level.index_of(next)
			if dist[j] == UNREACHABLE:
				dist[j] = dist[i] + 1
				queue.append(j)
	return dist
