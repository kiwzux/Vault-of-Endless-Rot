class_name Projectile
extends Node2D
## Снаряд: стрела героя, кинжал (dagger), костяное копьё (spear), серп (sickle — долетает до середины
## пути и возвращается), огненный шар (fireball — взрывается при попадании), искра кольца огня (ember),
## ледяной осколок (frost), осколок врага (hostile) или взрыв (blast, smite и acid —
## стоят на месте и через fuse секунд бьют всех в радиусе: взрыв элиты ранит героев, метеор, удар
## молнии и кислотная капля героя — врагов). Полёт детерминирован — позиция, направление, скорость, —
## поэтому клиенты ведут его сами без синхронизации; попадания считает только хост.
## Шаг 5, часть 2: к клиентам снаряд приходит событием в пачке кадра (ProjectileStream). Кончился сам (долетел,
## догорел, взорвался в срок — natural_end) — его убирает каждый участник сам; снятый раньше (попадание, сработавшая
## ловушка) хост снимает и у клиентов событием.
##
## Шаг 6 — телеграф (warn): предупреждение на земле без урона, круг (radius) или полоса (line: dir, range —
## длина, radius — полуширина). Заполняется, пока горит fuse, и исчезает: удар врага приходит следом.
## Хост ставит его так же, как снаряд, поэтому клиенты видят его без отдельной синхронизации.
## Зона врага (hostile) бьёт героев — огненный след элиты.
##
## Шаг 3 — навыки:
## - zone — зона на земле: бьёт всех внутри каждые tick секунд, пока не истечёт duration;
## - trap — ловушка: взводится за fuse секунд и срабатывает, когда враг подойдёт на trigger.
## Теги, статусы и приёмы навыка (раскол, рикошет, Вампиризм, взрыв убитого) хост ставит снаряду героя
## сам после спавна (arm): по сети они не нужны — клиент попаданий не считает. Раскол и рикошет —
## новые снаряды из точки попадания, а не поворот старого: полёт у клиентов остаётся детерминированным.
##
## Шаг 11.21 — облик навыка героя: кадры атласа эффектов (SkillVfx) по виду снаряда и стихии навыка (data.skill —
## id навыка вместо цвета): стрела, кинжал, копьё, серп, болт, огненный шар, ледяной осколок; удар с неба — печать
## на земле и падающий метеор (капля, глыба) или разряд в конце; зона — пятно с языками пламени (пузырями, искрами);
## ловушка — капкан или сеть. Попадание — искры стихии (SkillFxLayer): у хоста при ударе, у клиента — когда хост
## убрал снаряд раньше конца пути. Снаряды врагов и навык без облика рисуются кодом, как раньше.

const HIT_RADIUS := 4.0
## Серп вращается в полёте: оборотов на пиксель пути.
const SICKLE_SPIN := 0.12
## Раскол: осколки веером в этом секторе; летят на эту долю дальности, но не меньше SPLIT_MIN_RANGE.
const SPLIT_ARC := deg_to_rad(80.0)
const SPLIT_RANGE_SHARE := 0.5
const SPLIT_MIN_RANGE := 70.0
## Рикошет ищет следующего врага в этом радиусе от места попадания.
const RICOCHET_RANGE := 150.0
## Удар с неба (шаг 11.21): откуда падает метеор (направление полёта и высота, px мира), как вращается печать.
const FALL_DIR := Vector2(0.35, 1.0)
const FALL_HEIGHT := 90.0
const SIGIL_SPIN := 0.9
## Клиент: снаряд, который хост убрал ближе этой доли секунды полёта до конца пути, не попал — долетел.
const IMPACT_SLACK := 0.15
## Эволюция навыка: снаряд крупнее и с золотым блеском.
const EVOLVED_SIZE := 1.2

