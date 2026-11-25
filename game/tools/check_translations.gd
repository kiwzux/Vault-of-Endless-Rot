extends SceneTree
## Сверка ключей локализации (НФТ-08): у каждого ключа заполнены все языки,
## каждый ключ из сцен и данных есть в таблице, в сценах нет захардкоженного русского текста.
## Запуск: godot --headless --path game --script res://tools/check_translations.gd

const CSV_PATH := "res://localization/translations.csv"
const SCAN_DIRS: PackedStringArray = ["res://ui", "res://data", "res://world", "res://entities", "res://systems", "res://net", "res://hub"]
const SCAN_EXTENSIONS: PackedStringArray = ["tscn", "tres", "gd"]


func _init() -> void:
	var errors := PackedStringArray()
	var known := _read_table(errors)

	var key_regex := RegEx.create_from_string(
			"(?:\\btext|tooltip_text|_key)\\s*=\\s*\"([A-Z][A-Z0-9_]+)\"|\\btr\\(\"([A-Z][A-Z0-9_]+)\"\\)")
	var hardcoded_regex := RegEx.create_from_string("\\btext\\s*=\\s*\"([^\"]*[А-Яа-яЁё][^\"]*)\"")
	for path in _collect_files():
		var source := FileAccess.get_file_as_string(path)
		for m in key_regex.search_all(source):
			var key := m.get_string(1) if m.get_string(1) != "" else m.get_string(2)
			if not known.has(key):
				errors.append("%s: ключа %s нет в %s" % [path, key, CSV_PATH])
		if path.get_extension() != "gd":
			for m in hardcoded_regex.search_all(source):
				errors.append("%s: строка без перевода «%s»" % [path, m.get_string(1)])

	for e in errors:
		printerr(e)
	print("Ключей в таблице: %d, ошибок: %d" % [known.size(), errors.size()])
	quit(1 if errors.size() > 0 else 0)


func _read_table(errors: PackedStringArray) -> Dictionary:
	var keys := {}
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		errors.append("Не открыть %s" % CSV_PATH)
		return keys
	var header := file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 1 and row[0] == "":
			continue
		var key := row[0]
		for i in range(1, header.size()):
			if i >= row.size() or row[i].strip_edges() == "":
				errors.append("Ключ %s: нет перевода на «%s»" % [key, header[i]])
		keys[key] = true
	return keys


func _collect_files() -> PackedStringArray:
	var result := PackedStringArray()
	var stack := Array(SCAN_DIRS)
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			stack.append(dir.path_join(sub))
		for file in DirAccess.get_files_at(dir):
			if file.get_extension() in SCAN_EXTENSIONS:
				result.append(dir.path_join(file))
	return result
