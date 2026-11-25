extends RefCounted
## Сводка журнала боёв с боссами (systems/meta/balance_log.gd): строки JSON → таблица Markdown.
## Без ссылок на игровые классы — работает и в tools/balance_report.gd (--script, без автозагрузок).

const STAGE_NAMES := ["лес", "склеп", "собор", "Бездна"]


## Записи файла path (строка — объект JSON, битые пропускаются).
static func read(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return result
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var entry: Variant = JSON.parse_string(line)
		if entry is Dictionary:
			result.append(entry)
	return result


## Таблица боёв: этап, босс, здоровье, герои (класс и уровень), время боя, итог, урон в секунду отряда.
static func fights(entries: Array[Dictionary]) -> String:
	var lines := PackedStringArray([
		"| Этап | Босс | Здоровье | Герои (уровень) | Бой, с | Итог | Урон отряда/с |",
		"|---|---|---|---|---|---|---|",
	])
	for e in entries:
		var heroes := PackedStringArray()
		var party_dps := 0
		for h: Dictionary in e.get("heroes", []):
			heroes.append("%s %d" % [h.get("hero", "?"), int(h.get("level", 0))])
			party_dps += int(h.get("dps", 0))
		var outcome := String(e.get("outcome", "?"))
		if outcome != "victory":
			outcome += " (осталось %d %%)" % roundi(float(e.get("left", 0.0)) * 100.0)
		if int(e.get("pulls", 0)) > 0:  # симуляция: босс уходил из досягаемости, его подтягивали к герою
			outcome += ", подтянут ×%d" % int(e.get("pulls", 0))
		lines.append("| %s | %s | %s | %s | %.0f | %s | %s |" % [_stage(int(e.get("depth", 0))), e.get("boss", "?"),
				_thousands(int(e.get("boss_hp", 0))), ", ".join(heroes), float(e.get("seconds", 0.0)), outcome,
				_thousands(party_dps)])
	return "\n".join(lines)


static func _stage(depth: int) -> String:
	var cycle := depth / STAGE_NAMES.size()
	var name: String = STAGE_NAMES[depth % STAGE_NAMES.size()]
	return name if cycle == 0 else "%s (круг %d)" % [name, cycle + 1]


static func _thousands(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = " " + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if value < 0 else "") + text + out
