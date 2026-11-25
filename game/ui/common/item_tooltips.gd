class_name ItemTooltips
extends Node
## Всплывающее окно предмета для окна героя и торговца: окно предмета под мышью (или в фокусе). Окно поверх
## интерфейса (ItemTooltip, top_level) и не сдвигает раскладку. Узел кладётся в тот же CanvasLayer, что и окно
## с ячейками; process_mode наследует (меню и торговец работают на паузе).
## 17.10.2026: предметы копятся (Player.receive_item) — сравнения с надетым (Alt) больше нет: внизу окна
## сказано, что предмет прибавит свои характеристики насовсем (или что это лучший предмет слота на кукле).
##
## Окно встаёт справа от column (колонки с ячейками; null — от самой ячейки) на высоте ячейки, в пределах
## bounds (null — экран).

## Чья кукла (у предмета на кукле — своя подпись).
var player: Player
var column: Control
var bounds: Control
## Для проверок.
var tip: ItemTooltip

var _cell: Control
var _item := {}
var _note := ""
## Окно не предмета (товар): [заголовок, цвет, вид, описание].
var _text: Array = []


func _ready() -> void:
	tip = ItemTooltip.new()
	add_child(tip)


## Мышь или фокус на ячейке с предметом. note — строка цветом золота (цена).
func hover(item: Dictionary, cell: Control, note: String = "") -> void:
	_cell = cell
	_item = item
	_note = note
	_text = []
	_fill()
	_place()


## Мышь или фокус на товаре без экипировки: простое окно с описанием.
func hover_text(cell: Control, title: String, color: Color, kind_text: String, body: String, note: String = "") -> void:
	_cell = cell
	_item = {}
	_note = note
	_text = [title, color, kind_text, body]
	_fill()
	_place()


## Мышь ушла — окно прячется сразу (даже если ячейка в фокусе после щелчка); фокус ушёл — только если мышь
## не над ячейкой.
func unhover(cell: Control, from_mouse: bool) -> void:
	if cell == _cell and (from_mouse or not cell.is_hovered()):
		hide_tips()


func hide_tips() -> void:
	_cell = null
	_item = {}
	_text = []
	if tip != null:
		tip.hide()


func is_showing() -> bool:
	return tip != null and tip.visible


func _process(_delta: float) -> void:
	if _cell == null:
		return
	if not is_instance_valid(_cell) or not _cell.is_visible_in_tree():
		hide_tips()
		return
	_place()
	tip.tick()


func _fill() -> void:
	if not _text.is_empty():
		tip.show_text(_text[0], _text[1], _text[2], _text[3], _note)
		return
	var on_doll: bool = player != null and is_instance_valid(player) and player.equipment.values().has(_item)
	tip.show_item(_item, "", [], tr("INVENTORY_EQUIPPED" if on_doll else "ITEM_TIP_STACK"), _note)


func _place() -> void:
	if not tip.visible or _cell == null:
		return
	var screen := bounds.get_global_rect() if bounds != null else tip.get_viewport().get_visible_rect()
	var cell := _cell.get_global_rect()
	var anchor := cell
	if column != null:
		var rect := column.get_global_rect()
		anchor = Rect2(Vector2(rect.position.x, cell.position.y), Vector2(rect.size.x, cell.size.y))
	tip.place_beside(anchor, 1, screen)