var kind: StringName
var direction := Vector2.RIGHT
var speed := 200.0
var max_distance := 300.0
var damage := 0.0
## Удачный удар (Удача, HoMM3): урон уже удвоен, флаг нужен для цифр урона.
var crit := false
## Сколько врагов снаряд прошивает насквозь сверх первого.
var pierce := 0
var hostile := false
var owner_peer := 1
var color := Color.WHITE
## blast, smite, acid, zone, trap: радиус. blast — задержка взрыва; trap — время взвода.
var blast_radius := 0.0
var fuse := 0.0
## Взрыв при первом попадании (огненный шар): радиус; 0 — снаряд просто бьёт цель.
var explode := 0.0
## Серп: на середине пути (или у стены) разворачивается назад и снова может ранить тех же врагов.
var returns := false
## zone и trap: сколько живут, с; zone — как часто бьёт; trap — на каком расстоянии срабатывает.
var lifetime := 0.0
var tick_interval := 0.5
var trigger_radius := 0.0
## warn: полоса вдоль direction длиной max_distance (рывок), иначе круг.
var line := false
## Взрыв врага сковывает героев холодом (морозная вспышка Ледяной элиты, Player.chill).
var chill := false

## Хост (arm): теги удара (маска), статусы (Array[StatusApplication]) и приёмы навыка.
var tags := 0
var statuses: Array = []
var leech := 0.0
var kill_blast_share := 0.0
var kill_blast_radius := 0.0
var split := 0
var split_share := 0.5
var ricochet := 0
## Навык-источник удара — для статистики забега (HitInfo.skill).
var skill: StringName

## Кончился сам — так же у всех участников, событие о снятии не нужно (WorldNet).
var natural_end := false

var _turned := false
var _fuse_total := 0.0
var _travelled := 0.0
var _age := 0.0
var _tick_left := 0.0
var _split_done := false
var _hit := {}
var _done := false
var _world: World

## Облик навыка (шаг 11.21); null — рисуется кодом.
var _look: SkillVfx.Look
var _clip: SkillVfx.Clip
## Второй слой: печать под ударом с неба, то, что поднимается над зоной.
var _second: SkillVfx.Clip
var _glint: SkillVfx.Clip
## Время анимации летящего снаряда и показанный кадр (перерисовка — только при смене кадра).
var _anim := 0.0
var _frame := -1
## Зона: где поднимаются языки пламени (x, y) и сдвиг их анимации (z).
var _rises := PackedVector3Array()


static func from_data(data: Dictionary) -> Projectile:
	var p := Projectile.new()
	p.kind = data.get("type", &"arrow")
	p.position = data.get("pos", Vector2.ZERO)
	p.direction = Vector2(data.get("dir", Vector2.RIGHT)).normalized()
	p.speed = data.get("speed", 200.0)
	p.max_distance = data.get("range", 300.0)
	p.damage = data.get("damage", 0.0)
	p.crit = data.get("crit", false)
	p.pierce = data.get("pierce", 0)
	p.hostile = data.get("hostile", false)
	p.owner_peer = data.get("owner", 1)
	p.skill = StringName(data.get("skill", &""))
	var look := SkillVfx.look_of(p.skill) if not p.hostile else null  # снаряд навыка несёт id навыка, а не цвет
	p.color = data.get("color", look.color if look != null else Color.WHITE)
	p.blast_radius = data.get("radius", 0.0)
	p.fuse = data.get("fuse", 0.0)
	p.explode = data.get("explode", 0.0)
	p.returns = data.get("return", false)
	p.lifetime = clampf(float(data.get("duration", 0.0)), 0.0, 60.0)
	p.tick_interval = maxf(float(data.get("tick", 0.5)), 0.05)
	p.trigger_radius = data.get("trigger", 0.0)
	p.line = data.get("line", false)
	p.chill = data.get("chill", false)
	p._fuse_total = p.fuse
	return p


## Хост: приёмы навыка для удара этого снаряда (SkillRuntime.shoot).
func arm(hit: HitInfo, stats: SkillStats) -> void:
	tags = hit.tags
	statuses = hit.statuses
	leech = hit.leech
	kill_blast_share = hit.kill_blast_share
	kill_blast_radius = hit.kill_blast_radius
	skill = hit.skill
	split = stats.split
	split_share = stats.split_share
	ricochet = stats.ricochet


func is_blast() -> bool:
	return kind == &"blast" or kind == &"smite" or kind == &"acid"


