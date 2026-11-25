class_name ItemTooltip
extends PanelContainer
## Всплывающее окно предмета (как в Diablo): имя цветом редкости, редкость и слот, бонусы, проклятие и строка
## внизу (подсказка, «Надето», цена). Висит поверх интерфейса (top_level) и не участвует в раскладке —
## поэтому окно героя и торговца не сдвигается и не дёргается. Узкое: TIP_WIDTH пикселей интерфейса, текст переносится.
## Мышь сквозь окно проходит. Размер пересчитывается кадром позже показа, пока окно прозрачно: высота
## переносимого текста известна только после раскладки — так окно не мигает недомеренным.

const TIP_WIDTH := 112.0
const LABEL_COLOR := Color(0.72, 0.66, 0.54)
const STATS_COLOR := Color(0.55, 0.7, 1.0)
const CURSE_COLOR := Color(0.95, 0.35, 0.35)
const BETTER_COLOR := Color(0.45, 0.9, 0.5)
const WORSE_COLOR := Color(0.95, 0.4, 0.35)
const NOTE_COLOR := Color(1.0, 0.8, 0.25)
## Сколько кадров окно прозрачно после смены содержимого (раскладка переносов).
const SETTLE_FRAMES := 1

var _column: VBoxContainer
var _settle := 0


func _init() -> void:
	top_level = true
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 1)
	_column.custom_minimum_size.x = TIP_WIDTH
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	hide()


## Заполнить окно предметом. header — строка над именем («Надето»), пусто — без неё.
## deltas — пары [строка, лучше ли] для сравнения с надетым; note — строка цветом золота (цена у торговца);
## footer — серая строка внизу.
func show_item(item: Dictionary, header: String = "", deltas: Array = [], footer: String = "", note: String = "") -> void:
	_clear()
	if header != "":
		_add(header, LABEL_COLOR.darkened(0.15), 8)
	_add(ItemRoller.display_name(item), ItemRoller.rarity_color(item), 10)
	var slot := ItemRoller.slot_of(item)
	_add("%s · %s" % [tr(ItemRoller.RARITY_KEYS[item["rarity"]]), tr(ItemBaseData.SLOT_KEYS[slot])], LABEL_COLOR, 8)
	for line in ItemRoller.bonus_lines(item):
		_add(line, STATS_COLOR, 8)
	var curse := ItemRoller.curse_line(item)
	if curse != "":
		_add(curse, CURSE_COLOR, 8)
	if not deltas.is_empty():
		_add(tr("ITEM_TIP_COMPARE"), LABEL_COLOR, 8)
		for delta: Array in deltas:
			_add(delta[0], BETTER_COLOR if delta[1] else WORSE_COLOR, 8)
	_finish(note, footer)


## Окно товара без экипировки (загадочный свёрток у торговца): название, строка вида, описание.
func show_text(title: String, title_color: Color, kind_text: String, body: String, note: String = "") -> void:
	_clear()
	_add(title, title_color, 10)
	if kind_text != "":
		_add(kind_text, LABEL_COLOR, 8)
	if body != "":
		_add(body, STATS_COLOR, 8)
	_finish(note, "")


func _clear() -> void:
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()


func _finish(note: String, footer: String) -> void:
	if note != "":
		_add(note, NOTE_COLOR, 8)
	if footer != "":
		_add(footer, LABEL_COLOR.darkened(0.2), 8)
	modulate.a = 0.0
	_settle = SETTLE_FRAMES
	show()


## Поставить окно рядом с прямоугольником anchor (справа, если влезает, иначе слева), не выходя за экран.
## side > 0 — сначала справа, side < 0 — сначала слева. Возвращает занятый прямоугольник.
func place_beside(anchor: Rect2, side: int, screen: Rect2, gap: float = 2.0) -> Rect2:
	size = get_combined_minimum_size()
	var right := Vector2(anchor.end.x + gap, anchor.position.y)
	var left := Vector2(anchor.position.x - gap - size.x, anchor.position.y)
	var fits_right := right.x + size.x <= screen.end.x
	var fits_left := left.x >= screen.position.x
	var pos := right if (side > 0 and fits_right) or (side < 0 and not fits_left) else left
	pos.x = clampf(pos.x, screen.position.x, screen.end.x - size.x)
	pos.y = clampf(pos.y, screen.position.y, screen.end.y - size.y)
	position = pos
	return Rect2(pos, size)


## Каждый кадр, пока окно показано: проявить, когда раскладка текста готова.
func tick() -> void:
	if not visible:
		return
	if _settle > 0:
		_settle -= 1
	else:
		modulate.a = 1.0


func _add(text: String, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # текст уже переведён
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TIP_WIDTH
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", -3)  # перенос внутри строки — плотно, как между строками
	_column.add_child(label)
