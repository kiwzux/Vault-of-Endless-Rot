class_name StatusSystem
extends Node
## Хост: статусные эффекты на врагах (шаг 2, R3). Накладывает (шанс, стаки, сила, длительность), тикает
## урон со временем, снимает истёкшие и запускает реакции (StatusReaction). Обновляется тиками TICK
## (10 раз в секунду), а не каждый кадр: 300 горящих врагов — 3000 проходов в секунду, а не 18 000.
##
## Сеть: эффекты считает только хост. Клиенты видят их оттенком врага — биты StatusEffectData.visual_bit
## во флагах снимка врага (EnemySnapshot, без лишних байт). Взрыв реакции виден всем (вспышка идёт
## через спавнер снарядов), а надпись реакции пока только хосту: пачка визуальных событий для клиентов —
## шаг 5 (снаряды и эффекты событиями).

const TICK := 0.1


## Эффект на одном враге.
class Active:
	var data: StatusEffectData
	var stacks := 0
	var time_left := 0.0
	## Урон в секунду за стак и сила замедления — от сильнейшего наложения.
	var dps := 0.0
	var potency := 0.0
	## Кому засчитывается урон и убийство.
	var source_peer := 0
	## Навык, наложивший эффект: ему засчитывается урон со временем (статистика забега, RunStats).
	var skill: StringName
	var tick_left := 0.0


## Сколько реакций сработало за уровень (для проверок).
var reactions_total := 0

var _world: World
var _rng := RandomNumberGenerator.new()
## instance id врагов, на которых есть эффекты (узел мог уже исчезнуть — проверка через instance_from_id).
var _afflicted := {}
var _clock := 0.0


func _ready() -> void:
	_world = World.of(self)
	Events.level_loaded.connect(_on_level_loaded)


func _on_level_loaded(_level: LevelData) -> void:
	_afflicted.clear()
	_clock = 0.0
	reactions_total = 0
	_rng.seed = hash([RunConfig.run_seed, GameState.level_index, "statuses"])


## Удар hit прошёл по живому врагу: бросить шанс каждого наложения из hit.statuses.
func apply_from_hit(enemy: Enemy, hit: HitInfo) -> void:
	for app: StatusApplication in hit.statuses:
		if app == null or (app.chance < 1.0 and _rng.randf() >= app.chance):
			continue
		apply(enemy, app.status, hit.amount, hit.source_peer, app.stacks, app.potency, app.duration, hit.skill)
		if enemy.dead:
			return


## Наложить эффект id. base_damage — урон удара, от него считается урон со временем и взрыв реакции.
## skill — навык-источник для статистики забега. false — враг не подходит, эффекта нет или длительность
## ушла в ноль (контроль на боссе).
func apply(enemy: Enemy, id: StringName, base_damage: float = 0.0, source_peer: int = 0, stacks: int = 1,
		potency: float = 1.0, duration: float = 0.0, skill: StringName = &"") -> bool:
	if not multiplayer.is_server() or enemy == null or enemy.dead or enemy.ally:
		return false
	var data := DataRegistry.status(id)
	if data == null:
		return false
	var time := duration if duration > 0.0 else data.duration
	if enemy.data.is_boss and (data.stun or data.fear):
		time *= 1.0 - data.boss_resist
	if time <= 0.0:
		return false
	var active: Active = enemy.statuses.get(id)
	if active == null:
		active = Active.new()
		active.data = data
		active.tick_left = data.tick_interval
		enemy.statuses[id] = active
	active.stacks = mini(active.stacks + maxi(stacks, 1), data.max_stacks)
	active.time_left = maxf(active.time_left, time)
	active.dps = maxf(active.dps, base_damage * data.dot_share * potency)
	active.potency = maxf(active.potency, potency)
	if source_peer > 0:
		active.source_peer = source_peer
		active.skill = skill
	_afflicted[enemy.get_instance_id()] = true
	refresh(enemy)
	_react(enemy, id, base_damage, source_peer, skill)
	return true


## Снять эффект целиком.
func remove(enemy: Enemy, id: StringName) -> void:
	if enemy.statuses.erase(id):
		refresh(enemy)


