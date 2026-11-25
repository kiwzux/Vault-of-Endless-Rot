class_name RunCounters
extends Control
## Счётчики забега внизу правой панели HUD (шаг 11.7, как в Halls of Torment): таблички с золотом (CR-14),
## убитыми врагами и таймером уровня (песочные часы). Перерисовываются, только когда числа изменились.

const GOLD := Color(1.0, 0.8, 0.25)
const BONE := Color(0.88, 0.85, 0.75)
const SAND := Color(0.95, 0.78, 0.45)
const TEXT := Color(1.0, 0.94, 0.8)
const BOX := Color(0.04, 0.04, 0.05, 0.85)
const RIM := Color(0.36, 0.24, 0.09)
const ROW := 24.0
const BOX_HEIGHT := 20.0
const FONT_SIZE := 12

var player: Player
## Таймер уровня «м:сс»; пусто — таймера нет (логово финального босса).
var time_text := ""
var _shown := []
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_font(&"font", &"HeaderLabel")


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var values := [player.gold, player.kills, time_text]
	if values != _shown:
		_shown = values
		queue_redraw()


func _draw() -> void:
	if _shown.is_empty():
		return
	var texts := [str(_shown[0]), str(_shown[1]), _shown[2] if _shown[2] != "" else "—"]
	for i in 3:
		var box := Rect2(0.0, i * ROW, size.x, BOX_HEIGHT)
		draw_rect(box, BOX)
		draw_rect(box, RIM, false, 1.0)
	_coin(Vector2(10, 10))
	_skull(Vector2(10, ROW + 10))
	_hourglass(Vector2(10, ROW * 2 + 10))
	for i in 3:
		var text: String = texts[i]
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var pos := Vector2(size.x - 6.0 - w, i * ROW + 15.0)
		draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color.BLACK)
		draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)


func _coin(c: Vector2) -> void:
	draw_circle(c + Vector2(1, 1), 5.5, GOLD.darkened(0.6))
	draw_circle(c, 5.5, GOLD.darkened(0.3))
	draw_circle(c, 4.2, GOLD)
	draw_circle(c - Vector2(1.5, 1.5), 1.2, Color(1, 1, 0.85))


func _skull(c: Vector2) -> void:
	draw_circle(c - Vector2(0, 1), 5.0, BONE)
	draw_rect(Rect2(c.x - 3.0, c.y + 1.5, 6.0, 3.5), BONE)
	draw_circle(c + Vector2(-2.0, -1.0), 1.4, Color.BLACK)
	draw_circle(c + Vector2(2.0, -1.0), 1.4, Color.BLACK)


func _hourglass(c: Vector2) -> void:
	draw_rect(Rect2(c.x - 5.0, c.y - 6.5, 10.0, 1.5), GOLD.darkened(0.2))
	draw_rect(Rect2(c.x - 5.0, c.y + 5.0, 10.0, 1.5), GOLD.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -5), c + Vector2(4, -5), c + Vector2(0, 0)]), SAND.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0), c + Vector2(4, 5), c + Vector2(-4, 5)]), SAND)
