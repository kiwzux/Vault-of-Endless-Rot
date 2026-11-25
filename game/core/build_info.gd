class_name BuildInfo
extends RefCounted
## Метка экспорта для главного меню и журнала баланса.

const PATH := "res://build_id.txt"
const DEV := "dev"

static var _id := ""


static func id() -> String:
	if _id == "":
		var text := FileAccess.get_file_as_string(PATH).strip_edges() if FileAccess.file_exists(PATH) else ""
		_id = text if text != "" else DEV
	return _id


static func is_dev() -> bool:
	return id() == DEV
