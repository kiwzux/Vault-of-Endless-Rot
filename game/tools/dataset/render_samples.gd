extends SceneTree
## Картинка-сводка комнат датасета: строки — типы комнат, столбцы — биомы (для записки и проверки на глаз).
## Запуск: godot --headless --path game --script res://tools/dataset/render_samples.gd -- --out=C:/путь/samples.png [--seed=1]

const CELL_PX := 6
const GAP := 8


func _init() -> void:
	var out := "user://dataset_samples.png"
	var offset := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--seed="):
			offset = int(arg.trim_prefix("--seed="))
	var size := Palette.map_size()
	var map_px := size * CELL_PX
	var types := Palette.room_types().size()
	var biomes := Palette.biomes().size()
	var image := Image.create(biomes * (map_px + GAP) + GAP, types * (map_px + GAP) + GAP, false, Image.FORMAT_RGB8)
	image.fill(Color(0.1, 0.1, 0.1))
	var validator := LevelValidator.new()
	for t in types:
		for b in biomes:
			var seed_value := DatasetGenerators.class_seed(t, b, offset)
			var level := DatasetGenerators.generate(t, b, seed_value)
			while not validator.validate(level).valid:
				seed_value += 1
				level = DatasetGenerators.generate(t, b, seed_value)
			var origin := Vector2i(GAP + b * (map_px + GAP), GAP + t * (map_px + GAP))
			for y in size:
				for x in size:
					image.fill_rect(Rect2i(origin + Vector2i(x, y) * CELL_PX, Vector2i(CELL_PX, CELL_PX)),
							Palette.color(level.get_tile(Vector2i(x, y))))
	image.save_png(out)
	print("Строки: ", Palette.room_types(), "  столбцы: ", Palette.biomes(), "  → ", ProjectSettings.globalize_path(out))
	quit(0)
