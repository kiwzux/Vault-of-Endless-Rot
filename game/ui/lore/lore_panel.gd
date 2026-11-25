class_name LorePanel
extends PanelContainer
## Окно записи лора (шаг 8): заголовок и текст на пергаменте поверх HUD. Открывается у самого игрока
## (Interactable вида LORE), мир не останавливает: закрывается по E или Esc и само, когда герой отошёл.

const WIDTH := 360.0
## Дальше этого от точки лора окно закрывается само, px.
const CLOSE_DISTANCE := 70.0
const TITLE_COLOR := Color(0.95, 0.78, 0.4)
const TEXT_COLOR := Color(0.86, 0.8, 0.68)

var _world: World
var _source: Node2D
var _title: Label
var _text: Label


## Показать запись lore у точки source (повторное открытие — та же панель с новым текстом).
static func open(world: World, lore: LoreData, source: Node2D) -> LorePanel:
	var hud := world.get_node(^"HUD")
	var panel := hud.get_node_or_null(^"LorePanel") as LorePanel
	if panel == null:
		panel = LorePanel.new()
		panel.name = &"LorePanel"
		hud.add_child(panel)
	panel._world = world
	panel._source = source
	panel._title.text = TranslationServer.translate(lore.title_key)
	panel._text.text = TranslationServer.translate(lore.text_key)
	panel.show()
	return panel


func _init() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = -60.0  # по тексту окно вырастет само (в обе стороны)
	offset_bottom = 20.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_title = _label(13, TITLE_COLOR)
	column.add_child(_title)
	_text = _label(9, TEXT_COLOR)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WIDTH - 24.0, 0)
	column.add_child(_text)
	var hint := _label(8, Color(0.6, 0.55, 0.45))
	hint.text = "LORE_CLOSE_HINT"
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(hint)


func _process(_delta: float) -> void:
	if not visible:
		return
	var player := _world.local_player() if _world != null else null
	if player == null or not is_instance_valid(_source) or player.global_position.distance_to(_source.global_position) > CLOSE_DISTANCE:
		hide()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		hide()


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
