class_name SanctuaryMap
extends RefCounted
## Зал Убежища (шаг 10.3): постоянная карта 16×16 (ОГР-05) и места станций. С 17.10.2026 — тронный зал замка
## в духе Diablo: свой атлас «castle» (art/gen_tileset.py — каменные плиты, кладка с факелами, знамёнами и витражами).
## Это не генератор (ОГР-02): зал всегда один и тот же, как TestLevel; уровни забега по-прежнему создаёт CVAE.
## Карта рисуется тем же LevelBuilder/LevelArt, что и уровни, и даёт стены для физики героя.

const SIZE := 16
const BIOME := "flooded_crypt"
## Облик зала (LevelData.art_style): атлас res://assets/tiles/castle.png.
const ART_STYLE := "castle"
## Пол зала: клетки x 4..11, y 5..9 (8×5 логических клеток по 96 px — чуть больше экрана), вокруг — стена.
const HALL := Rect2i(4, 5, 8, 5)

## Станции: id → место в клетках (дробное: станции стоят у стен, а не в центрах клеток). С шага 11.12 реквизит
## крупный: огненный портал — у северной стены справа от статуй, стол кооператива — у южной, доска и летопись —
## у западной, алтарь — у восточной; костёр — в центре зала, герой появляется перед ним.
const STATIONS := {
	&"altar": Vector2(11.15, 8.0),
	&"board": Vector2(4.8, 6.45),
	&"chronicle": Vector2(4.85, 8.95),
	&"gate": Vector2(10.85, 5.95),
	&"war_table": Vector2(9.45, 9.5),
	&"exit": Vector2(6.6, 9.95),
}
## Статуи классов (Зал героев) — вдоль северной стены через пол-клетки, по порядку DataRegistry.HEROES.
const STATUE_ROW := 5.4
const STATUE_STEP := 0.5
const STATUE_CENTER_X := 8.0
const SPAWN := Vector2(8.0, 8.55)
const FIRE := Vector2(8.0, 7.55)
## Тронный зал замка (17.10.2026): ковровая дорожка по оси зала — от статуй к южной стене (полуширина в px мира).
const CARPET_TOP := Vector2(8.0, 5.75)
const CARPET_BOTTOM := Vector2(8.0, 10.0)
const CARPET_HALF_WIDTH := 30.0
## Колонны и доспехи на стойках: [id реквизита hub_props, место в клетках]. Проходы к станциям свободны.
const DECOR := [
	[&"pillar", Vector2(5.9, 6.6)], [&"pillar", Vector2(10.1, 6.6)],
	[&"pillar", Vector2(5.9, 8.9)], [&"pillar", Vector2(10.1, 8.9)],
	[&"armor", Vector2(4.55, 5.3)], [&"armor", Vector2(11.55, 6.75)],
]


static func make() -> LevelData:
	var level := LevelData.create_empty(SIZE, Palette.Tile.VOID)
	level.biome = maxi(Palette.biomes().find(BIOME), 0)
	level.model_hash = "sanctuary"
	level.art_style = ART_STYLE
	for y in range(HALL.position.y - 1, HALL.end.y + 1):
		for x in range(HALL.position.x - 1, HALL.end.x + 1):
			var inside := HALL.has_point(Vector2i(x, y))
			level.set_tile(Vector2i(x, y), Palette.Tile.FLOOR if inside else Palette.Tile.WALL)
	for cell: Vector2i in [Vector2i(5, 9), Vector2i(11, 7), Vector2i(6, 5)]:
		level.set_tile(cell, Palette.Tile.RUBBLE)
	return level


## Место в клетках (дробное) → пиксели.
static func point(cells: Vector2) -> Vector2:
	return cells * Palette.tile_size()


static func statue_point(index: int, count: int) -> Vector2:
	return point(Vector2(STATUE_CENTER_X + (index - (count - 1) / 2.0) * STATUE_STEP, STATUE_ROW))
