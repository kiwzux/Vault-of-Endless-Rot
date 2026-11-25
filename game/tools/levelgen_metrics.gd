extends SceneTree
## Протокол замеров генератора на 100 генерациях с фиксированными сидами (ЛР2, разделы 4.6 и 9.1):
##   НФТ-01 / ТК-05 — время цикла «вычисление + проверка» ≤ 500 мс (с учётом повторных попыток);
##   НФТ-03 / ТК-03 — ≥ 90 % локаций принимаются валидатором с 1–2 попытки;
##   НФТ-09 / ТК-18 — ≥ 90 % уникальных локаций (отличие ≥ 10 % тайлов от каждой другой); справочно — порог 20 % (CR-03).
## Запуск: godot --headless --path game --script res://tools/levelgen_metrics.gd [-- --model=res://... --count=100]
## Отчёт пишется в user://metrics/levelgen_<время>.json (данные для пояснительной записки).

const DEFAULT_COUNT := 100
const TIME_LIMIT_MS := 500.0
const PASS_RATE_MIN := 0.9
const UNIQUE_RATE_MIN := 0.9
const UNIQUE_DIFF := 0.10
const UNIQUE_DIFF_REFERENCE := 0.20


func _init() -> void:
	var args := _parse_args()
	var model_path: String = args.get("model", LevelGenerator.DEFAULT_MODEL)
	if not FileAccess.file_exists(model_path):
		model_path = "res://models/spike/levelgen_spike.onnx"
		print("Обученной модели нет — замер на модели-заготовке (цифры не для записки).")
	var count := int(args.get("count", DEFAULT_COUNT))
	var gen := LevelGenerator.new(model_path)
	if not gen.is_ready():
		printerr("Генератор не готов: ", gen.get_error())
		quit(1)
		return

	var times := PackedFloat64Array()
	var first_pass := 0
	var within_two := 0
	var failed := 0
	var maps: Array[PackedByteArray] = []
	var error_counts := {}
	var by_type := {}  # тип комнаты → {count, within_two, maps}
	for i in count:
		var request := LevelGenerator.make_request(i + 1, 0, i % Palette.biomes().size())
		var result := gen.generate(request)
		times.append(result.total_ms)
		var attempts := result.attempts.size()
		var type_name: String = Palette.room_types()[request.room_type]
		if not by_type.has(type_name):
			by_type[type_name] = {"count": 0, "within_two": 0, "maps": [] as Array[PackedByteArray]}
		by_type[type_name]["count"] += 1
		if result.level == null:
			failed += 1
		else:
			maps.append(result.level.tiles)
			by_type[type_name]["maps"].append(result.level.tiles)
			first_pass += 1 if attempts == 1 else 0
			within_two += 1 if attempts <= 2 else 0
			by_type[type_name]["within_two"] += 1 if attempts <= 2 else 0
		for record in result.attempts:
			for code: String in record.get("errors", []):
				error_counts[code] = error_counts.get(code, 0) + 1

	times.sort()
	var unique_10 := _unique_share(maps, UNIQUE_DIFF)
	var unique_20 := _unique_share(maps, UNIQUE_DIFF_REFERENCE)
	var pass_rate := float(within_two) / count
	var worst_ms := times[-1]
	var report := {
		"model_path": model_path,
		"model_hash": gen.model_hash,
		"count": count,
		"time_ms": {"median": times[count / 2], "p95": times[int(count * 0.95)], "max": worst_ms},
		"accepted_first_attempt": first_pass,
		"accepted_within_two": within_two,
		"failed_all_attempts": failed,
		"pass_rate_within_two": pass_rate,
		"unique_share_10pct": unique_10,
		"unique_share_20pct": unique_20,
		"rejection_reasons": error_counts,
	}

	print("Модель: %s (%s…)" % [model_path, gen.model_hash.left(12)])
	print("Генераций: %d, принято с 1-й попытки: %d, с 1–2: %d, отказ после 5: %d" % [count, first_pass, within_two, failed])
	print("Время цикла, мс: медиана %.2f, p95 %.2f, макс %.2f" % [times[count / 2], times[int(count * 0.95)], worst_ms])
	print("Причины отбраковки: ", error_counts)
	var type_report := {}
	for type_name: String in by_type:
		var stats: Dictionary = by_type[type_name]
		var row := {
			"count": stats["count"],
			"pass_rate_within_two": float(stats["within_two"]) / stats["count"],
			"unique_share_10pct_within_type": _unique_share(stats["maps"], UNIQUE_DIFF),
		}
		type_report[type_name] = row
		print("  %-6s: %2d генераций, принято с 1–2: %3.0f %%, уникальных внутри типа: %3.0f %%"
				% [type_name, row["count"], row["pass_rate_within_two"] * 100, row["unique_share_10pct_within_type"] * 100])
	report["by_room_type"] = type_report
	var all_ok := true
	all_ok = _verdict("НФТ-01 время цикла ≤ %.0f мс (макс %.2f)" % [TIME_LIMIT_MS, worst_ms], worst_ms <= TIME_LIMIT_MS) and all_ok
	all_ok = _verdict("НФТ-03 принято с 1–2 попытки ≥ 90 %% (%.0f %%)" % (pass_rate * 100), pass_rate >= PASS_RATE_MIN) and all_ok
	all_ok = _verdict("НФТ-09 уникальных при 10 %% ≥ 90 %% (%.0f %% из %d карт)" % [unique_10 * 100, maps.size()],
			unique_10 >= UNIQUE_RATE_MIN) and all_ok
	print("  справочно (CR-03): уникальных при 20 %% — %.0f %%" % (unique_20 * 100))

	var path := "user://metrics/levelgen_%s.json" % Time.get_datetime_string_from_system(true).replace(":", "-")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		print("Отчёт: ", ProjectSettings.globalize_path(path))
	quit(0 if all_ok else 1)


## НФТ-09: карта уникальна, если отличается от каждой другой карты выборки не менее чем на threshold тайлов.
func _unique_share(maps: Array[PackedByteArray], threshold: float) -> float:
	if maps.is_empty():
		return 0.0
	var min_diff := ceili(maps[0].size() * threshold)
	var unique := 0
	for i in maps.size():
		var is_unique := true
		for j in maps.size():
			if i != j and _diff(maps[i], maps[j], min_diff) < min_diff:
				is_unique = false
				break
		unique += 1 if is_unique else 0
	return float(unique) / maps.size()


## Число различающихся тайлов; счёт останавливается, как только порог достигнут.
func _diff(a: PackedByteArray, b: PackedByteArray, stop_at: int) -> int:
	var count := 0
	for k in a.size():
		if a[k] != b[k]:
			count += 1
			if count >= stop_at:
				break
	return count


func _verdict(text: String, ok: bool) -> bool:
	print("  %s %s" % ["OK  " if ok else "FAIL", text])
	return ok


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var parts := arg.trim_prefix("--").split("=", true, 1)
			result[parts[0]] = parts[1]
	return result