## Стоит на месте: взрыв, зона, ловушка, телеграф.
func is_ground() -> bool:
	return is_blast() or kind == &"zone" or kind == &"trap" or kind == &"warn"


func _ready() -> void:
	rotation = direction.angle() if not is_ground() or line else 0.0
	z_index = 0 if kind == &"zone" or kind == &"warn" else 1
	_world = World.of(self)
	var config := DataRegistry.VISUAL
	var light := config.attack_radius(kind, blast_radius)
	if light > 0.0:  # телеграф удара врага светит ярче: его надо видеть и в темноте (шаг 11.8)
		var telegraph := kind == &"warn" or hostile and is_ground()
		LightSources.add(self, Color(color, config.telegraph_light_energy if telegraph else config.attack_light_energy), light)
	_setup_vfx()


## Облик навыка героя по виду снаряда и стихии (шаг 11.21). Нет атласа или эффекта — снаряд рисуется кодом.
func _setup_vfx() -> void:
	if hostile or not SkillVfx.available():
		return
	_look = SkillVfx.look_of(skill)
	if _look == null:
		return
	var element := _look.element
	match kind:
		&"blast", &"acid":
			_clip = SkillVfx.pick("fall", element)
			_second = SkillVfx.pick("sigil", element)
		&"smite":
			_clip = SkillVfx.pick("smite", element, &"lightning")
			_second = SkillVfx.pick("sigil", element)
		&"zone":
			_clip = SkillVfx.pick("zone", element)
			_second = SkillVfx.pick("rise", element)
			_place_rises()
		&"trap":
			_clip = SkillVfx.pick("trap", element)
		&"warn":
			pass
		_:
			_clip = SkillVfx.pick("proj_" + String(kind), element)
	if _clip == null:
		_look = null
		return
	if _look.evolved:
		_glint = SkillVfx.clip(&"glint")
	material = SkillVfx.material


## Языки пламени над зоной: число — по радиусу, места — от позиции (у всех участников одинаковые).
func _place_rises() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position.round()))
	for i in clampi(int(blast_radius / 8.0), 2, 10):
		var at := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * blast_radius * 0.75
		_rises.append(Vector3(at.x, at.y, rng.randf() * 2.0))


## Свет снаряда (LightMap): взрыв и телеграф разгораются к удару, зона проявляется и гаснет, ловушка — ярче взведённая.
func light_scale() -> float:
	if _done:
		return 0.0
	if is_blast() or kind == &"warn":
		return 0.35 + 0.65 * clampf(1.0 - fuse / maxf(_fuse_total, 0.01), 0.0, 1.0)
	if kind == &"zone":
		return clampf(minf(_age, lifetime - _age) / 0.25, 0.0, 1.0)
	if kind == &"trap":
		return 1.0 if _age >= fuse else 0.4
	return 1.0


func _physics_process(delta: float) -> void:
	var started := PerfProbe.begin()
	_advance(delta)
	PerfProbe.add(&"projectiles", started)


func _advance(delta: float) -> void:
	if _done:
		return
	if is_blast():
		_tick_blast(delta)
		return
	if kind == &"warn":
		fuse -= delta
		queue_redraw()
		if fuse <= 0.0:
			_finish(true)
		return
	if kind == &"zone":
		_tick_zone(delta)
		return
	if kind == &"trap":
		_tick_trap(delta)
		return
	var step := speed * delta
	position += direction * step
	_travelled += step
	if kind == &"sickle":
		rotation = _travelled * SICKLE_SPIN
	if _clip != null and (_clip.count > 1 or _glint != null):
		_anim += delta
		var frame := _clip.index_at(_anim) * 64 + (_glint.index_at(_anim) if _glint != null else 0)
		if frame != _frame:
			_frame = frame
			queue_redraw()
	if returns and not _turned and (_travelled >= max_distance / 2.0 or _world.is_blocked(global_position)):
		_turn_back()
	elif _travelled >= max_distance or _world.is_blocked(global_position):
		_finish(true)
	elif multiplayer.is_server():
		_check_hits()


## Серп разворачивается и летит обратно столько же, сколько пролетел.
func _turn_back() -> void:
	_turned = true
	direction = -direction
	max_distance = _travelled * 2.0
	_hit.clear()


