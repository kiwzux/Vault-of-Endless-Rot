class_name SecretRooms
extends RefCounted
## Тайники карты (шаг 9): закрытые «карманы» пола, которые нарисовала модель — проходимые клетки, недостижимые
## от точки появления героев и отделённые от достижимой области стеной в одну клетку («дверь»). Отдельного
## генератора нет (ОГР-02): модель учится рисовать такие карманы по датасету (DatasetGenerators.add_secret),
## а здесь они только находятся. Детерминировано: та же карта — те же тайники в том же порядке.

## Меньше этого числа клеток — не комната, а шум модели.
const MIN_CELLS := 4
const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


## Тайники карты: [{"cells": Array[Vector2i], "doors": Array[Vector2i], "center": Vector2i}], у каждого хотя бы
## одна дверь. center — клетка тайника, ближайшая к его середине.
@warning_ignore("integer_division")
static func find(level: LevelData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var spawn := level.find_first(Palette.Tile.PLAYER_SPAWN)
	if spawn == LevelData.INVALID_CELL:
		return result
	var reach := LevelValidator.bfs(level, spawn)
	var seen := PackedByteArray()
	seen.resize(level.tiles.size())
	for start in level.tiles.size():
		if seen[start] == 1 or reach[start] >= 0 or not Palette.is_passable(level.tiles[start]):
			continue
		var region := LevelValidator.bfs(level, Vector2i(start % level.size, start / level.size))
		var cells: Array[Vector2i] = []
		for i in region.size():
			if region[i] >= 0:
				seen[i] = 1
				cells.append(Vector2i(i % level.size, i / level.size))
		if cells.size() < MIN_CELLS:
			continue
		var doors := doors_of(level, cells, reach)
		if not doors.is_empty():
			result.append({"cells": cells, "doors": doors, "center": _center(cells)})
	return result


## Стены вплотную к тайнику, за которыми по той же прямой — достижимая клетка.
static func doors_of(level: LevelData, cells: Array[Vector2i], reach: PackedInt32Array) -> Array[Vector2i]:
	var doors: Array[Vector2i] = []
	for c in cells:
		for d in DIRS:
			var door := c + d
			var beyond := door + d
			if not level.in_bounds(beyond) or level.get_tile(door) != Palette.Tile.WALL or door in doors:
				continue
			if Palette.is_passable(level.get_tile(beyond)) and reach[level.index_of(beyond)] >= 0:
				doors.append(door)
	return doors


static func _center(cells: Array[Vector2i]) -> Vector2i:
	var sum := Vector2.ZERO
	for c in cells:
		sum += Vector2(c)
	var mid := sum / cells.size()
	var best := cells[0]
	for c in cells:
		if Vector2(c).distance_squared_to(mid) < Vector2(best).distance_squared_to(mid):
			best = c
	return best
