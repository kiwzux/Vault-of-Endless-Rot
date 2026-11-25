extends SceneTree
## Картинка уровня с графикой биома без запуска игры: тайлы выбирает тот же LevelArt, что и в игре
## (у воды — первый кадр анимации).
## Запуск: godot --headless --path game --script res://tools/render_art.gd -- --out=C:/путь/art.png
##         [--model] [--biome=0] [--room=0] [--sample=1] [--region=x,y,w,h] [--scale=1]
## Без --model карта берётся из генератора датасета, с --model — из CVAE через полный конвейер, как в игре.
## --region — участок карты в логических клетках, --scale — целочисленное увеличение.


@warning_ignore("integer_division")
func _init() -> void:
	var out := "user://art.png"
	var use_model := false
	var biome := 0
	var room := 0
	var sample := 1
	var region := Rect2i()
	var scale := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--model":
			use_model = true
		elif arg.begins_with("--biome="):
			biome = int(arg.trim_prefix("--biome="))
		elif arg.begins_with("--room="):
			room = int(arg.trim_prefix("--room="))
		elif arg.begins_with("--sample="):
			sample = int(arg.trim_prefix("--sample="))
		elif arg.begins_with("--region="):
			var r := arg.trim_prefix("--region=").split(",")
			region = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		elif arg.begins_with("--scale="):
			scale = maxi(1, int(arg.trim_prefix("--scale=")))

	var level := _make_level(use_model, biome, room, sample)
	if level == null:
		quit(1)
		return
	if region.has_area():
		region = region.intersection(Rect2i(0, 0, level.size, level.size))
	else:
		region = Rect2i(0, 0, level.size, level.size)

	var style := LevelArt.style_for(level.biome)
	var layout: Dictionary = style["layout"]
	var columns := int(layout["columns"])
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(LevelArt.TILES_DIR + String(layout["texture"])))
	var indices := LevelArt.atlas_indices(level, layout)
	var art := int(layout["tile_size"])  # px текстуры тайла (детальнее мира)
	var k := LevelArt.blocks()
	var n := level.size * k
	var origin := region.position * k
	var image := Image.create(region.size.x * k * art, region.size.y * k * art, false, Image.FORMAT_RGBA8)
	for ay in range(origin.y, origin.y + region.size.y * k):
		for ax in range(origin.x, origin.x + region.size.x * k):
			var i := indices[ay * n + ax]
			image.blit_rect(atlas, Rect2i(Vector2i(i % columns, i / columns) * art, Vector2i(art, art)),
					(Vector2i(ax, ay) - origin) * art)
	if scale > 1:
		image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	image.save_png(out)
	print("%s, биом %s, тип %s, сид %d → %s" % ["CVAE" if use_model else "датасет", Palette.biomes()[level.biome],
			Palette.room_types()[level.room_type], level.gen_seed, ProjectSettings.globalize_path(out)])
	quit(0)


func _make_level(use_model: bool, biome: int, room: int, sample: int) -> LevelData:
	if not use_model:
		return DatasetGenerators.generate(room, biome, DatasetGenerators.class_seed(room, biome, sample))
	var gen := LevelGenerator.new(LevelGenerator.DEFAULT_MODEL)
	if not gen.is_ready():
		printerr("Генератор не готов: ", gen.get_error())
		return null
	var request := LevelGenerator.Request.new()
	request.run_seed = sample
	request.level_index = room * Palette.biomes().size() + biome
	request.biome = biome
	request.room_type = room
	var result := gen.generate(request)
	return result.level if result.level != null else gen.reproduce(result.attempts[-1])
