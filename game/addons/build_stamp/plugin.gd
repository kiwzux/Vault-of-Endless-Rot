@tool
extends EditorPlugin
## Подключает к экспорту метку сборки (build_stamp_export.gd). В игру не попадает (exclude_filter пресета).

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("res://addons/build_stamp/build_stamp_export.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
