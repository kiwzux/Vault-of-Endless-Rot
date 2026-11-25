class_name CastleCarpet
extends Node2D
## Ковровая дорожка тронного зала Убежища (17.10.2026, замок в духе Diablo): тёмно-красный ковёр с золотой каймой,
## ромбами по оси и бахромой на концах. Лежит на слое пола (под реквизитом и героями) и рисуется кодом — это часть
## облика зала, а не станция: тела и подсказки нет.

const BASE := Color(0.2, 0.03, 0.035)
const FIELD := Color(0.27, 0.045, 0.05)
const BORDER := Color(0.55, 0.4, 0.15)
const BORDER_DARK := Color(0.3, 0.2, 0.08)
const DIAMOND := Color(0.42, 0.29, 0.1)
const FRINGE := Color(0.55, 0.47, 0.3)

## Прямоугольник ковра в координатах узла (px мира).
var rect := Rect2(-40, -160, 80, 320)


func _draw() -> void:
	draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.35))  # тень по краю
	draw_rect(rect, BASE)
	var inner := rect.grow(-6.0)
	draw_rect(inner, FIELD)
	for r: Rect2 in [rect.grow(-3.0), rect.grow(-8.0)]:
		draw_rect(r, BORDER, false, 1.5)
	draw_rect(rect.grow(-4.5), BORDER_DARK, false, 1.0)
	# Ромбы вдоль оси.
	var step := 34.0
	var y := inner.position.y + step * 0.5
	while y < inner.end.y - step * 0.25:
		var c := Vector2(inner.get_center().x, y)
		var w := minf(inner.size.x * 0.32, 14.0)
		var diamond := PackedVector2Array([c + Vector2(0, -w), c + Vector2(w, 0), c + Vector2(0, w), c + Vector2(-w, 0)])
		draw_colored_polygon(diamond, DIAMOND)
		var core := PackedVector2Array([c + Vector2(0, -w * 0.45), c + Vector2(w * 0.45, 0), c + Vector2(0, w * 0.45),
				c + Vector2(-w * 0.45, 0)])
		draw_colored_polygon(core, BASE)
		y += step
	# Бахрома на концах.
	var x := rect.position.x + 2.0
	while x < rect.end.x - 1.0:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.position.y - 4.0), FRINGE, 1.0)
		draw_line(Vector2(x, rect.end.y), Vector2(x, rect.end.y + 4.0), FRINGE, 1.0)
		x += 3.0