func _check_hits() -> void:
	if hostile:
		for p in _world.director.players_alive():
			if global_position.distance_to(p.global_position) <= HIT_RADIUS + Player.RADIUS:
				p.take_damage(damage)
				_finish()
				return
		return
	for e in _world.director.enemies_in_radius(global_position, HIT_RADIUS):
		var id := e.get_instance_id()
		if _hit.has(id):
			continue
		if explode > 0.0:  # огненный шар: взрыв задевает всех рядом, включая цель
			for victim in _world.director.enemies_in_radius(global_position, explode):
				victim.take_hit(_make_hit())
			_world.spawn_projectile(_burst_fields(explode))
			_finish()
			return
		_hit[id] = true
		var at := e.global_position
		e.take_hit(_make_hit())
		_impact(global_position)
		if split > 0 and not _split_done:
			_split_done = true
			_spawn_splits(at, id)
		if _hit.size() > pierce:
			if ricochet > 0:
				_ricochet_from(at)
			_finish()
			return


func _make_hit() -> HitInfo:
	var hit := HitInfo.make(damage, owner_peer, tags, crit, statuses)
	hit.leech = leech
	hit.kill_blast_share = kill_blast_share
	hit.kill_blast_radius = kill_blast_radius
	hit.skill = skill
	return hit


## Раскол: осколки веером из точки попадания, каждый со своей долей урона; первую цель не задевают.
func _spawn_splits(at: Vector2, first_id: int) -> void:
	var reach := maxf(max_distance * SPLIT_RANGE_SHARE, SPLIT_MIN_RANGE)
	for i in split:
		var t := 0.0 if split == 1 else float(i) / (split - 1) - 0.5
		_spawn_child(at, direction.rotated(t * SPLIT_ARC), damage * split_share, reach, 0, {first_id: true})


## Рикошет: новый снаряд к ближайшему врагу, которого этот ещё не ранил.
func _ricochet_from(at: Vector2) -> void:
	var next := _world.director.nearest_enemy(at, RICOCHET_RANGE, _hit)
	if next != null:
		_spawn_child(at, at.direction_to(next.global_position), damage, at.distance_to(next.global_position) + 30.0,
				ricochet - 1, _hit.duplicate())


func _spawn_child(from: Vector2, dir: Vector2, child_damage: float, reach: float, bounces: int, skip: Dictionary) -> void:
	if _world.projectiles_full():
		return  # предел снарядов (шаг 5): осколок или рикошет не создаётся
	var fields := {
		"type": kind, "pos": from, "dir": dir, "speed": speed, "range": reach, "damage": child_damage, "crit": crit,
		"pierce": 0, "hostile": false, "owner": owner_peer,
	}
	if skill != &"":
		fields["skill"] = skill  # облик и цвет — по навыку, как у первого снаряда (шаг 11.21)
	else:
		fields["color"] = color
	var node := _world.spawn_projectile(fields)
	var child := node as Projectile
	if child == null:
		return
	child.tags = tags
	child.statuses = statuses
	child.leech = leech
	child.kill_blast_share = kill_blast_share
	child.kill_blast_radius = kill_blast_radius
	child.skill = skill
	child.ricochet = bounces
	child._split_done = true
	child._hit = skip


## Взрыв (импульс) на месте снаряда: у навыка — по навыку (облик его стихии), иначе — цветом снаряда.
func _burst_fields(radius: float) -> Dictionary:
	var fields := {"type": &"pulse", "pos": global_position, "radius": radius}
	if skill != &"" and not hostile:
		fields["skill"] = skill
	else:
		fields["color"] = color
	return fields


## Искры попадания стихии навыка (шаг 11.21) — только картинка, у каждого участника своя.
func _impact(at: Vector2) -> void:
	if _look == null or is_ground() or _world == null or _world.skill_fx == null:
		return
	_world.skill_fx.spawn(SkillVfx.pick("hit", _look.element), at, randf() * TAU)


