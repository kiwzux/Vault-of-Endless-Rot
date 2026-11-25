class_name CombatFx
extends Node2D
## Визуальный след атаки: дуга удара (slash), молния (lightning), взрыв (pulse), волна ауры от героя (nova), сферы на
## орбите вокруг героя (orbit — следует за героем owner сам, на каждом узле сети; look — вид: черепа, летучие мыши
## bats или пламя flames), луч (beam — тоже следует за героем, направление dir, длина radius) и рывок (dash —
## тени героя вдоль пути dir × radius).
## Урона не наносит — его уже посчитал хост в SkillRuntime.
##
## Шаг 11.21 — облик навыка героя (data.skill — id навыка вместо цвета): кадры атласа эффектов SkillVfx по стихии
## навыка. Взмах — полоса, натянутая на сектор удара, голова идёт по дуге; цепь — плитки разряда между целями и искры
## на каждой; взрыв и волна — анимации, подогнанные под радиус; луч — текущие плитки с брызгами на конце; орбита —
## черепа в пламени тьмы, летучие мыши, огненные сферы; рывок — полоса следа и тени-силуэты самого героя.
## Эволюция — золотой блеск. Без атласа и у врагов — линии кода, как раньше.

const LIFETIME := {&"slash": 0.18, &"lightning": 0.14, &"pulse": 0.3, &"nova": 0.3, &"dash": 0.32}
## Облик навыка: анимации атласа живут дольше простых линий.
const VFX_LIFETIME := {&"slash": 0.28, &"lightning": 0.24, &"pulse": 0.45, &"nova": 0.42, &"dash": 0.36}
## orbit и beam: проявляются и гаснут за это время.
const ORBIT_FADE := 0.2
## dash: сколько теней вдоль пути.
const DASH_GHOSTS := 5
## Взмах: голова проходит дугу за эту долю жизни; хвост отстаёт на эту долю дуги; внутренний край — доля радиуса.
const SLASH_SWEEP := 0.5
const SLASH_TRAIL := 0.85
const SLASH_INNER := 0.42

var kind: StringName
var color := Color.WHITE
var radius := 32.0
var arc_degrees := 120.0
var direction := Vector2.RIGHT
## Точки молнии относительно узла.
var points := PackedVector2Array()
## orbit и beam: герой-владелец; orbit — число сфер, начальный угол и угловая скорость (как у хоста).
var owner_peer := 1
var count := 0
var phase := 0.0
var speed := 0.0
var look: StringName
## beam и dash: толщина.
var width := 8.0
## Навык следа (шаг 11.21): по нему облик и цвет.
var skill: StringName

## Отжил своё время (а не снят хостом раньше) — см. Projectile.natural_end.
var natural_end := false

var _age := 0.0
var _lifetime := 0.2
var _world: World
var _look: SkillVfx.Look
var _clip: SkillVfx.Clip
## Второй слой: искры на целях цепи, брызги на конце луча.
var _second: SkillVfx.Clip
var _glint: SkillVfx.Clip
## Тени героя на рывке — отдельный узел без материала атласа: лист героя хранит цвет без предумножения.
var _ghosts: Node2D


static func from_data(data: Dictionary) -> CombatFx:
	var fx := CombatFx.new()
	fx.kind = data.get("type", &"pulse")
	fx.position = data.get("pos", Vector2.ZERO)
	fx.skill = StringName(data.get("skill", &""))
	var look_data := SkillVfx.look_of(fx.skill)
	fx.color = data.get("color", look_data.color if look_data != null else Color.WHITE)
	fx.radius = clampf(float(data.get("radius", 32.0)), 0.0, 1000.0)
	fx.arc_degrees = data.get("arc", 120.0)
	fx.direction = Vector2(data.get("dir", Vector2.RIGHT)).normalized()
	for p: Vector2 in data.get("points", PackedVector2Array()):
		fx.points.append(p - fx.position)
	fx.owner_peer = data.get("owner", 1)
	fx.count = clampi(int(data.get("count", 0)), 0, 32)
	fx.phase = data.get("phase", 0.0)
	fx.speed = data.get("speed", 0.0)
	fx.look = StringName(data.get("look", &""))
	fx.width = clampf(float(data.get("width", 8.0)), 1.0, 64.0)
	if fx.kind == &"orbit" or fx.kind == &"beam":
		fx._lifetime = clampf(float(data.get("duration", 1.0)), 0.05, 60.0)
	else:
		fx._lifetime = LIFETIME.get(fx.kind, 0.2)
	fx.z_index = 1
	fx._setup_vfx(look_data)
	return fx


