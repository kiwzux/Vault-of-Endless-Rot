extends Control
## Фон хаба в духе Diablo: тёмный камень, отсвет костра снизу, бронзовая рамка с угловыми накладками.
## Рисуется кодом — без внешних ассетов.

const STONE_TOP := Color(0.035, 0.028, 0.026)
const STONE_BOTTOM := Color(0.09, 0.05, 0.035)
const EMBER := Color(0.75, 0.22, 0.08)
const BRONZE := Color(0.45, 0.33, 0.17)
const BRONZE_LIGHT := Color(0.78, 0.6, 0.3)
const BANDS := 24

var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	for i in BANDS:
		var t := float(i) / (BANDS - 1)
		draw_rect(Rect2(0, h * i / BANDS, w, h / BANDS + 1.0), STONE_TOP.lerp(STONE_BOTTOM, t))
	# Отсвет костра: несколько полупрозрачных эллипсов, слегка мерцает.
	var flicker := 0.85 + 0.15 * sin(_time * 3.1) * sin(_time * 1.7)
	for i in 6:
		var r := (w * 0.55) * (1.0 - i * 0.14)
		var points := PackedVector2Array()
		for k in 33:
			var a := PI + PI * k / 32.0
			points.append(Vector2(w / 2.0 + cos(a) * r, h + sin(a) * r * 0.45))
		draw_colored_polygon(points, Color(EMBER, 0.035 * flicker))
	# Рамка и угловые накладки.
	var frame := Rect2(3, 3, w - 6, h - 6)
	draw_rect(frame, BRONZE, false, 2.0)
	draw_rect(frame.grow(-3), Color(BRONZE, 0.5), false, 1.0)
	for corner: Vector2 in [frame.position, Vector2(frame.end.x, frame.position.y), frame.end, Vector2(frame.position.x, frame.end.y)]:
		var sx := 1.0 if corner.x < w / 2.0 else -1.0
		var sy := 1.0 if corner.y < h / 2.0 else -1.0
		draw_colored_polygon(PackedVector2Array([
			corner, corner + Vector2(18 * sx, 0), corner + Vector2(0, 18 * sy),
		]), BRONZE_LIGHT)
		draw_circle(corner + Vector2(7 * sx, 7 * sy), 2.0, Color(0.6, 0.12, 0.08))