## Клиент: хост снял снаряд раньше конца пути — снаряд попал в цель; искры там, где он сейчас.
func _exit_tree() -> void:
	if _done or _look == null or is_ground() or _world == null or not _world.is_inside_tree():
		return
	if not multiplayer.is_server() and _travelled < max_distance - speed * IMPACT_SLACK:
		_impact(global_position)


## natural — снаряд кончился сам (так же у всех участников); иначе его снял хост (попадание, срабатывание).
## Клиент свой снаряд не снимает раньше хоста: попаданий он не считает, ранний конец приходит событием.
func _finish(natural: bool = false) -> void:
	_done = true
	natural_end = natural
	queue_free()


## Предупреждающий круг растёт, пока горит фитиль; затем взрыв по всем целям в радиусе.
func _tick_blast(delta: float) -> void:
	fuse -= delta
	queue_redraw()
	if fuse > 0.0:
		return
	if hostile and _world != null:  # удар врага встряхивает камеру тем сильнее, чем ближе свой герой (шаг 11.9)
		_world.juice.impact(global_position, DataRegistry.VISUAL.shake_hostile_blast)
	if kind == &"smite" and _look != null and _world != null and _world.skill_fx != null:
		_world.skill_fx.spawn(_clip, global_position)  # разряд или столп света бьёт в цель (шаг 11.21)
		_world.sfx.strike(_look.element, global_position)  # и гром или тяжёлый удар со звоном (шаг 11.27)
	if multiplayer.is_server():
		if hostile:
			for p in _world.director.players_alive():
				if global_position.distance_to(p.global_position) <= blast_radius + Player.RADIUS:
					p.take_damage(damage)
					if chill:
						p.chill()
		else:
			for e in _world.director.enemies_in_radius(global_position, blast_radius):
				e.take_hit(_make_hit())
		_world.spawn_projectile(_burst_fields(blast_radius))
	_finish(true)