func stacks_of(enemy: Enemy, id: StringName) -> int:
	var active: Active = enemy.statuses.get(id)
	return active.stacks if active != null else 0


## Пересчитать, как эффекты меняют врага: замедление, оглушение, страх, уязвимость, флаги для клиентов.
func refresh(enemy: Enemy) -> void:
	var slow := 0.0
	var stun := false
	var fear := false
	var vulnerability := 0.0
	var flags := 0
	for active: Active in enemy.statuses.values():
		var data := active.data
		var resist := data.boss_resist if enemy.data.is_boss else 0.0
		slow = maxf(slow, data.slow * active.potency * (1.0 - resist))
		stun = stun or data.stun
		fear = fear or data.fear
		vulnerability += data.vulnerability_per_stack * active.stacks
		if data.visual_bit > 0:
			flags |= 1 << data.visual_bit
	enemy.set_status_effects(clampf(slow, 0.0, 0.9), stun, fear, vulnerability, flags)


func _physics_process(delta: float) -> void:
	if _afflicted.is_empty() or not multiplayer.is_server():
		return
	_clock += delta
	if _clock < TICK:
		return
	var step := _clock
	_clock = 0.0
	var started := PerfProbe.begin()
	for key: int in _afflicted.keys():
		var enemy := instance_from_id(key) as Enemy
		if enemy == null or enemy.dead:
			_afflicted.erase(key)
			continue
		_tick(enemy, step)
		if not is_instance_valid(enemy) or enemy.dead or enemy.statuses.is_empty():
			_afflicted.erase(key)
	PerfProbe.add(&"statuses", started)


## Урон со временем и истечение эффектов одного врага за шаг step секунд.
func _tick(enemy: Enemy, step: float) -> void:
	var expired := false
	for id: StringName in enemy.statuses.keys():
		var active: Active = enemy.statuses.get(id)
		if active == null:
			continue  # снят реакцией в этом же шаге
		if active.dps > 0.0:
			active.tick_left -= step
			if active.tick_left <= 0.0:
				active.tick_left += active.data.tick_interval
				var hit := HitInfo.make(active.dps * active.stacks * active.data.tick_interval, active.source_peer,
						DataRegistry.status_mask(active.data.id))
				hit.is_dot = true
				hit.skill = active.skill
				enemy.take_hit(hit)
				if enemy.dead:
					return
		active.time_left -= step
		if active.time_left <= 0.0:
			enemy.statuses.erase(id)
			expired = true
	if expired:
		refresh(enemy)


## На врага лёг эффект trigger: проверить реакции, которые он запускает.
func _react(enemy: Enemy, trigger: StringName, base_damage: float, source_peer: int, skill: StringName) -> void:
	for reaction: StatusReaction in DataRegistry.STATUS_REACTIONS:
		if reaction.trigger != trigger:
			continue
		var held: Active = enemy.statuses.get(reaction.requires)
		if held == null or held.stacks < reaction.min_stacks:
			continue
		var stacks := held.stacks
		if reaction.consume:
			enemy.statuses.erase(reaction.requires)
			refresh(enemy)
		reactions_total += 1
		var pos := enemy.global_position
		Events.status_reaction.emit(enemy.label_position(), reaction.id)
		if reaction.burst_share > 0.0:
			var damage := base_damage * reaction.burst_share * stacks
			var mask := DataRegistry.tag_mask(reaction.burst_tags)
			if reaction.burst_radius > 0.0:
				for victim in _world.director.enemies_in_radius(pos, reaction.burst_radius):
					victim.take_hit(_burst_hit(damage, source_peer, mask, skill))
				_world.spawn_projectile({"type": &"pulse", "pos": pos, "radius": reaction.burst_radius, "color": reaction.color})
			else:
				enemy.take_hit(_burst_hit(damage, source_peer, mask, skill))
		if enemy.dead:
			return
		if reaction.apply_status != &"":
			apply(enemy, reaction.apply_status, base_damage, source_peer, 1, 1.0, 0.0, skill)


static func _burst_hit(damage: float, source_peer: int, mask: int, skill: StringName) -> HitInfo:
	var hit := HitInfo.make(damage, source_peer, mask)
	hit.skill = skill
	return hit