## Облик навыка по виду следа и стихии; нет атласа или эффекта — след рисуется кодом.
func _setup_vfx(look_data: SkillVfx.Look) -> void:
	if look_data == null or not SkillVfx.available():
		return
	var element := look_data.element
	match kind:
		&"slash":
			_clip = SkillVfx.pick("slash", element)
		&"lightning":
			_clip = SkillVfx.pick("chain", element, &"lightning")
			_second = SkillVfx.pick("hit", element)
		&"pulse":
			_clip = SkillVfx.pick("burst", element)
		&"nova":
			_clip = SkillVfx.pick("nova", element)
		&"orbit":
			_clip = SkillVfx.clip(StringName("orb_" + (String(look) if look != &"" else "skull")))
		&"beam":
			_clip = SkillVfx.pick("beam", element)
			_second = SkillVfx.pick("beam_end", element)
		&"dash":
			_clip = SkillVfx.pick("dash", element)
	if _clip == null:
		return
	_look = look_data
	if _look.evolved:
		_glint = SkillVfx.clip(&"glint")
	material = SkillVfx.material
	_lifetime = VFX_LIFETIME.get(kind, _lifetime)
	if kind == &"dash":
		_ghosts = Node2D.new()
		_ghosts.draw.connect(_draw_ghosts)
		add_child(_ghosts)


func _ready() -> void:
	_world = World.of(self)
	var config := DataRegistry.VISUAL
	LightSources.add(self, Color(color, config.attack_light_energy), config.attack_radius(kind, radius))


## Свет следа (LightMap): вспышка гаснет за время жизни, орбита и луч проявляются и гаснут, как рисуются.
func light_scale() -> float:
	if kind == &"orbit" or kind == &"beam":
		return clampf(minf(_age, _lifetime - _age) / ORBIT_FADE, 0.0, 1.0) * (0.6 if kind == &"orbit" else 1.0)
	return 1.0 - _age / _lifetime


func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		set_process(false)
		natural_end = true  # отжил своё — так же у всех участников, событие о снятии не нужно (WorldNet)
		queue_free()
		return
	if (kind == &"orbit" or kind == &"beam") and _world != null:
		var master := _world.find_player(owner_peer)
		if master != null:
			global_position = master.global_position
	queue_redraw()
	if _ghosts != null:
		_ghosts.queue_redraw()


func _draw() -> void:
	var t := _age / _lifetime
	if _look != null:
		_draw_vfx(t)
		return
	var c := Color(color, 1.0 - t)
	match kind:
		&"slash":
			var a := direction.angle()
			var half := deg_to_rad(arc_degrees) / 2.0
			draw_arc(Vector2.ZERO, radius * (0.75 + 0.25 * t), a - half, a + half, 18, c, 4.0 * (1.0 - t) + 1.0)
		&"lightning":
			if points.size() >= 2:
				draw_polyline(points, c, 3.0)
				draw_polyline(points, Color(1, 1, 1, c.a), 1.0)
		&"pulse", &"nova":
			draw_circle(Vector2.ZERO, radius, Color(color, 0.15 * (1.0 - t)))
			draw_arc(Vector2.ZERO, radius * (0.6 + 0.4 * t), 0.0, TAU, 32, c, 1.5)
		&"orbit":
			_draw_orbit()
		&"beam":
			_draw_beam()
		&"dash":
			_draw_dash(t)


# --- Облик навыка (шаг 11.21) ---

func _draw_vfx(t: float) -> void:
	match kind:
		&"slash":
			_draw_slash_vfx(t)
		&"lightning":
			_draw_chain_vfx(t)
		&"pulse", &"nova":
			SkillVfx.draw_round(self, _clip, _clip.index_of(t), Vector2.ZERO, radius)
			if _glint != null:
				SkillVfx.draw(self, _glint, _glint.index_at(_age), Vector2.ZERO, 0.0, clampf(radius / 16.0, 0.8, 2.5),
						SkillVfx.tint(1.0 - t))
		&"orbit":
			_draw_orbit_vfx()
		&"beam":
			_draw_beam_vfx()
		&"dash":
			var end := direction * radius
			SkillVfx.draw_quad(self, _clip, _clip.index_of(t), Vector2.ZERO, end, maxf(width * 0.6, 6.0))


