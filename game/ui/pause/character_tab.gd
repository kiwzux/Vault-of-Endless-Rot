class_name CharacterTab
extends HBoxContainer
## Вкладка «Герой» меню (шаг 11.7, как экран персонажа Halls of Torment; бывший инвентарь CR-07).
## Слева — экипировка «куклой» (шлем, амулет, оружие, доспех, перчатки, сапоги, два кольца) и накопленное с предметов;
## справа — характеристики (характеристика · основа · итог, итог лучше основы — зелёным) и навыки забега (урон
## в секунду и весь урон — из Player.run_stats, RunStats).
## 17.10.2026: предметы копятся — сумки и обмена нет. На кукле — лучший найденный предмет каждого слота, под ней —
## сколько предметов подобрано и сумма их характеристик (Player.item_stats). Описание предмета — всплывающее окно
## (ItemTooltips) справа от колонки: поверх меню, раскладку не сдвигает. Окно перестраивается по
## Events.inventory_changed.

const SLOT := 30.0
const LABEL_COLOR := Color(0.72, 0.66, 0.54)
const STACK_COLOR := Color(0.55, 0.7, 1.0)
const CURSE_COLOR := Color(0.95, 0.35, 0.35)
const VALUE_COLOR := Color(0.95, 0.9, 0.78)
const BETTER_COLOR := Color(0.45, 0.9, 0.5)
const WORSE_COLOR := Color(0.95, 0.4, 0.35)
const EMPTY_GLYPH := Color(1, 1, 1, 0.12)
## Где стоит слот в «кукле» (левый верхний угол, пиксели интерфейса).
const DOLL := {
	ItemBaseData.Slot.HELM: Vector2(78, 0),
	ItemBaseData.Slot.AMULET: Vector2(118, 8),
	ItemBaseData.Slot.WEAPON: Vector2(38, 40),
	ItemBaseData.Slot.ARMOR: Vector2(78, 40),
	ItemBaseData.Slot.GLOVES: Vector2(118, 40),
	ItemBaseData.Slot.BOOTS: Vector2(78, 80),
	ItemBaseData.Slot.RING: Vector2(38, 80),
	ItemBaseData.Slot.RING_2: Vector2(118, 80),
}

var world: World
var player: Player
## Лист характеристик: подпись · основа · итог (для проверок — его заполненность).
var sheet: GridContainer
## Сумма характеристик подобранных предметов (для проверок).
var stacked: VBoxContainer

var _doll: Control
var _collected: Label
var _skills: GridContainer
var _skills_signature := -1
## Окно предмета под мышью и окно надетого для сравнения (Alt).
var tips: ItemTooltips


func _init() -> void:
	add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 186.0
	left.add_theme_constant_override("separation", 3)
	add_child(left)
	left.add_child(_header("INVENTORY_EQUIPMENT", HORIZONTAL_ALIGNMENT_CENTER))
	_doll = Control.new()
	_doll.custom_minimum_size = Vector2(186, SLOT * 2.0 + 52.0)
	left.add_child(_doll)
	_collected = _header("", HORIZONTAL_ALIGNMENT_CENTER)
	_collected.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	left.add_child(_collected)
	stacked = VBoxContainer.new()
	stacked.add_theme_constant_override("separation", 0)
	stacked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stacked_scroll := _scroll(stacked, 40.0)
	stacked_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(stacked_scroll)
	var hint := _text(8, LABEL_COLOR.darkened(0.2))
	hint.text = "INVENTORY_HINT"
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	left.add_child(hint)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 3)
	add_child(right)
	right.add_child(_table_header(["CHAR_ATTRIBUTE", "CHAR_BASE", "CHAR_TOTAL"]))
	right.add_child(_divider())
	sheet = GridContainer.new()
	sheet.columns = 3
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_theme_constant_override("h_separation", 8)
	sheet.add_theme_constant_override("v_separation", 0)
	right.add_child(_scroll(sheet, 150.0))
	var gap := Control.new()
	gap.custom_minimum_size.y = 4.0
	right.add_child(gap)
	right.add_child(_table_header(["RUN_STATS_SKILL", "RUN_STATS_DPS", "RUN_STATS_DAMAGE_TOTAL"]))
	right.add_child(_divider())
	_skills = GridContainer.new()
	_skills.columns = 3
	_skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills.add_theme_constant_override("h_separation", 8)
	_skills.add_theme_constant_override("v_separation", 1)
	var skills_scroll := _scroll(_skills, 60.0)
	skills_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(skills_scroll)

	tips = ItemTooltips.new()
	tips.column = left
	add_child(tips)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			tips.hide_tips())


