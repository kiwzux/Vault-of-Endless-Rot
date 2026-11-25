class_name ProjectileFactory
extends RefCounted
## Фабрика узлов контейнера World/Projectiles: снаряды и визуальные следы атак.
## data — словарь из простых типов (тип, позиция, направление...); клиенты получают его пачкой событий
## (ProjectileStream, WorldNet._fire_batch) и строят по нему тот же узел (DESIGN 5.1).
##
## Анимация удара (шаги 11.1, 11.2): узел снаряда или следа создаётся и у хоста, и у клиентов, поэтому здесь же
## герой-владелец (data.owner) или враг-стрелок получает play_attack — без отдельной синхронизации.
## Удар с неба, зона и ловушка встают у цели — герой играет каст (шаг 11.19), снаряды и следы — удар.

## Снаряды (Projectile) и следы атак (CombatFx). Номер вида в этом списке уходит по сети (ProjectileStream):
## новые — только в конец.
const PROJECTILE_KINDS: Array[StringName] = [&"arrow", &"shard", &"blast", &"frost", &"fireball", &"ember", &"smite",
	&"dagger", &"spear", &"sickle", &"acid", &"bolt", &"zone", &"trap", &"warn"]
const FX_KINDS: Array[StringName] = [&"slash", &"lightning", &"pulse", &"nova", &"orbit", &"beam", &"dash"]
const KINDS: Array[StringName] = PROJECTILE_KINDS + FX_KINDS
## Следы, которые не значат нового удара: взрыв и волна ауры (nova) расходятся сами, орбита висит постоянно.
const AMBIENT_KINDS: Array[StringName] = [&"pulse", &"nova", &"orbit"]
## Без вспышки выстрела у руки (шаг 11.21): взмах и рывок сами идут от героя, поставленное у цели — каст.
const NO_FLASH_KINDS: Array[StringName] = [&"slash", &"dash"]
## Ставятся у цели, а не вылетают из героя: удар засчитывается, как бы далеко они ни были.
const PLACED_KINDS: Array[StringName] = [&"zone", &"trap"]
## Снаряд дальше этого от героя — осколок или рикошет из точки попадания, а не новый удар, px.
const CAST_REACH := 40.0
## Стрелок — ближайший враг не дальше этого от точки вылета: у клиента позиция врага чуть отстаёт от хоста, px.
const SHOOTER_REACH := 14.0
## Взрыв (pulse) от этого радиуса — со звуком взрыва (шаг 11.27); меньше — вспышка переноса или лечения, px.
const EXPLODE_RADIUS := 20.0

## Кольцо босса — десяток снарядов из одной точки за кадр: стрелок ищется один раз.
static var _shooter_frame := -1
static var _shooter_from := Vector2.INF
static var _shooter_id := 0


static func create(data: Dictionary) -> Node2D:
	var node: Node2D = null
	var kind := StringName(data.get("type", &""))
	if kind in PROJECTILE_KINDS:
		node = Projectile.from_data(data)
	elif kind in FX_KINDS:
		node = CombatFx.from_data(data)
	if node != null and _is_hero_cast(data):
		node.ready.connect(_play_caster_attack.bind(node, data), CONNECT_ONE_SHOT)
	elif node != null and _is_enemy_shot(data):
		node.ready.connect(_play_shooter_attack.bind(node, data), CONNECT_ONE_SHOT)
	if node != null and (kind == &"warn" or kind == &"pulse" and float(data.get("radius", 0.0)) >= EXPLODE_RADIUS):
		node.ready.connect(_play_sound.bind(node, &"warn" if kind == &"warn" else &"explode"), CONNECT_ONE_SHOT)
	return node


## Звук узла (шаг 11.27): телеграф удара и взрыв — у каждого участника, где узел появился.
static func _play_sound(node: Node2D, id: StringName) -> void:
	var world := World.of(node)
	if world != null and world.sfx != null:
		world.sfx.play(id, node.global_position)


static func _is_hero_cast(data: Dictionary) -> bool:
	return data.has("owner") and not data.get("hostile", false) \
			and not StringName(data.get("type", &"")) in AMBIENT_KINDS


## Выстрел и кольцо врага вылетают из стрелка, навесной огонь несёт from. Взрывы смерти и самоподрыва — нет.
static func _is_enemy_shot(data: Dictionary) -> bool:
	return data.get("hostile", false) and (StringName(data.get("type", &"")) == &"shard" or data.has("from"))


static func _play_shooter_attack(node: Node2D, data: Dictionary) -> void:
	var world := World.of(node)
	if world == null:
		return
	var from: Vector2 = data.get("from", data.get("pos", Vector2.ZERO))
	var frame := Engine.get_process_frames()
	if frame != _shooter_frame or from != _shooter_from:
		_shooter_frame = frame
		_shooter_from = from
		var found := world.enemy_near(from, SHOOTER_REACH)
		_shooter_id = found.get_instance_id() if found != null else 0
	var shooter := instance_from_id(_shooter_id) as Enemy if _shooter_id != 0 else null
	if shooter != null:
		var dir: Vector2 = data.get("dir", Vector2.ZERO)
		shooter.play_attack(dir if dir != Vector2.ZERO else Vector2(data.get("pos", from)) - from)
	if world.sfx != null:
		world.sfx.play(&"enemy_shot", from)  # кольцо из десятка снарядов за кадр — один звук (перерыв SfxData)


static func _play_caster_attack(node: Node2D, data: Dictionary) -> void:
	var world := World.of(node)
	var player := world.find_player(int(data["owner"])) if world != null else null
	if player == null:
		return
	var origin := player.global_position
	var pos: Vector2 = data.get("pos", origin)
	# Удар с неба (fuse) и зона с ловушкой встают у цели; остальное вылетает из героя.
	var placed := data.has("fuse") or StringName(data.get("type", &"")) in PLACED_KINDS
	if not placed and pos.distance_to(origin) > CAST_REACH:
		return
	var dir: Vector2 = data.get("dir", Vector2.ZERO)
	var points: PackedVector2Array = data.get("points", PackedVector2Array())
	if dir == Vector2.ZERO:
		dir = (points[0] if not points.is_empty() else pos) - origin  # цепь молний — к первой цели
	player.play_attack(dir, placed)  # шаг 11.19: поставленное у цели — заклинание (каст), остальное — удар
	var look := SkillVfx.look_of(StringName(data.get("skill", &"")))
	var kind := StringName(data.get("type", &""))
	if look != null and not placed and not kind in NO_FLASH_KINDS and SkillVfx.available():
		world.skill_fx.cast_flash(player, dir, look.element)  # шаг 11.21: вспышка у руки стихией навыка
	if world.sfx != null:  # шаг 11.27: звук удара — стихией навыка, у цели или у героя
		world.sfx.cast(look.element if look != null else SkillVfx.DEFAULT_ELEMENT, kind, pos if placed else origin)
