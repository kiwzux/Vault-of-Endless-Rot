class_name EnemyArt
extends RefCounted
## Атлас врагов (шаг 11.2, art/gen_enemies.py → res://assets/enemies/enemies.png + enemies.json). Все враги и боссы,
## тень, кольцо ауры элиты и белый пиксель полосок здоровья — в одной текстуре: сортировка по Y перемешивает
## врагов разных видов, а одна текстура не рвёт пакет отрисовки. Лист врага — блок атласа (SheetLayout с origin):
## покой, ходьба, удар, смерть. С шага 11.4 кадры 96 / 144 / 192 px из объёмных моделей, в мире — в 3 раза меньше
## (SheetLayout.scale). Враг без листа показывается белой заглушкой в цвет EnemyData.placeholder_color.

const PATH := "res://assets/enemies/enemies.json"
const PLACEHOLDER := "_placeholder"

static var texture: Texture2D
## Области служебных картинок в атласе.
static var white := Rect2()
static var shadow := Rect2()
static var aura := Rect2()
## id врага (String) → SheetLayout.
static var _sheets := {}
static var _loaded := false


## Лист врага; нет своего — заглушка.
static func sheet(id: StringName) -> SheetLayout:
	_ensure_loaded()
	return _sheets.get(String(id), _sheets.get(PLACEHOLDER))


static func has_sheet(id: StringName) -> bool:
	_ensure_loaded()
	return _sheets.has(String(id))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if not (parsed is Dictionary):
		push_error("EnemyArt: нет атласа врагов %s (art/gen_enemies.py)" % PATH)
		return
	texture = load(PATH.get_base_dir().path_join(String(parsed["atlas"])))
	white = _rect(parsed["white"])
	shadow = _rect(parsed["shadow"])
	aura = _rect(parsed["aura"])
	var sheets: Dictionary = parsed["sheets"]
	for id: String in sheets:
		_sheets[id] = SheetLayout.from_dict(sheets[id])


static func _rect(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
