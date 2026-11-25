class_name PotionBelt
extends Control
## Пояс зелий в духе Diablo (CR-14): Player.BELT_SIZE ячеек, заполненные — флаконы (значок VisualConfig.potion_icon).
## Зелье пьётся клавишей Q (действие drink_potion), подсказка клавиши — слева.

const CELL := 12.0
const GAP := 2.0
const FRAME := Color(0.45, 0.33, 0.17)
const BACK := Color(0.06, 0.045, 0.04, 0.9)
const KEY_HINT := "Q"

var player: Player
var _shown := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = ItemIcon.FILTER


func _process(_delta: float) -> void:
	var count := player.potions if player != null and is_instance_valid(player) else 0
	if count != _shown:
		_shown = count
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, Vector2(0, CELL - 3.0), KEY_HINT, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3, Color.BLACK)
	draw_string(font, Vector2(0, CELL - 3.0), KEY_HINT, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.85, 0.55))
	for i in Player.BELT_SIZE:
		var rect := Rect2(10.0 + i * (CELL + GAP), 0.0, CELL, CELL)
		draw_rect(rect, BACK)
		draw_rect(rect, FRAME, false, 1.0)
		if i < _shown:  # рисунок значка занимает ~3/4 клетки атласа — значок чуть больше ячейки
			ItemIcon.draw_potion(self, rect.grow(2.0))
