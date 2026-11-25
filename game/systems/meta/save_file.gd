class_name SaveFile
extends RefCounted
## Надёжная запись локальных файлов прогресса (шаг 10): обрыв записи или испорченный файл не стирают прогресс.
## Формат: первая строка — заголовок JSON {"format", "version", "sha256"}, дальше — данные JSON.
## sha256 считается по тексту данных: изменился хоть один байт — файл считается повреждённым.
## Запись: временный файл (.tmp) → проверка чтением → прежний основной файл становится резервной
## копией (.bak) → временный встаёт на место основного. Упала игра на любом шаге — read найдёт целую
## версию: временный файл (запись закончилась, переименование — нет), основной или резервную копию.
## Повреждённый основной файл не удаляется молча: его копия остаётся рядом (.damaged).

enum Source { NONE, TEMP, MAIN, BACKUP }

const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"
const DAMAGED_SUFFIX := ".damaged"


## Итог чтения: данные, версия формата, откуда взяты и были ли повреждённые файлы.
class Result:
	var data := {}
	var version := 0
	var source := Source.NONE
	## Найден файл, который не прочитался (обрыв записи, порча, ручная правка).
	var damaged := false


## Записать данные. OK — файл на месте и проверен чтением.
static func write(path: String, format: String, version: int, data: Dictionary) -> Error:
	var payload := JSON.stringify(data, "\t", true)
	var header := JSON.stringify({"format": format, "version": version, "sha256": payload.sha256_text()})
	var temp := path + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(header + "\n" + payload + "\n")
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK:
		return err
	if _read(temp, format).is_empty():
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		# Целый основной файл становится резервной копией; повреждённый резервную копию не вытесняет.
		if _read(path, format).is_empty():
			DirAccess.remove_absolute(path)
		else:
			err = DirAccess.rename_absolute(path, path + BACKUP_SUFFIX)
			if err != OK:
				return err
	return DirAccess.rename_absolute(temp, path)


## Прочитать самую свежую целую версию: временный файл, основной, резервная копия.
static func read(path: String, format: String) -> Result:
	var result := Result.new()
	var candidates := {Source.TEMP: path + TEMP_SUFFIX, Source.MAIN: path, Source.BACKUP: path + BACKUP_SUFFIX}
	for source: Source in candidates:
		var file_path: String = candidates[source]
		if not FileAccess.file_exists(file_path):
			continue
		var parsed := _read(file_path, format)
		if parsed.is_empty():
			result.damaged = true
			if source == Source.MAIN:
				DirAccess.copy_absolute(file_path, file_path + DAMAGED_SUFFIX)
			continue
		result.data = parsed.data
		result.version = parsed.version
		result.source = source
		return result
	return result


## Удалить файл со всеми спутниками (проверки).
static func remove(path: String) -> void:
	for suffix in ["", TEMP_SUFFIX, BACKUP_SUFFIX, DAMAGED_SUFFIX]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)


## {"data": Dictionary, "version": int}; пусто — файл не прочитался или не прошёл проверку.
static func _read(path: String, format: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var cut := text.find("\n")
	if cut < 0:
		return {}
	var payload := text.substr(cut + 1).trim_suffix("\n")
	var header: Variant = _parse(text.left(cut))
	if not header is Dictionary or header.get("format") != format or header.get("sha256") != payload.sha256_text():
		return {}
	var data: Variant = _parse(payload)
	if not data is Dictionary or not (header.get("version") is float or header.get("version") is int):
		return {}
	return {"data": data, "version": int(header.version)}


## JSON без сообщений об ошибке в журнал: повреждённый файл — ожидаемый случай.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null
