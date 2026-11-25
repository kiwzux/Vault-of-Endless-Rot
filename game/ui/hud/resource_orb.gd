class_name ResourceOrb
extends Control
## Сфера ресурса в стиле Diablo: стеклянный шар в бронзовой оправе, жидкость заполняет его снизу
## на долю value / max_value. Число в центре — текущее значение.

@export var fill_color := Color(0.65, 0.08, 0.08)
@export var value := 1.0:
	set(v):
		value = v
		queue_redraw()
@export var max_value := 1.0:
	set(v):
		max_value = v
		queue_redraw()
## Число в центре сферы; в HUD шага 11.7 числа — на табличках над сферой (VitalsPanel).
@export var show_value := true
## Железные когти оправы, держащие сферу снизу (как в Halls of Torment).
@export var claws := false

const CLAW := Color(0.16, 0.16, 0.19)
const CLAW_LIGHT := Color(0.42, 0.42, 0.48)

const RIM := Color(0.45, 0.33, 0.17)
const RIM_LIGHT := Color(0.8, 0.62, 0.3)
const GLASS := Color(0.05, 0.03, 0.03, 0.92)
const SEGMENTS := 40


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 3.0
	draw_circle(c, r + 3.0, RIM)
	draw_circle(c, r, GLASS)
	var f := clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	if f > 0.01:
		# Уровень жидкости: y = level (ось вниз); дуга окружности ниже него + хорда.
		var level := r - 2.0 * r * f
		var t0 := asin(clampf(level / r, -1.0, 1.0))
		var points := PackedVector2Array()
		for i in SEGMENTS + 1:
			var t := lerpf(t0, PI - t0, float(i) / SEGMENTS)
			points.append(c + Vector2(cos(t), sin(t)) * r)
		draw_colored_polygon(points, fill_color)
		draw_line(points[0], points[SEGMENTS], fill_color.lightened(0.35), 1.0)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.45), r * 0.22, Color(1, 1, 1, 0.12))
	draw_arc(c, r + 1.5, 0.0, TAU, SEGMENTS, RIM_LIGHT, 1.5)
	if claws:
		_draw_claws(c, r)
	if max_value > 0.0 and show_value:
		_draw_value(c)


## Пять загнутых когтей снизу и по бокам: основание за оправой, острие — на стекле.
func _draw_claws(c: Vector2, r: float) -> void:
	for angle_deg: float in [20.0, 55.0, 90.0, 125.0, 160.0]:
		var dir := Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
		var side := dir.orthogonal()
		var base := c + dir * (r + 1.5)
		var tip := c + dir * (r * 0.78) + side * r * 0.08
		var points := PackedVector2Array([base + side * 2.5, tip, base - side * 2.5])
		draw_colored_polygon(points, CLAW)
		draw_line(base + side * 2.0, tip, CLAW_LIGHT, 1.0)


func _draw_value(c: Vector2) -> void:
	var font := get_theme_default_font()
	var text := str(ceili(value))
	var font_size := 10
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string_outline(font, c + Vector2(-w / 2.0, 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color.BLACK)
	draw_string(font, c + Vector2(-w / 2.0, 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.94, 0.85))
