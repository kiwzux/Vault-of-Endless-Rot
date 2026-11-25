extends SceneTree
## Сводка журнала боёв с боссами (шаг 12) — что записала игра у хоста (systems/meta/balance_log.gd).
## Запуск: godot --headless --path game --script res://tools/balance_report.gd [-- --file=путь] [--last=N]
## По умолчанию — user://balance_log.jsonl (папка профиля игры; у сборки .exe — та же папка).

const Table := preload("res://tools/balance_table.gd")


func _initialize() -> void:
	var path := "user://balance_log.jsonl"
	var last := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--file="):
			path = arg.trim_prefix("--file=")
		elif arg.begins_with("--last="):
			last = arg.trim_prefix("--last=").to_int()
	var entries := Table.read(path)
	if last > 0 and entries.size() > last:
		entries = entries.slice(entries.size() - last)
	print("Журнал: %s — боёв: %d" % [ProjectSettings.globalize_path(path), entries.size()])
	if not entries.is_empty():
		print(Table.fights(entries))
	quit()
