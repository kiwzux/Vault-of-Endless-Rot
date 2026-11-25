class_name TestLevel
extends RefCounted
## Фиксированная тестовая арена 32×32 для разработки механик, пока нет обученной модели.
## Это не генератор (ОГР-02): карта всегда одна и та же и уходит из игрового цикла после интеграции CVAE.

const MODEL_HASH := "test-fixture"


static func make() -> LevelData:
	var size := Palette.map_size()
	var level := LevelData.create_empty(size, Palette.Tile.FLOOR)
	level.model_hash = MODEL_HASH

	_fill(level, Rect2i(0, 0, size, 1), Palette.Tile.WALL)
	_fill(level, Rect2i(0, size - 1, size, 1), Palette.Tile.WALL)
	_fill(level, Rect2i(0, 0, 1, size), Palette.Tile.WALL)
	_fill(level, Rect2i(size - 1, 0, 1, size), Palette.Tile.WALL)
	for corner: Vector2i in [Vector2i(8, 8), Vector2i(22, 8), Vector2i(8, 22), Vector2i(22, 22)]:
		_fill(level, Rect2i(corner, Vector2i(2, 2)), Palette.Tile.WALL)
	_fill(level, Rect2i(13, 21, 6, 3), Palette.Tile.HAZARD)
	for cell: Vector2i in [Vector2i(5, 12), Vector2i(6, 13), Vector2i(25, 18), Vector2i(19, 5), Vector2i(11, 27)]:
		level.set_tile(cell, Palette.Tile.RUBBLE)

	level.set_tile(Vector2i(16, 15), Palette.Tile.PLAYER_SPAWN)
	level.set_tile(Vector2i(28, 3), Palette.Tile.EXIT)
	level.set_tile(Vector2i(6, 16), Palette.Tile.CHEST)
	level.set_tile(Vector2i(16, 6), Palette.Tile.FOUNTAIN)
	level.set_tile(Vector2i(16, 27), Palette.Tile.STATUE)
	level.set_tile(Vector2i(26, 16), Palette.Tile.OBELISK)
	for cell: Vector2i in [Vector2i(3, 3), Vector2i(3, 28), Vector2i(28, 28)]:
		level.set_tile(cell, Palette.Tile.ENEMY_SPAWN)
		level.set_spawn_weight(cell, 255)
	return level


static func _fill(level: LevelData, rect: Rect2i, id: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			level.set_tile(Vector2i(x, y), id)