## Взмах: голова идёт по дуге от края к краю, хвост тянется следом и догоняет её к концу.
func _draw_slash_vfx(t: float) -> void:
	var half := deg_to_rad(arc_degrees) / 2.0
	var head := -half + 2.0 * half * ease(clampf(t / SLASH_SWEEP, 0.0, 1.0), 0.6)
	var tail := maxf(head - 2.0 * half * SLASH_TRAIL, -half)
	if t > SLASH_SWEEP:
		tail = lerpf(tail, head, (t - SLASH_SWEEP) / (1.0 - SLASH_SWEEP))
	if head - tail < 0.02:
		return
	var a := direction.angle()
	var alpha := 1.0 if t < 0.6 else (1.0 - t) / 0.4
	var segments := clampi(int(rad_to_deg(head - tail) / 10.0), 4, 32)
	SkillVfx.draw_arc_strip(self, _clip, _clip.index_at(_age), Vector2.ZERO, a + tail, a + head, radius * SLASH_INNER,
			radius * 1.05, SkillVfx.tint(alpha), segments)
	if _glint != null:
		SkillVfx.draw(self, _glint, _glint.index_at(_age), Vector2.from_angle(a + head) * radius * 0.85, 0.0, 0.8,
				SkillVfx.tint(alpha))


## Цепь: плитки разряда между точками (кадры мерцают вразнобой) и искры на каждой цели.
func _draw_chain_vfx(t: float) -> void:
	if points.size() < 2:
		return
	var tint := SkillVfx.tint(1.0 - t * t)
	var tile := _clip.size.x * SkillVfx.scale
	var half := _clip.size.y * SkillVfx.scale * 0.5
	var tick := int(_age * _clip.fps)
	for i in points.size() - 1:
		var from := points[i]
		var to := points[i + 1]
		var n := maxi(1, roundi(from.distance_to(to) / tile))
		for k in n:
			SkillVfx.draw_quad(self, _clip, (tick + i * 3 + k * 7) % _clip.count, from.lerp(to, float(k) / n),
					from.lerp(to, float(k + 1) / n), half, tint)
		if _second != null:
			SkillVfx.draw(self, _second, _second.index_of(t), to)


## Луч: текущие плитки на всю длину, брызги на конце и вспышка у героя.
func _draw_beam_vfx() -> void:
	var tint := SkillVfx.tint(clampf(minf(_age, _lifetime - _age) / ORBIT_FADE, 0.0, 1.0))
	var end := direction * radius
	var tile := _clip.size.x * SkillVfx.scale
	var half := maxf(width, 6.0)
	var n := maxi(1, ceili(radius / tile))
	var frame := _clip.index_at(_age)
	for k in n:
		SkillVfx.draw_quad(self, _clip, frame, end * (float(k) / n), end * (float(k + 1) / n), half, tint)
	if _second != null:
		SkillVfx.draw(self, _second, _second.index_at(_age), end, 0.0, clampf(width / 8.0, 0.8, 2.0), tint)
		SkillVfx.draw(self, _second, _second.index_at(_age + 0.3), Vector2.ZERO, 0.0, 0.6, tint)


## Орбита: те же углы, что считает хост; летучие мыши летят по касательной, черепа и пламя — прямо.
func _draw_orbit_vfx() -> void:
	if count <= 0:
		return
	var tint := SkillVfx.tint(clampf(minf(_age, _lifetime - _age) / ORBIT_FADE, 0.0, 1.0))
	var size := 1.15 if _look.evolved else 1.0
	for i in count:
		var angle := phase + speed * _age + TAU * i / count
		var pos := Vector2.RIGHT.rotated(angle) * radius
		var rot := angle + (PI / 2.0 if speed >= 0.0 else -PI / 2.0) if look == &"bats" else 0.0
		SkillVfx.draw(self, _clip, _clip.index_at(_age + i * 0.37), pos, rot, size, tint)
		if _glint != null:
			SkillVfx.draw(self, _glint, _glint.index_at(_age + i * 0.5), pos, 0.0, 0.6, tint)


## Тени героя вдоль рывка: текущий кадр его листа оттенком стихии, ближние к концу ярче.
func _draw_ghosts() -> void:
	var master := _world.find_player(owner_peer) if _world != null else null
	if master == null or master.body.texture == null:
		return
	var body := master.body
	var t := _age / _lifetime
	var cell := body.texture.get_size() / Vector2(body.hframes, body.vframes)
	var src := Rect2(Vector2(body.frame_coords) * cell, cell)
	var rect := body.get_rect()
	var dst := Rect2(rect.position * body.scale + body.position, rect.size * body.scale)
	if body.flip_h:
		dst = Rect2(dst.position.x + dst.size.x, dst.position.y, -dst.size.x, dst.size.y)
	var end := direction * radius
	var tint := color.lightened(0.35)
	for i in DASH_GHOSTS:
		var k := float(i + 1) / DASH_GHOSTS
		tint.a = clampf((1.0 - t) * (0.2 + 0.45 * k), 0.0, 1.0)
		_ghosts.draw_texture_rect_region(body.texture, Rect2(dst.position + end * k, dst.size), src, tint)


