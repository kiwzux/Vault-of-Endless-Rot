extends SceneTree
## Картинка-сводка карт, созданных моделью через полный конвейер игры (CVAE → декодер → валидатор → попытки):
## строки — типы комнат, столбцы — биомы. Рамка: зелёная — принята с 1-й попытки, жёлтая — со 2–5-й,
## красная — все попытки отбракованы (показана последняя).
## Запуск: godot --headless --path game --script res://tools/render_generated.gd -- --out=C:/путь/gen.png
##         [--model=res://models/levelgen.onnx] [--seed=1]

const CELL_PX := 6
const GAP := 10
const BORDER := 3


func _init() -> void:
	var out := "user://generated.png"
	var model := LevelGenerator.DEFAULT_MODEL
	var run_seed := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--model="):
			model = arg.trim_prefix("--model=")
		elif arg.begins_with("--seed="):
			run_seed = int(arg.trim_prefix("--seed="))
	var gen := LevelGenerator.new(model)
	if not gen.is_ready():
		printerr("Генератор не готов: ", gen.get_error())
		quit(1)
		return
	var size := Palette.map_size()
	var map_px := size * CELL_PX
	var types := Palette.room_types().size()
	var biomes := Palette.biomes().size()
	var image := Image.create(biomes * (map_px + GAP) + GAP, types * (map_px + GAP) + GAP, false, Image.FORMAT_RGB8)
	image.fill(Color(0.1, 0.1, 0.1))
	for t in types:
		for b in biomes:
			var request := LevelGenerator.Request.new()
			request.run_seed = run_seed
			request.level_index = t * biomes + b
			request.biome = b
			request.room_type = t
			var result := gen.generate(request)
			var level := result.level
			var frame := Color(0.85, 0.2, 0.15)
			if level != null:
				frame = Color(0.3, 0.8, 0.3) if result.attempts.size() == 1 else Color(0.9, 0.8, 0.2)
			else:
				var last := result.attempts[-1]
				level = gen.reproduce(last)
			var origin := Vector2i(GAP + b * (map_px + GAP), GAP + t * (map_px + GAP))
			image.fill_rect(Rect2i(origin - Vector2i(BORDER, BORDER), Vector2i(map_px, map_px) + Vector2i(2 * BORDER, 2 * BORDER)), frame)
			for y in size:
				for x in size:
					image.fill_rect(Rect2i(origin + Vector2i(x, y) * CELL_PX, Vector2i(CELL_PX, CELL_PX)),
							Palette.color(level.get_tile(Vector2i(x, y))))
	image.save_png(out)
	print("Строки: ", Palette.room_types(), "  столбцы: ", Palette.biomes(), "  → ", ProjectSettings.globalize_path(out))
	quit(0)