## Зона: удар по всем внутри сразу и дальше каждые tick_interval секунд, пока не истечёт lifetime.
func _tick_zone(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= lifetime:
		_finish(true)
		return
	if not multiplayer.is_server():
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left += tick_interval
	if hostile:  # зона врага (огненный след элиты) жжёт героев
		for p in _world.director.players_alive():
			if global_position.distance_to(p.global_position) <= blast_radius + Player.RADIUS:
				p.take_damage(damage)
		return
	for e in _world.director.enemies_in_radius(global_position, blast_radius):
		e.take_hit(_make_hit())


## Ловушка: после взвода (fuse) ждёт врага на trigger_radius и бьёт по своей области один раз.
func _tick_trap(delta: float) -> void:
	var armed_before := _age >= fuse
	_age += delta
	if armed_before != (_age >= fuse):
		queue_redraw()
	if lifetime > 0.0 and _age >= lifetime:
		_finish(true)
		return
	if not multiplayer.is_server() or _age < fuse:
		return
	if _world.director.nearest_enemy(global_position, trigger_radius) == null:
		return
	for e in _world.director.enemies_in_radius(global_position, blast_radius):
		e.take_hit(_make_hit())
	_world.spawn_projectile(_burst_fields(blast_radius))
	_finish()


func _draw() -> void:
	if _look != null:
		_draw_vfx()
		return
	if is_blast():
		var t := 1.0 - fuse / maxf(_fuse_total, 0.01)
		draw_circle(Vector2.ZERO, blast_radius, Color(color, 0.12 + 0.2 * t))
		draw_arc(Vector2.ZERO, blast_radius * t, 0.0, TAU, 32, Color(color, 0.8), 1.5)
		if kind == &"smite":  # удар молнии: ломаная с неба
			var points := PackedVector2Array([Vector2(4, -90), Vector2(-3, -60), Vector2(4, -35), Vector2(-2, -12), Vector2.ZERO])
			draw_polyline(points, Color(color, 0.4 + 0.6 * t), 3.0)
			draw_polyline(points, Color(1, 1, 1, 0.5 + 0.5 * t), 1.0)
		elif kind == &"acid":  # кислотная капля падает с неба
			var drop := Vector2(0, -36.0 * (1.0 - t))
			draw_colored_polygon(PackedVector2Array([
				drop + Vector2(0, -4), drop + Vector2(2, 0), drop + Vector2(0, 2), drop + Vector2(-2, 0),
			]), color.lightened(0.2))
		elif not hostile:  # метеор: падающий огненный шар сходится к центру взрыва
			draw_circle(Vector2(0, -40.0 * (1.0 - t)), 3.0 + 2.0 * t, color.lightened(0.3))
	elif kind == &"warn":
		_draw_warn()
	elif kind == &"zone":
		_draw_zone()
	elif kind == &"trap":
		_draw_trap()
	elif kind == &"fireball":
		draw_circle(Vector2.ZERO, 5.0, Color(color, 0.35))
		draw_circle(Vector2.ZERO, 3.5, color)
		draw_circle(Vector2(1, 0), 1.8, Color(1, 0.95, 0.7))
	elif kind == &"ember":
		draw_circle(Vector2.ZERO, 3.0, Color(color, 0.4))
		draw_circle(Vector2.ZERO, 2.0, color.lightened(0.3))
	elif kind == &"shard":
		draw_circle(Vector2.ZERO, 3.0, color)
		draw_circle(Vector2.ZERO, 1.5, Color(1, 0.9, 0.7))
	elif kind == &"frost":
		draw_colored_polygon(PackedVector2Array([
			Vector2(5, 0), Vector2(0, -2.5), Vector2(-4, 0), Vector2(0, 2.5),
		]), color)
		draw_line(Vector2(-4, 0), Vector2(4, 0), Color(1, 1, 1, 0.8), 1.0)
	elif kind == &"dagger":  # клинок и тёмная рукоять
		draw_colored_polygon(PackedVector2Array([Vector2(6, 0), Vector2(0, -1.6), Vector2(-2, 0), Vector2(0, 1.6)]), color)
		draw_line(Vector2(-2, -2.5), Vector2(-2, 2.5), color.darkened(0.3), 1.0)
		draw_line(Vector2(-2, 0), Vector2(-5, 0), Color(0.35, 0.22, 0.12), 1.5)
	elif kind == &"spear":  # длинное древко и наконечник
		draw_line(Vector2(-11, 0), Vector2(4, 0), color.darkened(0.15), 1.5)
		draw_colored_polygon(PackedVector2Array([Vector2(9, 0), Vector2(3, -2.5), Vector2(4, 0), Vector2(3, 2.5)]), color)
	elif kind == &"sickle":  # серп: полумесяц, вращается в полёте
		draw_arc(Vector2.ZERO, 6.0, -PI * 0.15, PI * 1.05, 12, color, 2.0)
		draw_arc(Vector2.ZERO, 6.0, -PI * 0.15, PI * 1.05, 12, Color(1, 1, 1, 0.6), 0.8)
		draw_line(Vector2(-6, 1), Vector2(-3, 5), Color(0.35, 0.22, 0.12), 1.5)
	elif kind == &"bolt":  # арбалетный болт: древко и широкий наконечник, светлый блик
		draw_line(Vector2(-7, 0), Vector2(3, 0), color.darkened(0.35), 1.5)
		draw_colored_polygon(PackedVector2Array([Vector2(7, 0), Vector2(2, -2.5), Vector2(3, 0), Vector2(2, 2.5)]), color)
		draw_line(Vector2(-7, -1.5), Vector2(-5, 0), color, 1.0)
		draw_line(Vector2(-7, 1.5), Vector2(-5, 0), color, 1.0)
	else:
		draw_line(Vector2(-6, 0), Vector2(3, 0), color, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(6, 0), Vector2(2, -2), Vector2(2, 2)]), color)


