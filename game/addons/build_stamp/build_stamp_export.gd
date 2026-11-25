@tool
extends EditorExportPlugin
## Кладёт в экспортированный пакет метку сборки (BuildInfo.PATH): «коммит[+] дд.мм чч:мм:сс».
## «+» — в рабочей копии были незакоммиченные правки отслеживаемых файлов: коммит тогда не описывает сборку целиком,
## поэтому в метке ещё и время экспорта.

const PATH := "res://build_id.txt"


func _get_name() -> String:
	return "BuildStamp"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var stamp := make_stamp()
	add_file(PATH, stamp.to_utf8_buffer(), false)
	print("Метка сборки: %s" % stamp)


static func make_stamp() -> String:
	var root := ProjectSettings.globalize_path("res://")
	var commit := "nogit"
	var out := []
	if OS.execute("git", ["-C", root, "rev-parse", "--short", "HEAD"], out) == 0 and not out.is_empty():
		commit = str(out[0]).strip_edges()
		out.clear()
		if OS.execute("git", ["-C", root, "status", "--porcelain", "--untracked-files=no"], out) == 0 \
				and not out.is_empty() and str(out[0]).strip_edges() != "":
			commit += "+"
	var t := Time.get_datetime_dict_from_system()
	return "%s %02d.%02d %02d:%02d:%02d" % [commit, t.day, t.month, t.hour, t.minute, t.second]