# --- Линии кода (без облика) ---

## Черепа (или летучие мыши) на орбите: угол тот же, что считает хост для попаданий.
func _draw_orbit() -> void:
	if count <= 0:
		return
	var alpha := clampf(minf(_age, _lifetime - _age) / ORBIT_FADE, 0.0, 1.0)
	for i in count:
		var pos := Vector2.RIGHT.rotated(phase + speed * _age + TAU * i / count) * radius
		if look == &"bats":
			_draw_bat(pos, alpha, i)
			continue
		if look == &"flames":
			_draw_flame(pos, alpha, i)
			continue
		draw_circle(pos, 4.5, Color(color, 0.25 * alpha))
		draw_circle(pos, 3.0, Color(color, alpha))
		draw_circle(pos + Vector2(-1, -0.5), 0.8, Color(0.1, 0.05, 0.05, alpha))
		draw_circle(pos + Vector2(1, -0.5), 0.8, Color(0.1, 0.05, 0.05, alpha))


## Летучая мышь: тельце и два крыла, которые машут (у каждой мыши своя фаза).
func _draw_bat(pos: Vector2, alpha: float, index: int) -> void:
	var flap := sin(_age * 18.0 + index * 1.7) * 2.0
	var body_color := Color(color, alpha)
	draw_circle(pos, 4.5, Color(color, 0.2 * alpha))
	for side in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			pos + Vector2(side * 1.0, 0.0), pos + Vector2(side * 5.0, -2.0 - flap),
			pos + Vector2(side * 4.0, 1.0), pos + Vector2(side * 2.5, 0.5),
		]), body_color)
	draw_circle(pos, 1.8, body_color.darkened(0.3))
	draw_circle(pos + Vector2(-0.7, -0.6), 0.45, Color(1.0, 0.25, 0.2, alpha))
	draw_circle(pos + Vector2(0.7, -0.6), 0.45, Color(1.0, 0.25, 0.2, alpha))


## Огненная сфера (Огненный круг, шаг 4): свечение, дрожащий язык пламени и белое ядро.
func _draw_flame(pos: Vector2, alpha: float, index: int) -> void:
	var flicker := sin(_age * 22.0 + index * 2.3) * 0.8
	draw_circle(pos, 5.5, Color(color, 0.22 * alpha))
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-2.6, 0.8), pos + Vector2(0.4 * flicker, -5.0 - flicker),
		pos + Vector2(2.6, 0.8), pos + Vector2(0.0, 2.8),
	]), Color(color, alpha))
	draw_circle(pos + Vector2(0, 0.6), 1.3, Color(1.0, 0.95, 0.75, alpha))


## Луч: широкое свечение, яркое ядро и мерцание по длине.
func _draw_beam() -> void:
	var alpha := clampf(minf(_age, _lifetime - _age) / ORBIT_FADE, 0.0, 1.0)
	var end := direction * radius
	var flicker := 0.85 + 0.15 * sin(_age * 40.0)
	draw_line(Vector2.ZERO, end, Color(color, 0.25 * alpha), width * flicker)
	draw_line(Vector2.ZERO, end, Color(color, 0.8 * alpha), width * 0.45)
	draw_line(Vector2.ZERO, end, Color(1, 1, 1, 0.7 * alpha), 1.0)
	draw_circle(end, width * 0.5 * flicker, Color(color, 0.5 * alpha))


## Рывок: полупрозрачные тени-силуэты вдоль пути, дальние гаснут раньше.
func _draw_dash(t: float) -> void:
	var end := direction * radius
	draw_line(Vector2.ZERO, end, Color(color, 0.35 * (1.0 - t)), width)
	for i in DASH_GHOSTS:
		var k := float(i + 1) / DASH_GHOSTS
		var alpha := clampf((1.0 - t) * (0.3 + 0.7 * k), 0.0, 1.0)
		var at := end * k
		draw_circle(at + Vector2(0, -6), 3.5, Color(color, alpha))
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(-3.5, -3), at + Vector2(3.5, -3), at + Vector2(4.5, 4), at + Vector2(-4.5, 4),
		]), Color(color, alpha * 0.8))
