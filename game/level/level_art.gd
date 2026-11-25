@tool
class_name LevelArt
extends RefCounted
## Графический слой уровня (DESIGN 4, П-6): логическая клетка 96 px рисуется блоком 3×3 тайлов графики по 32 px мира.
## Текстура тайла детальнее мира (шаг 9: 64 px на 32 px мира, как листы героев и врагов): слой уменьшен до размера
## мира (scale) и сглаживается, как SheetLayout, — в окне 1280×720 тайл ложится на экран пиксель в пиксель.
## Тайл выбирается по соседям: верх стены и толща породы (VOID), вода — blob-наборы по 47 тайлов; у стены,
## южнее которой проход, две нижние строки блока — её лицевая сторона; на полу — тени от стен.
## Слой только рисует: физика, BFS и датасет работают с логическим слоем Ground (атлас (id, 0)).
## Атлас и раскладку генерирует art/gen_tileset.py → res://assets/tiles/<биом>.png + <биом>.json.

const SOURCE_ID := 0
const TILES_DIR := "res://assets/tiles/"
## Атлас для биома, у которого своего нет: тёмный склеп ближе всего по духу.
const FALLBACK_BIOME := "flooded_crypt"
## Доля тайлов с мусором в клетке RUBBLE, %.
const RUBBLE_PERCENT := 60
## Соседи в порядке битов маски, как в art/gen_tileset.py: N, NE, E, SE, S, SW, W, NW.
const NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
const PEERING := [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER]
## Terrain-наборы тайлсета: ключ раскладки и цвет кисти в редакторе.
const TERRAINS := {"wall_cap": Color(0.54, 0.48, 0.38), "void_cap": Color(0.1, 0.08, 0.07), "water": Color(0.24, 0.42, 0.29)}

## Вид тайла графики. Лицевая сторона — две строки: верхняя (UP) и нижняя (LOW).
enum Kind { FLOOR, RUBBLE, WATER, WALL_CAP, WALL_FACE_UP, WALL_FACE_LOW, VOID_CAP, VOID_FACE_UP, VOID_FACE_LOW }

const FACES := (1 << Kind.WALL_FACE_UP) | (1 << Kind.WALL_FACE_LOW) | (1 << Kind.VOID_FACE_UP) | (1 << Kind.VOID_FACE_LOW)
const CAPS := (1 << Kind.WALL_CAP) | (1 << Kind.VOID_CAP)
const SOLID := FACES | CAPS

## Имя биома → {"layout": раскладка атласа, "tileset": TileSet}.
static var _styles := {}


## Нарисовать уровень на слое графики. Детерминировано: у хоста и клиентов из одной LevelData — одна картинка.
@warning_ignore("integer_division")
static func build(level: LevelData, layer: TileMapLayer) -> void:
	var style := style_of(level)
	var columns := int(style["layout"]["columns"])
	var n := level.size * blocks()
	var indices := atlas_indices(level, style["layout"])
	layer.tile_set = style["tileset"]
	var detail := float(style["layout"]["tile_size"]) / Palette.art_tile_size()
	layer.scale = Vector2.ONE / detail
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if detail > 1.0 else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	layer.clear()
	for i in indices.size():
		layer.set_cell(Vector2i(i % n, i / n), SOURCE_ID, Vector2i(indices[i] % columns, indices[i] / columns))


## Сколько тайлов графики по стороне логической клетки (96 / 32 = 3).
@warning_ignore("integer_division")
static func blocks() -> int:
	return Palette.tile_size() / Palette.art_tile_size()


## Облик карты: свой стиль (LevelData.art_style, Убежище — «castle»), иначе по биому.
static func style_of(level: LevelData) -> Dictionary:
	return style_named(level.art_style) if level.art_style != "" else style_for(level.biome)


## Раскладка и TileSet биома; если атласа биома нет — запасной (FALLBACK_BIOME).
static func style_for(biome: int) -> Dictionary:
	var names := Palette.biomes()
	return style_named(names[biome] if biome >= 0 and biome < names.size() else FALLBACK_BIOME)


