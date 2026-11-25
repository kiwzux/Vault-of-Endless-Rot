class_name LevelLights
extends RefCounted
## Неподвижный свет уровня (шаг 11.8): огонь, нарисованный на тайлах (факелы, витражи, руны, свечи, угли, кристаллы —
## список "lights" раскладки атласа, art/gen_tileset.py), горящие предметы обстановки (DecorPlan, шаг 11.29)
## и свечение опасных клеток биома (BiomeData.hazard_light).
## Считается из LevelData у каждого участника — у хоста и клиентов одинаково, как и картинка LevelArt.

var positions := PackedVector2Array()
## Цвет × энергия.
var colors := PackedColorArray()
var radii := PackedFloat32Array()
## Фаза мерцания: у соседних факелов огонь дрожит не в такт.
var phases := PackedFloat32Array()


func size() -> int:
	return positions.size()


@warning_ignore("integer_division")
static func collect(level: LevelData) -> LevelLights:
	var result := LevelLights.new()
	if level == null:
		return result
	var layout: Dictionary = LevelArt.style_of(level)["layout"]
	var by_index := {}
	for entry: Array in layout.get("lights", []):
		by_index[int(entry[0])] = entry
	if not by_index.is_empty():
		var indices := LevelArt.atlas_indices(level, layout)
		var n := level.size * LevelArt.blocks()
		var art := float(Palette.art_tile_size())
		for i in indices.size():
			var entry: Variant = by_index.get(indices[i])
			if entry == null:
				continue
			var at := Vector2(i % n, i / n) * art + Vector2(float(entry[4]), float(entry[5]))
			result._add(at, Color(String(entry[1])), float(entry[2]), float(entry[3]))
	# Шаг 11.29: горящие предметы обстановки (фонарь, канделябр, жаровня, кристаллы) — тоже неподвижный свет.
	for item: Dictionary in DecorPlan.of(level):
		var light := PropArt.light_of(item["id"])
		if not light.is_empty():
			var offset := Vector2(float(light[3]) * (-1.0 if item["flip"] else 1.0), float(light[4]))
			result._add(item["pos"] + offset, Color(String(light[0])), float(light[1]), float(light[2]))
	var biome := biome_of(level)
	if biome != null and biome.hazard_light.a > 0.0:
		var tile := float(Palette.tile_size())
		for y in level.size:
			for x in level.size:
				if level.get_tile(Vector2i(x, y)) == Palette.Tile.HAZARD:
					result._add((Vector2(x, y) + Vector2(0.5, 0.5)) * tile, biome.hazard_light, biome.hazard_light.a,
							biome.hazard_light_radius)
	return result


## Биом уровня (условие модели — номер в палитре); null — тестовая арена без данных биома.
static func biome_of(level: LevelData) -> BiomeData:
	var names := Palette.biomes()
	if level == null or level.biome < 0 or level.biome >= names.size():
		return null
	return DataRegistry.biome(StringName(names[level.biome]))


func _add(at: Vector2, color: Color, energy: float, radius: float) -> void:
	positions.append(at)
	colors.append(Color(color.r * energy, color.g * energy, color.b * energy))
	radii.append(radius)
	phases.append(fmod(at.x * 0.37 + at.y * 0.61, TAU))
