class_name VitalsPanel
extends Control
## Левая панель HUD в духе Halls of Torment (шаг 11.7): медальон с уровнем героя, вертикальная полоса опыта,
## под ней числа опыта, здоровья и маны. Всё рисуется одним проходом _draw (фигуры, затем текст) и только
## когда числа изменились. Сфера здоровья и пояс зелий — отдельные узлы ниже.

const MEDALLION_RADIUS := 19.0
const BAR_WIDTH := 12.0
const BAR_TOP := 50.0
const GOLD := Color(0.86, 0.66, 0.3)
const GOLD_DARK := Color(0.36, 0.24, 0.09)
const XP_FILL := Color(0.24, 0.48, 0.95)
const XP_LIGHT := Color(0.55, 0.75, 1.0)
const BOX := Color(0.04, 0.04, 0.05, 0.85)
const XP_TEXT := Color(0.62, 0.78, 1.0)
const HP_TEXT := Color(1.0, 0.45, 0.4)
const MANA_TEXT := Color(0.5, 0.65, 1.0)
const LEVEL_TEXT := Color(1.0, 0.92, 0.72)
const FONT_SIZE := 9

var player: Player
## Где кончается полоса опыта и начинаются таблички чисел (в пикселях панели; под ними место на 3 таблички).
var bar_bottom := 196.0
var _shown := []
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_font(&"font", &"HeaderLabel")


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var values := [player.level, player.xp, Player.xp_to_next(player.level), ceili(player.health),
			ceili(player.max_health), ceili(player.mana), ceili(player.max_mana)]
	if values != _shown:
		_shown = values
		queue_redraw()


func _draw() -> void:
	if _shown.is_empty():
		return
	var mid := size.x / 2.0
	# Медальон: бронзовая оправа, тёмный камень, уровень золотом.
	var center := Vector2(mid, 4.0 + MEDALLION_RADIUS)
	draw_circle(center, MEDALLION_RADIUS + 2.0, GOLD_DARK)
	draw_circle(center, MEDALLION_RADIUS, GOLD)
	draw_circle(center, MEDALLION_RADIUS - 2.5, Color(0.07, 0.06, 0.06))
	draw_arc(center, MEDALLION_RADIUS - 4.0, PI * 1.1, PI * 1.9, 16, Color(1, 1, 1, 0.12), 1.5)
	for i in 4:
		var spike := center + Vector2.RIGHT.rotated(PI / 4.0 + i * PI / 2.0) * (MEDALLION_RADIUS + 1.0)
		draw_circle(spike, 2.2, GOLD)
	# Полоса опыта снизу вверх.
	var bar := Rect2(mid - BAR_WIDTH / 2.0, BAR_TOP, BAR_WIDTH, bar_bottom - BAR_TOP)
	draw_rect(bar.grow(2.0), GOLD_DARK)
	draw_rect(bar.grow(1.0), GOLD)
	draw_rect(bar, Color(0.03, 0.03, 0.05))
	var share := clampf(float(_shown[1]) / maxf(float(_shown[2]), 1.0), 0.0, 1.0)
	var filled := Rect2(bar.position.x, bar.end.y - bar.size.y * share, bar.size.x, bar.size.y * share)
	draw_rect(filled, XP_FILL)
	draw_rect(Rect2(filled.position, Vector2(3.0, filled.size.y)), XP_LIGHT * Color(1, 1, 1, 0.6))
	for i in range(1, 10):  # деления по 10 %
		var y := bar.end.y - bar.size.y * i / 10.0
		draw_line(Vector2(bar.position.x, y), Vector2(bar.position.x + 3.0, y), Color(0, 0, 0, 0.6), 1.0)
	# Таблички с числами.
	var rows: Array = [["%d / %d" % [_shown[1], _shown[2]], XP_TEXT], ["%d / %d" % [_shown[3], _shown[4]], HP_TEXT]]
	if int(_shown[6]) > 0:
		rows.append(["%d / %d" % [_shown[5], _shown[6]], MANA_TEXT])
	var y := bar_bottom + 6.0
	for row: Array in rows:
		draw_rect(Rect2(8.0, y, size.x - 16.0, 13.0), BOX)
		draw_rect(Rect2(8.0, y, size.x - 16.0, 13.0), GOLD_DARK, false, 1.0)
		y += 16.0
	# Текст — после всех фигур (один пакет отрисовки на фигуры, один на текст).
	_centered(str(_shown[0]), center + Vector2(0, 5.0), 14, LEVEL_TEXT)
	y = bar_bottom + 6.0
	for row: Array in rows:
		_centered(row[0], Vector2(mid, y + 10.0), FONT_SIZE, row[1])
		y += 16.0


func _centered(text: String, baseline: Vector2, font_size: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := baseline - Vector2(w / 2.0, 0.0)
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color.BLACK)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
