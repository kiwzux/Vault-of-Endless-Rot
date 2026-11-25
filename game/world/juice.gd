class_name Juice
extends Node2D
## «Сочность» боя (шаг 11.9; техзадание, раздел 7) — дёшево и только у себя:
## - тряска камеры своего героя: сила складывается от событий и спадает (Settings.screen_shake);
## - стоп-кадр: время почти стоит долю секунды — только в одиночной игре, в кооперативе время общее (Settings.hit_stop);
## - искры и капли от ударов, брызги цветом врага при его смерти — один узел и один проход отрисовки, как цифры урона,
##   с пределом живых частиц по качеству эффектов.
## Пятна на месте смерти рисует EnemyCorpses, отдачу врага от удара — Enemy и WorldNet.
## Всё выводится из того, что у участника уже есть: удары (Events.damage_dealt — у клиентов пачкой от хоста),
## уход узла врага (Enemy → EnemyCorpses), рана своего героя (Player.flash_hit), взрывы (Projectile),
## события HUD (босс, тайник). Новых сетевых данных нет. Числа — VisualConfig (DataRegistry.VISUAL).

## Над картой света (LightMap.Z): искры светятся сами. Подписи (LightMap.LABEL_Z) — выше.
const Z := 92
const DRAG := 3.0

## Стоп-кадров сейчас идёт (перекрывающиеся продлевают друг друга); время вернётся, когда их не останется.
var stops := 0
## Текущая сила тряски, 0…1.
var trauma := 0.0

var _shake_time := 0.0
var _world: World
var _rng := RandomNumberGenerator.new()
## Частицы — параллельные массивы; умершая заменяется последней (порядок не важен).
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _color := PackedColorArray()


func _ready() -> void:
	_world = World.of(self)
	z_index = Z
	z_as_relative = false
	_rng.randomize()
	Events.damage_dealt.connect(_on_damage_dealt)
	Events.boss_spawned.connect(func(_boss: Node) -> void: shake(DataRegistry.VISUAL.shake_boss_spawn))
	Events.interactable_used.connect(_on_interactable_used)
	Events.level_loaded.connect(func(_level: LevelData) -> void: clear())
	set_process(false)


func _exit_tree() -> void:
	if stops > 0:
		Engine.time_scale = 1.0  # выход из уровня посреди стоп-кадра


## Сколько частиц живо (для проверок и стенда).
func particle_count() -> int:
	return _pos.size()


## Новый уровень: прежние частицы и тряска к нему не относятся.
func clear() -> void:
	_clear_particles()
	trauma = 0.0
	_apply_shake()


# --- Тряска ---

## strength — прибавка силы 0…1 (сумма не больше 1).
func shake(strength: float) -> void:
	if strength <= 0.0 or not Settings.screen_shake:
		return
	trauma = minf(trauma + strength, 1.0)
	set_process(true)


## Удар по области (взрыв врага): тряска тем слабее, чем дальше свой герой.
func impact(at: Vector2, strength: float) -> void:
	var me := _world.local_player() if _world != null else null
	if me == null:
		return
	var reach := DataRegistry.VISUAL.shake_blast_reach
	shake(strength * clampf(1.0 - me.global_position.distance_to(at) / reach, 0.0, 1.0))


func _apply_shake() -> void:
	var me := _world.local_player() if _world != null else null
	if me == null or me.camera == null:
		return
	if trauma <= 0.0:
		me.camera.offset = Vector2.ZERO
		return
	var config := DataRegistry.VISUAL
	var t := _shake_time * config.shake_frequency
	var wobble := Vector2(sin(t) + sin(t * 0.71 + 1.3), cos(t * 0.87) + sin(t * 1.31 + 0.4)) * 0.5
	me.camera.offset = wobble * config.shake_max_offset * trauma * trauma


# --- Стоп-кадр ---

func hit_stop(seconds: float) -> void:
	if not is_inside_tree():  # мир уже уходит со сцены (выход из забега, возврат отряда в Убежище)
		return
	if seconds <= 0.0 or not Settings.hit_stop or not multiplayer.get_peers().is_empty() or get_tree().paused:
		return
	stops += 1
	Engine.time_scale = DataRegistry.VISUAL.hit_stop_scale
	# Таймер в реальном времени (ignore_time_scale): сам стоп-кадр его не замедляет.
	get_tree().create_timer(seconds, true, false, true).timeout.connect(_release_stop)


func _release_stop() -> void:
	stops = maxi(stops - 1, 0)
	if stops == 0:
		Engine.time_scale = 1.0


# --- События ---

