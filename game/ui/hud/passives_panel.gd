class_name PassivesPanel
extends Control
## Пассивки героя в правой панели HUD под навыками (CR-15, шаг 11.7): слотов не занимают и копятся — сетка значков
## (медальоны атласа ItemIcon, шаг 11.18) с уровнем, не больше MAX_ROWS рядов (полный список — вкладка «Навыки» меню). Сюда же — копящиеся дары (Точильный камень, Кровь древних).
## Наведение мыши — название, уровень и итоговая прибавка. Перерисовывается, только когда изменились.

const CELL := 14.0
const GAP := 3.0
const COLUMNS := 4
const MAX_ROWS := 3
const BORDER := Color(0.4, 0.55, 0.85)
const GIFT_BORDER := Color(0.55, 0.5, 0.42)

var player: Player
## [Rect2, текст подсказки] — для _get_tooltip.
var _cells: Array = []
var _signature := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = ItemIcon.FILTER


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var signature := hash(player.upgrade_levels)
	if signature != _signature:
		_signature = signature
		visible = not entries().is_empty()  # пустая панель не заслоняет стрелки целей
		queue_redraw()


## Пассивки и копящиеся дары героя по порядку взятия.
func entries() -> Array[PassiveData]:
	var result: Array[PassiveData] = []
	if player == null or not is_instance_valid(player):
		return result
	for id: StringName in player.upgrade_levels:
		var passive := DataRegistry.upgrade(id) as PassiveData
		if passive != null and player.upgrade_levels[id] > 0:
			result.append(passive)
	return result


func _draw() -> void:
	_cells.clear()
	var font := get_theme_default_font()
	var list := entries()
	for i in mini(list.size(), COLUMNS * MAX_ROWS):
		var passive := list[i]
		@warning_ignore("integer_division")
		var rect := Rect2((i % COLUMNS) * (CELL + GAP), (i / COLUMNS) * (CELL + GAP), CELL, CELL)
		var gift := passive.kind == UpgradeData.Kind.FILLER
		if not ItemIcon.draw_icon(self, rect.grow(1.0), passive.icon_name()):  # медальон (шаг 11.18); без атласа — кружок
			draw_rect(rect, passive.icon_color.darkened(0.3))
			draw_circle(rect.get_center(), CELL * 0.3, passive.icon_color)
			draw_rect(rect.grow(-0.5), GIFT_BORDER if gift else BORDER, false, 1.0)
		var level: int = player.upgrade_levels[passive.id]
		var text := str(level)
		var pos := rect.end - Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 1.0, 1.0)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color.BLACK)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.95, 0.8))
		var tip := "%s · %s" % [tr(passive.name_key), tr("UPGRADE_LEVEL").format({"level": level})]
		var total := ItemRoller.stat_line(passive.stat, passive.per_level * level)
		if total != "":
			tip += "\n" + total
		_cells.append([rect, tip])


func _get_tooltip(at_position: Vector2) -> String:
	for cell: Array in _cells:
		if (cell[0] as Rect2).has_point(at_position):
			return cell[1]
	return ""