## Облик навыка (шаг 11.21). Цвета кода — с предумножением (SkillVfx.tint): материал узла — как у атласа.
func _draw_vfx() -> void:
	var size := EVOLVED_SIZE if _look.evolved else 1.0
	if is_blast():
		var t := clampf(1.0 - fuse / maxf(_fuse_total, 0.01), 0.0, 1.0)
		SkillVfx.draw_round(self, _second, 0, Vector2.ZERO, blast_radius, t * SIGIL_SPIN, SkillVfx.tint(0.35 + 0.65 * t))
		draw_arc(Vector2.ZERO, blast_radius * t, 0.0, TAU, 32, SkillVfx.tint(0.6, color), 1.5)
		if kind != &"smite":  # метеор (капля, глыба) падает к центру, под ним растёт тень
			var dir := FALL_DIR.normalized()
			draw_circle(Vector2.ZERO, 2.0 + 4.0 * t, Color(0, 0, 0, 0.35 * t))
			SkillVfx.draw(self, _clip, _clip.index_at(_fuse_total - fuse), -dir * FALL_HEIGHT * (1.0 - t),
					Vector2.DOWN.angle_to(dir), size)
		return
	if kind == &"zone":
		var alpha := clampf(minf(_age, lifetime - _age) / 0.25, 0.0, 1.0)
		SkillVfx.draw_round(self, _clip, _clip.index_at(_age), Vector2.ZERO, blast_radius, 0.0, SkillVfx.tint(alpha))
		if _second != null:
			for r in _rises:
				SkillVfx.draw(self, _second, _second.index_at(_age + r.z), Vector2(r.x, r.y), 0.0, 1.0, SkillVfx.tint(alpha))
		return
	if kind == &"trap":
		var armed := _age >= fuse
		SkillVfx.draw(self, _clip, 1 if armed else 0, Vector2.ZERO)
		if armed:
			draw_arc(Vector2.ZERO, trigger_radius, 0.0, TAU, 24, SkillVfx.tint(0.25, color), 1.0)
		return
	SkillVfx.draw(self, _clip, _clip.index_at(_anim), Vector2.ZERO, 0.0, size)
	if _glint != null:
		SkillVfx.draw(self, _glint, _glint.index_at(_anim), Vector2.ZERO, 0.0, 0.8)


## Телеграф: тусклая область удара и яркая заливка, которая доходит до края к моменту удара.
func _draw_warn() -> void:
	var t := clampf(1.0 - fuse / maxf(_fuse_total, 0.01), 0.0, 1.0)
	var edge := Color(color.lightened(0.2), 0.55 + 0.4 * t)
	if line:
		var area := Rect2(0.0, -blast_radius, max_distance, blast_radius * 2.0)
		draw_rect(area, Color(color, 0.12))
		draw_rect(Rect2(area.position, Vector2(max_distance * t, area.size.y)), Color(color, 0.3))
		draw_rect(area, edge, false, 1.5)
	else:
		draw_circle(Vector2.ZERO, blast_radius, Color(color, 0.16))
		draw_circle(Vector2.ZERO, blast_radius * t, Color(color, 0.3))
		draw_arc(Vector2.ZERO, blast_radius, 0.0, TAU, 32, edge, 1.5)


## Зона: пятно с мерцающей кромкой; проявляется и гаснет за 0.25 с.
func _draw_zone() -> void:
	var alpha := clampf(minf(_age, lifetime - _age) / 0.25, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_age * 6.0)
	draw_circle(Vector2.ZERO, blast_radius, Color(color, (0.16 + 0.06 * pulse) * alpha))
	draw_circle(Vector2.ZERO, blast_radius * 0.6, Color(color, 0.12 * alpha))
	draw_arc(Vector2.ZERO, blast_radius, 0.0, TAU, 32, Color(color.lightened(0.2), 0.7 * alpha), 1.0)


## Ловушка: невзведённая — тусклые сомкнутые челюсти, взведённая — раскрытые, с кольцом срабатывания.
func _draw_trap() -> void:
	var armed := _age >= fuse
	var jaw := color if armed else color.darkened(0.4)
	var open := 3.5 if armed else 1.5
	draw_circle(Vector2.ZERO, 3.0, Color(0.15, 0.12, 0.1))
	draw_arc(Vector2(0, -open), 4.5, PI * 0.15, PI * 0.85, 8, jaw, 1.5)
	draw_arc(Vector2(0, open), 4.5, PI * 1.15, PI * 1.85, 8, jaw, 1.5)
	if armed:
		draw_arc(Vector2.ZERO, trigger_radius, 0.0, TAU, 24, Color(color, 0.25), 1.0)
