@tool
class_name LevelBuilder
extends RefCounted
## Строит TileMapLayer из LevelData. Метки (спавн, сундуки, портал...) кладутся на отдельный слой,
## под ними — пол. Объекты по меткам создаёт игровой код хоста, не билдер.
##
## Логический слой (ground/markers) — клетка 96 px, атлас-координаты тайла = (id, 0), физика по клеткам.
## Его читают датасет, коллизии и отладка, поэтому его TileSet простой — из цветов палитры.
## Картинку уровня рисует отдельный слой art (LevelArt, тайлы 32 px), если он передан.

const SOURCE_ID := 0

static var _placeholder_tileset: TileSet


static func build(level: LevelData, ground: TileMapLayer, markers: TileMapLayer, art: TileMapLayer = null) -> void:
	var tileset := placeholder_tileset()
	ground.tile_set = tileset
	markers.tile_set = tileset
	ground.clear()
	markers.clear()
	for y in level.size:
		for x in level.size:
			var cell := Vector2i(x, y)
			var id := level.get_tile(cell)
			if Palette.is_marker(id):
				ground.set_cell(cell, SOURCE_ID, Vector2i(Palette.Tile.FLOOR, 0))
				markers.set_cell(cell, SOURCE_ID, Vector2i(id, 0))
			else:
				ground.set_cell(cell, SOURCE_ID, Vector2i(id, 0))
	_build_bounds(ground, level.size * Palette.tile_size())
	if art != null:
		LevelArt.build(level, art)


## Невидимые стены по краю карты: у сгенерированной карты край может быть проходимым,
## а уйти за пределы уровня нельзя. Тайлы при этом не меняются.
static func _build_bounds(ground: TileMapLayer, extent: int) -> void:
	var bounds := ground.get_node_or_null(^"Bounds") as StaticBody2D
	if bounds == null:
		bounds = StaticBody2D.new()
		bounds.name = &"Bounds"
		bounds.collision_layer = PhysicsLayers.WORLD
		bounds.collision_mask = 0
		ground.add_child(bounds)
		for i in 4:
			var shape := CollisionShape2D.new()
			shape.shape = WorldBoundaryShape2D.new()
			bounds.add_child(shape)
	# Нормаль направлена внутрь карты; distance — смещение прямой вдоль нормали.
	var sides := [[Vector2.DOWN, 0.0], [Vector2.UP, -extent], [Vector2.RIGHT, 0.0], [Vector2.LEFT, -extent]]
	for i in 4:
		var boundary: WorldBoundaryShape2D = (bounds.get_child(i) as CollisionShape2D).shape
		boundary.normal = sides[i][0]
		boundary.distance = sides[i][1]


static func placeholder_tileset() -> TileSet:
	if _placeholder_tileset:
		return _placeholder_tileset
	var px := Palette.tile_size()
	var art := Palette.art_tile_size()
	var count := Palette.class_count()
	var image := Image.create(px * count, px, false, Image.FORMAT_RGBA8)
	for id in count:
		var c := Palette.color(id)
		if Palette.is_marker(id):
			# Метка — рамка: в отладочной сборке слой меток лежит поверх графики и не закрывает её.
			image.fill_rect(Rect2i(id * px + 4, 4, px - 8, px - 8), c)
			image.fill_rect(Rect2i(id * px + 10, 10, px - 20, px - 20), Color.TRANSPARENT)
			continue
		for sy in range(0, px, art):
			for sx in range(0, px, art):
				image.fill_rect(Rect2i(id * px + sx, sy, art, art), c.darkened(0.3))
				image.fill_rect(Rect2i(id * px + sx + 1, sy + 1, art - 2, art - 2), c)

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(px, px)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, PhysicsLayers.WORLD)
	tileset.set_physics_layer_collision_mask(0, 0)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(px, px)
	tileset.add_source(source, SOURCE_ID)

	var half := px / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half),
	])
	for id in count:
		var coords := Vector2i(id, 0)
		source.create_tile(coords)
		if not Palette.is_passable(id):
			var data := source.get_tile_data(coords, 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, square)

	_placeholder_tileset = tileset
	return tileset