## Рана своего героя (Player.flash_hit у владельца героя). Красные края и аберрацию показывает PostFx.
func hero_hurt() -> void:
	var config := DataRegistry.VISUAL
	shake(config.shake_hero_hurt)
	hit_stop(config.stop_hero_hurt)
	var me := _world.local_player() if _world != null else null
	if me != null and me.max_health > 0.0:
		_world.post.hero_hurt(me.health / me.max_health)


## Узел врага ушёл (Enemy._exit_tree): брызги цветом врага; элита и босс — тряска и стоп-кадр.
## killed — смерть, а не очистка уровня (у клиента не отличить: уровень потом всё равно очистит clear()).
func enemy_gone(enemy: Enemy, killed: bool) -> void:
	if enemy.data == null or enemy.ally:
		return
	var config := DataRegistry.VISUAL
	var big := enemy.data.is_boss or enemy.is_elite() or enemy.data.loot_rarity >= 0
	burst(enemy.global_position + Vector2(0, -6), enemy.data.placeholder_color,
			config.elite_death_particles if big else config.death_particles, 1.3 if big else 1.0)
	if not killed or not big:
		return
	if enemy.data.is_boss:
		shake(config.shake_boss_death)
		hit_stop(config.stop_boss_death)
	else:
		shake(config.shake_elite_death)
		hit_stop(config.stop_elite_death)


func _on_damage_dealt(pos: Vector2, amount: float, crit: bool) -> void:
	if amount <= 0.0:
		return
	var config := DataRegistry.VISUAL
	var count := config.crit_sparks if crit else config.hit_sparks
	var at := pos + Vector2(0, 10)  # цифры урона встают над головой, искры — у тела
	var blood := roundi(count * config.hit_blood_share)
	burst(at, config.blood_color, blood, 0.8)
	burst(at, config.spark_color, count - blood, 1.2, 1.0)


func _on_interactable_used(_type_id: StringName, _peer_id: int, outcome: StringName) -> void:
	if outcome == &"secret":
		shake(DataRegistry.VISUAL.shake_secret)


# --- Частицы ---

## count частиц цвета color из точки at; speed — множитель скорости; size — сторона квадратика, px мира.
func burst(at: Vector2, color: Color, count: int, speed := 1.0, size := 1.5) -> void:
	var config := DataRegistry.VISUAL
	var limit := config.particle_limit(Settings.effects_quality)
	for i in mini(count, limit - _pos.size()):
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var velocity := dir * config.particle_speed * speed * _rng.randf_range(0.4, 1.0)
		velocity.y -= config.particle_speed * 0.35 * speed  # вылетают чуть вверх и падают
		_pos.append(at)
		_vel.append(velocity)
		_age.append(0.0)
		_life.append(config.particle_life * _rng.randf_range(0.6, 1.2))
		_size.append(size * _rng.randf_range(0.7, 1.3))
		_color.append(color.lightened(_rng.randf_range(-0.15, 0.2)))
	if not _pos.is_empty():
		set_process(true)


func _process(delta: float) -> void:
	var started := PerfProbe.begin()
	if trauma > 0.0:
		_shake_time += delta
		trauma = maxf(trauma - DataRegistry.VISUAL.shake_decay * delta, 0.0)
		_apply_shake()
	var gravity := DataRegistry.VISUAL.particle_gravity * delta
	var drag := exp(-DRAG * delta)
	var i := 0
	while i < _pos.size():
		_age[i] += delta
		if _age[i] >= _life[i]:
			_remove(i)
			continue
		_vel[i] = _vel[i] * drag + Vector2(0, gravity)
		_pos[i] += _vel[i] * delta
		i += 1
	queue_redraw()
	if trauma <= 0.0 and _pos.is_empty():
		set_process(false)
	PerfProbe.add(&"juice", started)


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	_pos[i] = _pos[last]
	_vel[i] = _vel[last]
	_age[i] = _age[last]
	_life[i] = _life[last]
	_size[i] = _size[last]
	_color[i] = _color[last]
	_pos.resize(last)
	_vel.resize(last)
	_age.resize(last)
	_life.resize(last)
	_size.resize(last)
	_color.resize(last)


## Packed-массивы копируются при присваивании, поэтому каждый очищается по имени.
func _clear_particles() -> void:
	_pos.clear()
	_vel.clear()
	_age.clear()
	_life.clear()
	_size.clear()
	_color.clear()
	queue_redraw()


func _draw() -> void:
	for i in _pos.size():
		var s := _size[i]
		var color := _color[i]
		color.a *= 1.0 - _age[i] / _life[i]
		draw_rect(Rect2(_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), color)
