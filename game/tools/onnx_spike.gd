extends SceneTree
## Спайк моста ONNX Runtime ↔ Godot (ФТ-06): загрузка модели, инференс, воспроизводимость,
## обработка ошибок, работа из фонового потока, время инференса.
## Запуск: godot --headless --path game --script res://tools/onnx_spike.gd
## Модель-заготовку создаёт res://tools/make_spike_model.gd.

const MODEL := "res://models/spike/levelgen_spike.onnx"
const EXPECTED_RUNTIME := "1.30.0"
const Z_DIM := 32
const COND_DIM := 8
const TIMING_RUNS := 200
const TIME_LIMIT_MS := 500.0  # НФТ-01 — на весь цикл генерации; инференс должен быть много меньше
const TILE_CHARS := " .#~,@E!$FSO"  # символы классов палитры для текстового предпросмотра

var _failures := 0


func _init() -> void:
	if not ClassDB.class_exists(&"OnnxModel"):
		printerr("FAIL: класс OnnxModel не зарегистрирован — расширение addons/onnx_runtime не загрузилось")
		quit(1)
		return

	var version: String = ClassDB.class_call_static(&"OnnxModel", &"get_runtime_version")
	_check(version == EXPECTED_RUNTIME, "ONNX Runtime %s загружен из папки расширения (ожидается %s)" % [version, EXPECTED_RUNTIME])

	var model: RefCounted = ClassDB.instantiate(&"OnnxModel")
	_check(model.load(MODEL) == OK, "модель загружается из res:// через FileAccess")
	if not model.is_loaded():
		printerr("  ", model.get_last_error())
		quit(1)
		return

	_check(model.get_input_names() == PackedStringArray(["z", "cond"]), "входы z, cond")
	_check(model.get_output_names() == PackedStringArray(["probs"]), "выход probs")
	_check(model.get_input_shapes()["z"] == PackedInt64Array([1, Z_DIM]), "форма z = [1, 32]")
	var out_shape: PackedInt64Array = model.get_output_shapes()["probs"]
	_check(out_shape == PackedInt64Array([1, Palette.class_count(), 32, 32]),
			"форма probs = [1, %d, 32, 32] совпадает с палитрой (ФТ-02)" % Palette.class_count())
	_check(model.get_model_hash() == FileAccess.get_sha256(MODEL), "хэш модели для журнала (ФТ-17) = SHA-256 файла")

	var inputs := _inputs(12345, 0)
	var result: Dictionary = model.run(inputs)
	var probs: PackedFloat32Array = result.get("probs", PackedFloat32Array())
	_check(probs.size() == Palette.class_count() * 32 * 32, "инференс вернул %d значений" % probs.size())
	_check(_softmax_ok(probs), "в каждой клетке вероятности по каналам дают в сумме 1")
	var again: PackedFloat32Array = model.run(inputs)["probs"]
	_check(again == probs, "повторный запуск с тем же z даёт бит-в-бит тот же результат (ФТ-17)")
	var other: PackedFloat32Array = model.run(_inputs(777, 1))["probs"]
	_check(_argmax(other) != _argmax(probs), "другой z даёт другую карту")

	var threaded := {}
	var task := WorkerThreadPool.add_task(func() -> void: threaded["probs"] = model.run(inputs)["probs"])
	WorkerThreadPool.wait_for_task_completion(task)
	_check(threaded.get("probs") == probs, "инференс из WorkerThreadPool работает и совпадает (НФТ-05)")

	print("  ...проверки ошибок — ниже ожидаемые сообщения ERROR:")
	_check(model.run({"z": inputs["z"]}).is_empty() and model.get_last_error() != "", "нет входа → пустой результат и текст ошибки")
	_check(model.run({"z": PackedFloat32Array([1.0]), "cond": inputs["cond"]}).is_empty(), "неверный размер входа отклоняется")
	_check(model.run({"z": [0.0], "cond": inputs["cond"]}).is_empty(), "вход не PackedFloat32Array отклоняется")
	var broken: RefCounted = ClassDB.instantiate(&"OnnxModel")
	_check(broken.load("res://models/spike/missing.onnx") != OK, "несуществующий файл → ошибка, не падение")
	_check(broken.load("res://models/palette.json") != OK, "не-ONNX файл → ошибка, не падение")
	_check(broken.run(inputs).is_empty(), "run() до load() → ошибка, не падение")

	var times := PackedFloat64Array()
	for i in TIMING_RUNS:
		var started := Time.get_ticks_usec()
		model.run(_inputs(i, i % 4))
		times.append((Time.get_ticks_usec() - started) / 1000.0)
	times.sort()
	var average := 0.0
	for t in times:
		average += t / TIMING_RUNS
	print("  время инференса, мс: среднее %.3f, медиана %.3f, p95 %.3f, макс %.3f"
			% [average, times[TIMING_RUNS / 2], times[int(TIMING_RUNS * 0.95)], times[-1]])
	_check(times[-1] < TIME_LIMIT_MS, "даже худший запуск укладывается в бюджет НФТ-01 (%.0f мс)" % TIME_LIMIT_MS)

	print("  карта argmax для z(seed=12345), биом 0 (модель-заготовка со случайными весами):")
	_print_map(_argmax(probs))
	print("Провалено проверок: %d" % _failures)
	quit(1 if _failures > 0 else 0)


## z ~ N(0, I) из сида (как будет в генераторе), cond = one-hot биома + one-hot типа комнаты.
func _inputs(seed_value: int, biome: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var z := PackedFloat32Array()
	z.resize(Z_DIM)
	for i in Z_DIM:
		z[i] = rng.randfn(0.0, 1.0)
	var cond := PackedFloat32Array()
	cond.resize(COND_DIM)
	cond[biome] = 1.0
	cond[4] = 1.0
	return {"z": z, "cond": cond}


func _softmax_ok(probs: PackedFloat32Array) -> bool:
	var cells := 32 * 32
	for i in cells:
		var total := 0.0
		for c in Palette.class_count():
			total += probs[c * cells + i]
		if absf(total - 1.0) > 1e-4:
			return false
	return true


## ФТ-02: тайл клетки = канал с максимальной вероятностью.
func _argmax(probs: PackedFloat32Array) -> PackedByteArray:
	var cells := 32 * 32
	var tiles := PackedByteArray()
	tiles.resize(cells)
	for i in cells:
		var best := 0
		for c in range(1, Palette.class_count()):
			if probs[c * cells + i] > probs[best * cells + i]:
				best = c
		tiles[i] = best
	return tiles


func _print_map(tiles: PackedByteArray) -> void:
	for y in 32:
		var row := "    "
		for x in 32:
			row += TILE_CHARS[tiles[y * 32 + x]]
		print(row)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  OK   ", description)
	else:
		_failures += 1
		printerr("  FAIL ", description)
