@tool
class_name LevelValidator
extends RefCounted
## ФТ-04: детерминированная проверка проходимости — BFS по 4-связности от точки спавна игрока
## по проходимым клеткам палитры. Модель в проверке не участвует. Карта либо принимается, либо
## отбраковывается целиком (ФТ-05): валидатор ничего не «чинит», иначе это была бы ручная постобработка (ФТ-01).

const DEFAULT_MIN_PASSABLE_RATIO := 0.35
const DEFAULT_MIN_SPAWN_EXIT_DISTANCE := 12
## Доля проходимых клеток, достижимых от спавна: сильно раздробленная карта с маленькой игровой зоной
## отбраковывается. В обучающих данных все карты связные.
const DEFAULT_MIN_REACHABLE_RATIO := 0.75

## Допустимое число меток каждого вида: [минимум, максимум], максимум -1 — без ограничения.
## Эти же лимиты применяет декодер (LevelDecoder), поэтому лимит здесь нарушается только при ошибке декодера.
const MARKER_COUNTS := {
	Palette.Tile.PLAYER_SPAWN: [1, 1],
	Palette.Tile.EXIT: [1, 1],
	Palette.Tile.ENEMY_SPAWN: [1, -1],  # ФТ-03: ≥ 1 точка спавна врагов
	Palette.Tile.CHEST: [1, -1],  # ФТ-03: ≥ 1 точка лута
	Palette.Tile.FOUNTAIN: [0, 1],
	Palette.Tile.STATUE: [0, 1],
	Palette.Tile.OBELISK: [0, 2],
}
## Метки, каждая из которых обязана быть достижима от спавна игрока.
const MUST_REACH: Array[int] = [
	Palette.Tile.EXIT, Palette.Tile.CHEST, Palette.Tile.FOUNTAIN, Palette.Tile.STATUE, Palette.Tile.OBELISK,
]

## Пороги — поля, а не константы: их уточняют запросом на изменение после замеров (ЛР2, раздел 8).
var min_passable_ratio := DEFAULT_MIN_PASSABLE_RATIO
var min_spawn_exit_distance := DEFAULT_MIN_SPAWN_EXIT_DISTANCE
var min_reachable_ratio := DEFAULT_MIN_REACHABLE_RATIO


class Report:
	var valid := false
	## Коды причин отказа для журнала, например "exit_unreachable". Это не текст UI, перевод не нужен.
	var errors := PackedStringArray()
	var passable_ratio := 0.0
	## Доля проходимых клеток, достижимых от спавна игрока.
	var reachable_ratio := 0.0
	var spawn_exit_distance := -1
	## BFS-расстояние от спавна игрока до каждой клетки, -1 — недостижима (для отладочного оверлея F3).
	var distances := PackedInt32Array()

	func to_dict() -> Dictionary:
		return {
			"valid": valid,
			"errors": Array(errors),
			"passable_ratio": snappedf(passable_ratio, 0.001),
			"reachable_ratio": snappedf(reachable_ratio, 0.001),
			"spawn_exit_distance": spawn_exit_distance,
		}


func validate(level: LevelData) -> Report:
	var report := Report.new()
	var cells := level.size * level.size
	var counts := PackedInt32Array()
	counts.resize(Palette.class_count())
	var passable := 0
	for i in cells:
		var id := level.tiles[i]
		counts[id] += 1
		if Palette.is_passable(id):
			passable += 1
	report.passable_ratio = float(passable) / cells

	for id: int in MARKER_COUNTS:
		var limits: Array = MARKER_COUNTS[id]
		if counts[id] < limits[0] or (limits[1] >= 0 and counts[id] > limits[1]):
			report.errors.append("%s_count" % Palette.name_of(id).to_lower())
	if report.passable_ratio < min_passable_ratio:
		report.errors.append("too_few_passable")

	var spawn := level.find_first(Palette.Tile.PLAYER_SPAWN)
	if spawn != LevelData.INVALID_CELL:
		report.distances = bfs(level, spawn)
		var reachable := 0
		for d in report.distances:
			if d >= 0:
				reachable += 1
		report.reachable_ratio = float(reachable) / passable
		if report.reachable_ratio < min_reachable_ratio:
			report.errors.append("too_few_reachable")
		for id in MUST_REACH:
			for cell in level.find_cells(id):
				if report.distances[level.index_of(cell)] < 0:
					report.errors.append("%s_unreachable" % Palette.name_of(id).to_lower())
					break
		if counts[Palette.Tile.ENEMY_SPAWN] > 0 and not _any_reachable(level, report, Palette.Tile.ENEMY_SPAWN):
			report.errors.append("enemy_spawn_unreachable")
		var exit := level.find_first(Palette.Tile.EXIT)
		if exit != LevelData.INVALID_CELL:
			report.spawn_exit_distance = report.distances[level.index_of(exit)]
			if report.spawn_exit_distance >= 0 and report.spawn_exit_distance < min_spawn_exit_distance:
				report.errors.append("exit_too_close")

	report.valid = report.errors.is_empty()
	return report


## Расстояния в шагах по 4-связности от start до каждой клетки; -1 — клетка недостижима.
@warning_ignore("integer_division")
static func bfs(level: LevelData, start: Vector2i) -> PackedInt32Array:
	var size := level.size
	var distances := PackedInt32Array()
	distances.resize(size * size)
	distances.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(size * size)
	var head := 0
	var tail := 0
	var first := level.index_of(start)
	distances[first] = 0
	queue[tail] = first
	tail += 1
	while head < tail:
		var i := queue[head]
		head += 1
		var x := i % size
		var y := i / size
		var next := distances[i] + 1
		for neighbour: int in [
			i - 1 if x > 0 else -1,
			i + 1 if x < size - 1 else -1,
			i - size if y > 0 else -1,
			i + size if y < size - 1 else -1,
		]:
			if neighbour >= 0 and distances[neighbour] == -1 and Palette.is_passable(level.tiles[neighbour]):
				distances[neighbour] = next
				queue[tail] = neighbour
				tail += 1
	return distances


func _any_reachable(level: LevelData, report: Report, id: int) -> bool:
	for cell in level.find_cells(id):
		if report.distances[level.index_of(cell)] >= 0:
			return true
	return false