## Раскладка и TileSet атласа по имени (биом или отдельный стиль); нет атласа — запасной (FALLBACK_BIOME).
static func style_named(style_name: String) -> Dictionary:
	var biome_name := style_name
	if not FileAccess.file_exists(TILES_DIR + biome_name + ".json"):
		biome_name = FALLBACK_BIOME
	if not _styles.has(biome_name):
		var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TILES_DIR + biome_name + ".json"))
		var texture: Texture2D = load(TILES_DIR + String(layout["texture"]))
		_styles[biome_name] = {"layout": layout, "tileset": _make_tileset(layout, texture)}
	return _styles[biome_name]


## Вид каждого тайла графики (n × n, построчно): что за клетка и какая часть стены.
static func classify(level: LevelData) -> PackedByteArray:
	var k := blocks()
	var n := level.size * k
	var kinds := PackedByteArray()
	kinds.resize(n * n)
	for y in level.size:
		for x in level.size:
			var cell := Vector2i(x, y)
			var id := level.get_tile(cell)
			var below := cell + Vector2i.DOWN
			# Лицевая сторона видна, если южнее стены проход; у нижнего края карты её нет.
			var face := _is_solid(id) and level.in_bounds(below) and not _is_solid(level.get_tile(below))
			for sy in k:
				var kind := _kind(id, face, sy - (k - 2))
				for sx in k:
					kinds[(y * k + sy) * n + x * k + sx] = kind
	return kinds


## Индексы тайлов атласа для каждого тайла графики (n × n, построчно; у воды — первый кадр).
@warning_ignore("integer_division")
static func atlas_indices(level: LevelData, layout: Dictionary) -> PackedInt32Array:
	var k := blocks()
	var n := level.size * k
	var kinds := classify(level)
	var lut: Array = layout["blob_lut"]
	var floor_info: Dictionary = layout["floor"]
	var plain := int(floor_info["plain"])
	var floor_bases := plain + int(floor_info["rubble"])
	var water: Dictionary = layout["water"]
	var result := PackedInt32Array()
	result.resize(n * n)
	for ay in n:
		for ax in n:
			var kind := kinds[ay * n + ax]
			var h := _hash(ax, ay, level.gen_seed)
			var index: int
			if kind == Kind.FLOOR or kind == Kind.RUBBLE:
				var shadow := 0
				if _is(kinds, n, ax, ay - 1, FACES):
					shadow |= 1
				if _is(kinds, n, ax - 1, ay, SOLID):
					shadow |= 2
				if _is(kinds, n, ax + 1, ay, SOLID):
					shadow |= 4
				var base := h % plain
				if kind == Kind.RUBBLE and (h >> 8) % 100 < RUBBLE_PERCENT:
					base = plain + (h >> 4) % int(floor_info["rubble"])
				index = int(floor_info["start"]) + shadow * floor_bases + base
			elif kind == Kind.WALL_CAP:
				index = _blob(layout["wall_cap"], lut, _mask(kinds, n, ax, ay, 1 << Kind.WALL_CAP), h)
			elif kind == Kind.VOID_CAP:
				# Толща породы не обводится у стены: кромку там рисует верх стены.
				index = _blob(layout["void_cap"], lut, _mask(kinds, n, ax, ay, CAPS), h)
			elif kind == Kind.WATER:
				var mask := _mask(kinds, n, ax, ay, 1 << Kind.WATER)
				if mask == 255:
					var interior: Array = water["interior"]
					index = int(interior[h % interior.size()])
				else:
					index = int(water["start"]) + int(lut[mask]) * int(water["frames"])
			else:
				var info: Dictionary = layout["wall_face"] if kind <= Kind.WALL_FACE_LOW else layout["void_face"]
				var row := 0 if kind == Kind.WALL_FACE_UP or kind == Kind.VOID_FACE_UP else 1
				var left := _face_end(kinds, n, ax - 1, ay)
				var right := _face_end(kinds, n, ax + 1, ay)
				var pair: Array
				if left != "":
					pair = info["l_" + left]
				elif right != "":
					pair = info["r_" + right]
				else:
					# Вариант выбирается по столбцу и клетке, чтобы верх и низ лицевой стороны совпали.
					var mids: Array = info["mid"]
					pair = mids[_hash(ax, ay / k, level.gen_seed) % mids.size()]
				index = int(pair[row])
			result[ay * n + ax] = index
	return result


static func _is_solid(id: int) -> bool:
	return id == Palette.Tile.WALL or id == Palette.Tile.VOID


