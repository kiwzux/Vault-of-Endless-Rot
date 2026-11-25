class_name SealsWindow
extends HubWindow
## Печати Скверны (шаг 12.3, как Пакт наказания в Hades) — окно от Врат: у каждой печати ранг кнопками - и +,
## что даёт ранг и сколько он стоит Скверны; внизу сумма Скверны и награда — души и шанс редкого лута.
## Выбор хранится в Sanctuary.seals.

const HEAT_COLOR := Color(0.78, 0.45, 1.0)

var _rows := {}
var _total: Label


func build() -> void:
	set_title(tr("HUB_SEALS_TITLE"))
	_rows.clear()
	var hint := make_label(tr("HUB_SEALS_HINT"), 8, DIM_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(WRAP_WIDTH, 0)
	body.add_child(hint)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	for seal: SealData in DataRegistry.SEALS:
		list.add_child(_row(seal))
	body.add_child(make_scroll(list))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	_total = make_label("", 10, HEAT_COLOR)
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_total)
	var reset := Button.new()
	reset.text = "HUB_SEALS_RESET"
	reset.add_theme_font_size_override("font_size", 9)
	reset.pressed.connect(_reset)
	footer.add_child(reset)
	var back := Button.new()
	back.text = "HUB_SEALS_BACK"
	back.add_theme_font_size_override("font_size", 9)
	back.pressed.connect(_back)
	footer.add_child(back)
	body.add_child(footer)
	_update()


## Строка печати: полоска цвета печати, название и цена ранга, описание; справа - ранг +.
func _row(seal: SealData) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var swatch := ColorRect.new()
	swatch.color = seal.icon_color
	swatch.custom_minimum_size = Vector2(3, 0)
	row.add_child(swatch)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(make_label("%s · %s" % [tr(seal.name_key), tr("HUB_SEALS_POINTS").format({"points": seal.points})],
			10, TITLE_COLOR))
	var description := make_label(seal.describe(), 8, TEXT_COLOR)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(250, 0)
	text.add_child(description)
	row.add_child(text)
	var minus := _step_button("-", seal, -1)
	var rank := make_label("", 10, HEAT_COLOR)
	rank.custom_minimum_size = Vector2(30, 0)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var plus := _step_button("+", seal, 1)
	row.add_child(minus)
	row.add_child(rank)
	row.add_child(plus)
	_rows[seal.id] = [rank, minus, plus]
	return row


func _step_button(text: String, seal: SealData, delta: int) -> Button:
	var button := Button.new()
	button.text = text
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.add_theme_font_size_override("font_size", 18)  # знаки шрифта заголовков мелкие — крупнее
	button.custom_minimum_size = Vector2(18, 18)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void:
		sanctuary.set_seal(seal.id, rank_of(seal.id) + delta)
		_update())
	return button


func rank_of(id: StringName) -> int:
	return int(sanctuary.seals.get(id, 0))


func _update() -> void:
	for id: StringName in _rows:
		var seal := DataRegistry.seal(id)
		var cells: Array = _rows[id]
		var rank := rank_of(id)
		(cells[0] as Label).text = "%d / %d" % [rank, seal.max_rank]
		(cells[1] as Button).disabled = rank <= 0
		(cells[2] as Button).disabled = rank >= seal.max_rank
	_total.text = GateWindow.heat_text(sanctuary.seals)


func _reset() -> void:
	for id: StringName in _rows:
		sanctuary.set_seal(id, 0)
	_update()


func _back() -> void:
	close_window()
	sanctuary.open_window(&"gate")