## Перестроить всё: куклу, накопленное с предметов, лист характеристик, навыки.
func refresh() -> void:
	if player == null or not is_instance_valid(player):
		return
	tips.player = player
	tips.bounds = get_parent_control()  # страница меню: окна не наезжают на боковые панели HUD
	tips.hide_tips()
	_clear(_doll)
	_clear(stacked)
	_clear(sheet)
	for slot: int in DOLL:
		var worn: Dictionary = player.equipment.get(slot, {})
		var button := _item_button(worn, slot, Vector2(SLOT, SLOT))
		button.position = DOLL[slot]
		if worn.is_empty():  # у надетого — своё окно предмета, системная подсказка только у пустого слота
			button.tooltip_text = ItemBaseData.SLOT_KEYS[slot]
		_doll.add_child(button)
	_collected.text = tr("INVENTORY_COLLECTED").format({"count": player.items_collected})
	var keys := player.item_stats.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for stat: Variant in keys:
		var value := float(player.item_stats[stat])
		var line := ItemRoller.stat_line(StringName(str(stat)), value)
		if line != "" and absf(value) > 0.0001:
			var label := _text(8, STACK_COLOR if value > 0.0 else CURSE_COLOR)
			label.text = line
			stacked.add_child(label)
	if stacked.get_child_count() == 0:
		var none := _text(8, LABEL_COLOR.darkened(0.2))
		none.text = tr("INVENTORY_NOTHING_YET")
		stacked.add_child(none)
	_fill_sheet()
	_skills_signature = -1
	refresh_live()


## Каждый кадр, пока вкладка открыта: таблица навыков, когда пришла новая сводка забега.
func refresh_live() -> void:
	if player == null or not is_instance_valid(player):
		return
	var signature := hash(player.run_stats)
	if signature == _skills_signature:
		return
	_skills_signature = signature
	_clear(_skills)
	var rows: Array = player.run_stats.get("skills", [])
	if rows.is_empty():
		_skills.add_child(_cell(tr("RUN_STATS_NO_DATA"), LABEL_COLOR))
		_skills.add_child(Control.new())
		_skills.add_child(Control.new())
	for row: Array in rows:
		var name_box := HBoxContainer.new()
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_box.add_theme_constant_override("separation", 4)
		var swatch := ColorRect.new()
		var upgrade := DataRegistry.upgrade(StringName(str(row[0])))
		swatch.color = upgrade.icon_color if upgrade != null else LABEL_COLOR
		swatch.custom_minimum_size = Vector2(6, 6)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_box.add_child(swatch)
		name_box.add_child(_cell(tr(RunStats.source_name_key(String(row[0]))), VALUE_COLOR))
		_skills.add_child(name_box)
		_skills.add_child(_cell(RunStatsView.short_number(roundi(RunStats.row_dps(row))), VALUE_COLOR, true))
		_skills.add_child(_cell(RunStatsView.short_number(int(row[1])), VALUE_COLOR, true))


## Лист характеристик: разделы цветным заголовком, строки «подпись · основа · итог».
func _fill_sheet() -> void:
	var section := -1
	for row: Array in StatSheet.rows(player, world.economy.chest_price(player)):
		if row[2] != section:
			section = row[2]
			var header := _cell(tr(StatSheet.SECTION_KEYS[section]), StatSheet.SECTION_COLORS[section])
			header.theme_type_variation = &"HeaderLabel"
			header.add_theme_font_size_override("font_size", 10)
			sheet.add_child(header)
			sheet.add_child(Control.new())
			sheet.add_child(Control.new())
		var label := _cell(tr(row[0]), LABEL_COLOR)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sheet.add_child(label)
		var base: String = row[3]
		sheet.add_child(_cell(base, LABEL_COLOR, true))
		var total: String = row[1]
		sheet.add_child(_cell(total, _compare_color(row[0], base, total), true))