## face_row — номер строки блока относительно начала лицевой стороны (0 — верх, 1 — низ, < 0 — над ней).
static func _kind(id: int, face: bool, face_row: int) -> int:
	if id == Palette.Tile.WALL:
		return Kind.WALL_FACE_UP + face_row if face and face_row >= 0 else Kind.WALL_CAP
	if id == Palette.Tile.VOID:
		return Kind.VOID_FACE_UP + face_row if face and face_row >= 0 else Kind.VOID_CAP
	if id == Palette.Tile.HAZARD:
		return Kind.WATER
	if id == Palette.Tile.RUBBLE:
		return Kind.RUBBLE
	return Kind.FLOOR


## Вид соседа входит в набор kinds_bits; за краем карты — нет.
static func _is(kinds: PackedByteArray, n: int, x: int, y: int, kinds_bits: int) -> bool:
	return x >= 0 and y >= 0 and x < n and y < n and (kinds_bits >> kinds[y * n + x]) & 1 == 1


## Маска «свой сосед» для blob-набора; за краем карты сосед считается своим (кромки по краю нет).
static func _mask(kinds: PackedByteArray, n: int, x: int, y: int, same_bits: int) -> int:
	var mask := 0
	for i in 8:
		var p := Vector2i(x, y) + NEIGHBORS[i]
		if p.x < 0 or p.y < 0 or p.x >= n or p.y >= n or (same_bits >> kinds[p.y * n + p.x]) & 1 == 1:
			mask |= 1 << i
	return mask


static func _blob(info: Dictionary, lut: Array, mask: int, h: int) -> int:
	if mask == 255:
		var interior: Array = info["interior"]
		return int(interior[h % interior.size()])
	return int(info["start"]) + int(lut[mask])


## Конец лицевой стороны: "" — продолжается, "in" — упирается в верх стены, "out" — угол стены.
static func _face_end(kinds: PackedByteArray, n: int, x: int, y: int) -> String:
	if x < 0 or x >= n:
		return ""
	var bit := 1 << kinds[y * n + x]
	if bit & FACES:
		return ""
	return "in" if bit & CAPS else "out"


## Детерминированный хэш клетки для выбора вариантов тайла (без переполнения int64).
static func _hash(x: int, y: int, salt: int) -> int:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h ^= salt & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 16)) * 1103515245) & 0x7fffffff
	return h ^ (h >> 15)


@warning_ignore("integer_division")
static func _make_tileset(layout: Dictionary, texture: Texture2D) -> TileSet:
	var size := int(layout["tile_size"])
	var columns := int(layout["columns"])
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(size, size)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(size, size)
	tileset.add_source(source, SOURCE_ID)
	for i in int(layout["static_count"]):
		source.create_tile(Vector2i(i % columns, i / columns))
	# Жидкость анимирована: кадры тайла идут подряд в строке атласа. Blob-набор + варианты середины.
	var water: Dictionary = layout["water"]
	var frames := int(water["frames"])
	var animated := {}
	for t in int(water["count"]):
		animated[int(water["start"]) + t * frames] = true
	for i in water["interior"]:
		animated[int(i)] = true
	for i: int in animated:
		var coords := Vector2i(i % columns, i / columns)
		source.create_tile(coords)
		source.set_tile_animation_frames_count(coords, frames)
		for f in frames:
			source.set_tile_animation_frame_duration(coords, f, float(water["frame_duration"]))

	# Blob-тайлы размечены битами соседства: в редакторе их можно рисовать terrain-кистью.
	tileset.add_terrain_set()
	tileset.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	var masks: Array = layout["blob_masks"]
	for key: String in TERRAINS:
		var terrain := tileset.get_terrains_count(0)
		tileset.add_terrain(0)
		tileset.set_terrain_name(0, terrain, key)
		tileset.set_terrain_color(0, terrain, TERRAINS[key])
		var step := frames if key == "water" else 1
		for b in masks.size():
			var i := int(layout[key]["start"]) + b * step
			var data := source.get_tile_data(Vector2i(i % columns, i / columns), 0)
			data.terrain_set = 0
			data.terrain = terrain
			for bit in 8:
				if int(masks[b]) & (1 << bit):
					data.set_terrain_peering_bit(PEERING[bit], terrain)
	return tileset
