@tool
class_name Palette
extends RefCounted
## Единая палитра тайлов (ФТ-02, НФТ-06). Источник истины — res://models/palette.json, его же читает ml/.
## Порядок enum Tile обязан совпадать с id в JSON — проверяется при загрузке.

const PATH := "res://models/palette.json"

enum Tile { VOID, FLOOR, WALL, HAZARD, RUBBLE, PLAYER_SPAWN, EXIT, ENEMY_SPAWN, CHEST, FOUNTAIN, STATUE, OBELISK }

static var _loaded := false
static var _map_size := 32
static var _tile_size := 96
static var _art_tile_size := 32
static var _names := PackedStringArray()
static var _passable := PackedByteArray()
static var _marker := PackedByteArray()
static var _colors := PackedColorArray()
static var _biomes := PackedStringArray()
static var _room_types := PackedStringArray()


static func class_count() -> int:
	_ensure_loaded()
	return _names.size()


static func is_valid(id: int) -> bool:
	return id >= 0 and id < class_count()


static func is_passable(id: int) -> bool:
	_ensure_loaded()
	return _passable[id] == 1


static func is_marker(id: int) -> bool:
	_ensure_loaded()
	return _marker[id] == 1


static func name_of(id: int) -> String:
	_ensure_loaded()
	return _names[id]


static func color(id: int) -> Color:
	_ensure_loaded()
	return _colors[id]


static func map_size() -> int:
	_ensure_loaded()
	return _map_size


## Размер логического тайла (клетки сетки модели) в мире, px. Сетка модели — 32×32 (ОГР-05),
## а мир большой за счёт крупной клетки: 32 × 96 = 3072 px.
static func tile_size() -> int:
	_ensure_loaded()
	return _tile_size


## Размер тайла графики, px (как в HoMM3). Логический тайл рисуется блоком
## (tile_size / art_tile_size)² = 3×3 таких тайлов.
static func art_tile_size() -> int:
	_ensure_loaded()
	return _art_tile_size


static func biomes() -> PackedStringArray:
	_ensure_loaded()
	return _biomes


static func room_types() -> PackedStringArray:
	_ensure_loaded()
	return _room_types


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		push_error("Palette: не удалось прочитать %s" % PATH)
		return
	_map_size = int(parsed["map_size"])
	_tile_size = int(parsed["tile_size"])
	_art_tile_size = int(parsed.get("art_tile_size", _tile_size))
	assert(_tile_size % _art_tile_size == 0, "Palette: tile_size должен делиться на art_tile_size")
	_biomes = PackedStringArray(parsed["biomes"])
	_room_types = PackedStringArray(parsed["room_types"])
	var enum_names: Array = Tile.keys()
	var classes: Array = parsed["classes"]
	assert(classes.size() == enum_names.size(), "Palette: число классов в JSON не совпадает с enum Tile")
	for i in classes.size():
		var entry: Dictionary = classes[i]
		assert(int(entry["id"]) == i and entry["name"] == enum_names[i],
				"Palette: класс %d в JSON не совпадает с enum Tile" % i)
		_names.append(entry["name"])
		_passable.append(1 if entry["passable"] else 0)
		_marker.append(1 if entry["marker"] else 0)
		_colors.append(Color.html(entry["color"]))
	_loaded = true
