@tool
class_name LevelData
extends RefCounted
## Контракт уровня между генератором, движком и сетью (ФТ-15, DESIGN 5.2).
## Формат меняет только оркестратор; при изменении поднять FORMAT_VERSION.

const FORMAT_VERSION := 1
const INVALID_CELL := Vector2i(-1, -1)
const ALLOWED_SIZES: Array[int] = [16, 32]  # ОГР-05
const MAX_RAW_BYTES := 64 * 1024

var size: int = 32
var biome: int = 0
var room_type: int = 0
var gen_seed: int = 0
var model_hash: String = ""
## Облик графики не по биому (атлас res://assets/tiles/<art_style>.png): у постоянных карт вроде Убежища («castle»).
## Пусто — по биому. По сети не передаётся: уровни забега рисуются по биому.
var art_style: String = ""
## size*size id тайлов из палитры, построчно (индекс = y * size + x).
var tiles := PackedByteArray()
## Квантованная вероятность ENEMY_SPAWN из выхода модели, 0..255 (ФТ-03).
var spawn_weights := PackedByteArray()


static func create_empty(p_size: int, fill: int = Palette.Tile.VOID) -> LevelData:
	var level := LevelData.new()
	level.size = p_size
	level.tiles.resize(p_size * p_size)
	level.tiles.fill(fill)
	level.spawn_weights.resize(p_size * p_size)
	level.spawn_weights.fill(0)
	return level


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size and cell.y < size


func index_of(cell: Vector2i) -> int:
	return cell.y * size + cell.x


func get_tile(cell: Vector2i) -> int:
	return tiles[index_of(cell)]


func set_tile(cell: Vector2i, id: int) -> void:
	tiles[index_of(cell)] = id


func get_spawn_weight(cell: Vector2i) -> int:
	return spawn_weights[index_of(cell)]


func set_spawn_weight(cell: Vector2i, weight: int) -> void:
	spawn_weights[index_of(cell)] = clampi(weight, 0, 255)


@warning_ignore("integer_division")
func find_cells(id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in tiles.size():
		if tiles[i] == id:
			result.append(Vector2i(i % size, i / size))
	return result


@warning_ignore("integer_division")
func find_first(id: int) -> Vector2i:
	var i := tiles.find(id)
	return INVALID_CELL if i == -1 else Vector2i(i % size, i / size)


func to_bytes() -> PackedByteArray:
	var payload := {
		"v": FORMAT_VERSION,
		"size": size,
		"biome": biome,
		"room_type": room_type,
		"gen_seed": gen_seed,
		"model_hash": model_hash,
		"tiles": tiles,
		"spawn_weights": spawn_weights,
	}
	return var_to_bytes(payload).compress(FileAccess.COMPRESSION_DEFLATE)


## Возвращает null, если пакет повреждён или не соответствует контракту.
## Данные приходят от другого участника сессии, поэтому проверяется всё.
static func from_bytes(bytes: PackedByteArray) -> LevelData:
	var raw := bytes.decompress_dynamic(MAX_RAW_BYTES, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return null
	var payload: Variant = bytes_to_var(raw)
	if not (payload is Dictionary) or payload.get("v") != FORMAT_VERSION:
		return null
	var level := LevelData.new()
	level.size = payload.get("size", 0)
	level.biome = payload.get("biome", -1)
	level.room_type = payload.get("room_type", -1)
	level.gen_seed = payload.get("gen_seed", 0)
	level.model_hash = payload.get("model_hash", "")
	level.tiles = payload.get("tiles", PackedByteArray())
	level.spawn_weights = payload.get("spawn_weights", PackedByteArray())
	return level if level.is_valid() else null


func is_valid() -> bool:
	if size not in ALLOWED_SIZES:
		return false
	if tiles.size() != size * size or spawn_weights.size() != size * size:
		return false
	if biome < 0 or biome >= Palette.biomes().size():
		return false
	if room_type < 0 or room_type >= Palette.room_types().size():
		return false
	for id in tiles:
		if not Palette.is_valid(id):
			return false
	return true


## SHA-256 карты и точек спавна: сверяется у всех участников сессии (ФТ-15).
func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(tiles)
	ctx.update(spawn_weights)
	return ctx.finish().hex_encode()
