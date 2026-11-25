class_name OffscreenMarkers
extends Control
## Стрелки у края экрана на важные цели за его пределами: босс и мини-босс статуи, Ключ босса,
## открытые порталы, союзники в коопе (DESIGN 4). Цель на экране — над ней пульсирующий маркер,
## если это Ключ или открытый портал: их легко потерять в толпе. Стрелка не заходит под панели
## HUD (миникарта, сборка героя): останавливается на луче перед ними.

const MARGIN_TOP := 16.0
const MARGIN_SIDE := 14.0
## Снизу панель со сферами и опытом — стрелки выше неё.
const MARGIN_BOTTOM := 44.0
const ARROW := 6.0
## Зазор между стрелкой и панелью HUD.
const PANEL_GAP := 6.0
const BOSS := Color(1.0, 0.25, 0.2)
const MINI_BOSS := Color(1.0, 0.55, 0.2)
const KEY := Color(1.0, 0.85, 0.3)
const ALLY := Color(0.45, 0.95, 0.55)

var world: World
## Панели HUD, под которые стрелка не заходит.
var obstacles: Array[Control] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## [мировая позиция, цвет, рисовать ли маркер над целью на экране] для всех целей.
func targets() -> Array:
	var result: Array = []
	if world == null:
		return result
	for node in world.enemies.get_children():
		var e := node as Enemy
		if e == null or e.dead or e.ally or e.data == null:
			continue
		if e.data.is_boss:
			result.append([e.global_position, BOSS, false])
		elif e.data.loot_rarity >= 0:
			result.append([e.global_position, MINI_BOSS, false])
	for node in world.pickups.get_children():
		if node is Pickup and (node as Pickup).kind == Pickup.Kind.KEY:
			result.append([(node as Pickup).global_position, KEY, true])
	for node in world.props.get_children():
		if node is Portal and (node as Portal).active:
			result.append([(node as Portal).global_position, Portal.MODE_COLORS[(node as Portal).mode], true])
	var me := world.local_player()
	for p in world.get_players():
		if p != me:
			result.append([p.global_position, ALLY if p.alive else Color(ALLY, 0.5), false])
	return result


func _draw() -> void:
	var view := get_viewport().get_visible_rect()
	var to_screen := get_viewport().get_canvas_transform()
	var inner := Rect2(view.position + Vector2(MARGIN_SIDE, MARGIN_TOP),
			view.size - Vector2(MARGIN_SIDE * 2.0, MARGIN_TOP + MARGIN_BOTTOM))
	var center := inner.get_center()
	var pulse := 0.65 + 0.35 * sin(_time * 5.0)
	for target: Array in targets():
		var screen: Vector2 = to_screen * (target[0] as Vector2)
		var color: Color = target[1]
		if inner.has_point(screen):
			if target[2]:
				_draw_bounce(screen, color, pulse)
			continue
		var dir := (screen - center).normalized()
		var t := _edge_distance(inner, dir)
		for panel in obstacles:
			if panel.is_visible_in_tree():
				t = minf(t, _ray_enter(center, dir, panel.get_global_rect().grow(PANEL_GAP + ARROW)))
		_draw_arrow(center + dir * t, dir, Color(color, pulse))


## Расстояние по лучу из центра прямоугольника до его края.
func _edge_distance(rect: Rect2, dir: Vector2) -> float:
	var half := rect.size / 2.0
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, half.x / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, half.y / absf(dir.y))
	return t


## Где луч входит в прямоугольник (метод плит); INF — не входит.
func _ray_enter(origin: Vector2, dir: Vector2, box: Rect2) -> float:
	var t_near := -INF
	var t_far := INF
	for axis in 2:
		if absf(dir[axis]) < 0.000001:
			if origin[axis] < box.position[axis] or origin[axis] > box.end[axis]:
				return INF
			continue
		var t1 := (box.position[axis] - origin[axis]) / dir[axis]
		var t2 := (box.end[axis] - origin[axis]) / dir[axis]
		t_near = maxf(t_near, minf(t1, t2))
		t_far = minf(t_far, maxf(t1, t2))
	return t_near if t_near <= t_far and t_near > 0.0 else INF


func _draw_arrow(pos: Vector2, dir: Vector2, color: Color) -> void:
	var side := dir.orthogonal()
	var tip := pos + dir * ARROW
	var back := pos - dir * ARROW * 0.6
	var outline := Color(0, 0, 0, color.a * 0.8)
	draw_circle(pos - dir * ARROW * 1.4, 3.0, outline)
	draw_circle(pos - dir * ARROW * 1.4, 2.0, color)
	var points := PackedVector2Array([tip, back + side * ARROW * 0.8, back - side * ARROW * 0.8])
	draw_colored_polygon(points, color)
	points.append(tip)
	draw_polyline(points, outline, 1.0)


## Пульсирующая стрелка вниз над целью на экране.
func _draw_bounce(screen: Vector2, color: Color, pulse: float) -> void:
	var y := -26.0 - 3.0 * sin(_time * 5.0)
	_draw_arrow(screen + Vector2(0, y), Vector2.DOWN, Color(color, pulse))