## Итог лучше основы — зелёным, хуже — красным (у Оберега меньше секунд — лучше). У здоровья и маны сравнивается
## максимум («текущее / максимум»).
static func _compare_color(key: String, base: String, total: String) -> Color:
	if base == "" or base == "—" or total == "—":
		return VALUE_COLOR
	var shown := total.get_slice(" / ", 1) if total.contains(" / ") else total
	var a := _number(base)
	var b := _number(shown)
	if is_equal_approx(a, b):
		return VALUE_COLOR
	var better := b > a if key != "CHAR_WARD" else b < a
	return BETTER_COLOR if better else WORSE_COLOR


static func _number(text: String) -> float:
	return text.replace("+", "").replace("%", "").replace("×", "").replace(" s", "").to_float()


func _item_button(item: Dictionary, slot: int, cell: Vector2) -> Button:
	var button := Button.new()
	button.custom_minimum_size = cell
	button.size = cell
	button.texture_filter = ItemIcon.FILTER
	var frame := get_theme_stylebox(&"panel", &"SlotPanel")
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	if item.is_empty():
		button.focus_mode = Control.FOCUS_NONE
	else:
		button.mouse_entered.connect(func() -> void: tips.hover(item, button))
		button.focus_entered.connect(func() -> void: tips.hover(item, button))
		button.mouse_exited.connect(func() -> void: tips.unhover(button, true))
		button.focus_exited.connect(func() -> void: tips.unhover(button, false))
	button.draw.connect(func() -> void:
		var rect := Rect2(Vector2.ZERO, button.size)
		button.draw_style_box(frame, rect)
		var inner := rect.grow(-3.0)
		if not item.is_empty():  # значок (шаг 11.15) на подложке цвета редкости, рисунок чуть шире ячейки
			button.draw_rect(inner, ItemIcon.EMPTY_BACK.lerp(ItemRoller.rarity_color(item), 0.14))
			ItemIcon.draw_item_picture(button, rect.grow(1.0), item)
			button.draw_rect(inner, ItemRoller.rarity_color(item), false, 1.0)
		elif slot >= 0:
			ItemIcon.draw_glyph(button, inner, slot, EMPTY_GLYPH)
		if button.is_hovered() or button.has_focus():
			button.draw_rect(rect.grow(-1.0), Color(1, 0.86, 0.5), false, 1.0))
	button.mouse_entered.connect(button.queue_redraw)
	button.mouse_exited.connect(button.queue_redraw)
	button.focus_entered.connect(button.queue_redraw)
	button.focus_exited.connect(button.queue_redraw)
	return button


# --- Построение ---

func _header(key: String, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HeaderLabel"
	label.text = key
	label.horizontal_alignment = align
	return label


## Заголовок таблицы: первая колонка растягивается, остальные — по правому краю.
func _table_header(keys: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for i in keys.size():
		var label := _header(keys[i], HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", LABEL_COLOR)
		if i == 0:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			label.custom_minimum_size.x = 64.0
		row.add_child(label)
	return row


## Золотая черта со стрелками (art/gen_ui.py, divider.png).
func _divider() -> Panel:
	var line := Panel.new()
	line.custom_minimum_size.y = 4.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := SlicedStyle.new()
	style.texture = load("res://assets/ui/divider.png")
	style.margin = 8.0
	line.add_theme_stylebox_override(&"panel", style)
	return line


func _scroll(content: Control, height: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = height
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(content)
	return scroll


func _cell(text: String, color: Color, right: bool = false) -> Label:
	var label := _text(9, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size.x = 64.0
	return label


func _text(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # текст уже переведён через tr()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
