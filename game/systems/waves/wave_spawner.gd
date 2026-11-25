class_name WaveSpawner
extends Node
## Хост: волны врагов по таймеру уровня (ФТ-09). Таблица волн и босс — по биому этапа забега (RunPlan).
## Точка появления выбирается из вероятностной карты ENEMY_SPAWN, которую выдала модель
## (LevelData.spawn_weights, ФТ-03): враги лезут оттуда, где их «нарисовал» ИИ (DESIGN 6, фишка 7).
## С глубиной враги крепнут, чаще выходят улучшенным тиром (CR-09) и элитами-«чемпионами».
## Внутри уровня каждая следующая волна выпускает врагов чуть крепче и злее прежней — рост линейный
## и умеренный: собранный билд не позволяет стоять на месте, но и лавины к концу уровня нет.
## Боссов и мини-босса статуи рост волн не касается — их сила задана данными и глубиной.
## Число врагов в пачке растёт с этапом круга: 2-й уровень ×3, 3-й ×5 (count_mult); предел живых — max_alive.

## Не ближе этого к игрокам — враг появляется за краем экрана 640×360 или у его кромки.
const SAFE_DISTANCE := 180.0
## Если подходящих точек нет (игрок стоит у спавна), допускается ближе, но не вплотную.
const FALLBACK_DISTANCE := 96.0
const ATTEMPTS := 8
const JITTER := 10.0
## Рост силы врагов с глубиной и волнами, доля улучшенного тира и шанс элиты — BalanceConfig.
## Натиск (Алтарь испытания, CR-16): пока идёт, каждые SURGE_INTERVAL секунд сверх волн появляется
## SURGE_BATCH врагов текущей волны — крепче и злее, элиты втрое чаще; предел живых выше.
const SURGE_INTERVAL := 0.5
const SURGE_BATCH := 6
const SURGE_HEALTH_MULT := 1.6
const SURGE_DAMAGE_MULT := 1.3
const SURGE_ELITE_MULT := 3.0
const SURGE_ALIVE_MULT := 1.5

## Текущая таблица (по этапу забега); задаётся при загрузке уровня.
var table: WaveTable
var active := false
## Секунд натиска осталось (0 — натиска нет).
var surge_left := 0.0

var _world: World
var _rng := RandomNumberGenerator.new()
var _xp_rng := RandomNumberGenerator.new()
var _timers := PackedFloat32Array()
var _started := PackedByteArray()
var _cells: Array[Vector2i] = []
var _weights := PackedFloat32Array()
var _surge_timer := 0.0
## Дробная часть врагов от Проклятия — копится до целого.
var _curse_carry := 0.0
## Во сколько раз больше врагов в пачке на этом уровне (BalanceConfig.enemy_count_at: 2-й уровень ×3, 3-й ×5).
var count_mult := 1.0
## Алтарь проклятий (шаг 8): прибавки до конца уровня — здоровье и урон новых врагов, награда (опыт, золото,
## шанс лута). Сбрасываются с новым уровнем.
var level_curse_health := 0.0
var level_curse_damage := 0.0
var level_curse_reward := 0.0


func _ready() -> void:
	table = DataRegistry.wave_table_for(0)
	_world = World.of(self)
	Events.level_loaded.connect(_on_level_loaded)


func _on_level_loaded(level: LevelData) -> void:
	if not multiplayer.is_server():
		return
	table = DataRegistry.wave_table_for(GameState.level_index)
	_rng.seed = hash([RunConfig.run_seed, GameState.level_index, "waves"])
	_xp_rng.seed = hash([RunConfig.run_seed, GameState.level_index, "xp"])
	_timers.resize(table.waves.size())
	_timers.fill(0.0)
	_started.resize(table.waves.size())
	_started.fill(0)
	_build_spawn_map(level)
	active = true
	surge_left = 0.0
	_curse_carry = 0.0
	count_mult = DataRegistry.BALANCE.enemy_count_at(RunPlan.stage(GameState.level_index))
	level_curse_health = 0.0
	level_curse_damage = 0.0
	level_curse_reward = 0.0


func stop() -> void:
	active = false


## Алтарь проклятий: до конца уровня враги крепче, награда щедрее (складывается, если алтарей несколько).
func add_level_curse(health: float, damage: float, reward: float) -> void:
	level_curse_health += health
	level_curse_damage += damage
	level_curse_reward += reward


## Множитель награды уровня (опыт, золото, шанс лута) от алтарей проклятий.
func reward_mult() -> float:
	return 1.0 + level_curse_reward


## Натиск на duration секунд (Алтарь испытания). Идёт и когда обычные волны остановлены (босс).
func start_surge(duration: float) -> void:
	surge_left = duration
	_surge_timer = 0.0


func stop_surge() -> void:
	surge_left = 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if surge_left > 0.0 and _world.flow.phase not in [LevelFlow.Phase.DEFEAT, LevelFlow.Phase.VICTORY]:
		_tick_surge(delta)
	if not active or not GameState.running:
		return
	var time := GameState.LEVEL_DURATION - GameState.level_time_left
	var alive := _world.director.hostile_count()
	for i in table.waves.size():
		var wave := table.waves[i]
		if not wave.is_active(time):
			continue
		if _started[i] == 0:
			_started[i] = 1
			Events.wave_started.emit(i)
		_timers[i] -= delta
		if _timers[i] > 0.0:
			continue
		_timers[i] += wave.interval
		# Печать орды (шаг 12.3) — больше врагов в пачке; предел живых прежний (НФТ-07).
		_curse_carry += wave.batch * count_mult * (1.0 + _curse()) * RunConfig.seal_mult(SealData.Stat.WAVE_SIZE)
		var count := floori(_curse_carry)
		_curse_carry -= count
		for k in count:
			if alive >= table.max_alive:
				return
			if spawn_enemy(_tiered(wave.pick(_rng)), null, _roll_elite(), wave_stage()) != null:
				alive += 1


## Случайный враг текущей волны с тиром по глубине — для испытаний.
func pick_current_enemy() -> EnemyData:
	return _tiered(table.waves[wave_stage()].pick(_rng))


## Аффиксы элиты наверняка (стая Проклятого тотема).
func elite_affixes(count: int) -> PackedStringArray:
	return _roll_elite(1.0, count)


## Проклятие отряда: сильнейшее среди живых героев.
func _curse() -> float:
	var curse := 0.0
	for p in _world.director.players_alive():
		curse = maxf(curse, p.stat(Player.STAT_CURSE))
	return curse


func _tick_surge(delta: float) -> void:
	surge_left = maxf(surge_left - delta, 0.0)
	_surge_timer -= delta
	if _surge_timer > 0.0 or table.waves.is_empty():
		return
	_surge_timer += SURGE_INTERVAL
	var wave := table.waves[wave_stage()]
	var alive := _world.director.hostile_count()
	for k in SURGE_BATCH:
		if alive >= table.max_alive * SURGE_ALIVE_MULT:
			return
		var elite := _roll_elite(SURGE_ELITE_MULT)
		if spawn_enemy(_tiered(wave.pick(_rng)), null, elite, wave_stage(), SURGE_HEALTH_MULT, SURGE_DAMAGE_MULT) != null:
			alive += 1


## Номер последней начавшейся волны уровня (с нуля): от него растёт сила новых врагов.
func wave_stage() -> int:
	return maxi(_started.count(1) - 1, 0)


## Опыт за врага: кристалл крупнее с глубиной и с каждой волной уровня (BalanceConfig), дробная часть —
## шансом на лишнюю единицу.
func xp_reward(base: int) -> int:
	var value := base * DataRegistry.BALANCE.xp_mult(GameState.level_index, wave_stage()) * reward_mult() \
			* RunConfig.seal_mult(SealData.Stat.XP)  # печать тлена (шаг 12.3)
	var whole := floori(value)
	return whole + (1 if _xp_rng.randf() < value - whole else 0)


## pos == null — точка выбирается по карте спавна; null в ответе — подходящей точки нет.
## stage — номер волны для роста силы (у боссов и мини-босса 0).
## hp_bonus и dmg_bonus — сверх роста по глубине и волнам (натиск испытания).
## Шаг 6: в кооперативе здоровье растёт с числом героев (BalanceConfig.coop_health_mult) — и у боссов.
## Шаг 12: здоровье боссов растёт с глубиной по своей кривой — BalanceConfig.boss_health_at; урон босса
## сверх роста врагов — ×1,5…×2,5 (BalanceConfig.boss_damage_at); остальные враги — ×enemy_damage_scale (0,6).
func spawn_enemy(data: EnemyData, pos: Variant = null, elite: PackedStringArray = [], stage: int = 0,
		hp_bonus: float = 1.0, dmg_bonus: float = 1.0) -> Enemy:
	if pos == null:
		pos = pick_spawn_position()
	if pos == null:
		return null
	var depth := GameState.level_index
	var balance := DataRegistry.BALANCE
	var growth := balance.boss_health_at(depth) * RunConfig.seal_mult(SealData.Stat.BOSS_HEALTH) if data.is_boss \
			else balance.enemy_health_mult(depth, stage)  # печать тирана — только боссам (шаг 12.3)
	growth *= balance.cycle_health_at(RunPlan.cycle(depth))  # каждый круг забега — враги и боссы крепче
	var hits := balance.boss_damage_at(depth) if data.is_boss else balance.enemy_damage_scale
	return _world.spawn_enemy({
		"id": data.id,
		"pos": pos,
		"hp_mult": RunConfig.enemy_health_mult() * growth * hp_bonus
				* balance.coop_health_mult(_world.get_players().size()) * (1.0 + level_curse_health),
		"dmg_mult": RunConfig.enemy_damage_mult() * balance.enemy_damage_mult(depth, stage) * dmg_bonus * hits
				* (1.0 + level_curse_damage),
		"elite": elite,
	})


## CR-09: с глубиной враг всё чаще выходит улучшенным тиром (Скелет → Скелет-воин).
func _tiered(data: EnemyData) -> EnemyData:
	if data.upgrade != null and _rng.randf() < DataRegistry.BALANCE.tier_chance(GameState.level_index):
		return data.upgrade
	return data


## chance_mult — во сколько раз чаще обычного (натиск); affix_count > 0 — элита наверняка, с этим
## числом аффиксов (стая Проклятого тотема).
func _roll_elite(chance_mult: float = 1.0, affix_count: int = 0) -> PackedStringArray:
	var depth := GameState.level_index
	var affixes := PackedStringArray()
	var chance := DataRegistry.BALANCE.elite_chance(depth) * chance_mult \
			* DataRegistry.BALANCE.coop_elite_mult(_world.get_players().size()) \
			* RunConfig.seal_mult(SealData.Stat.ELITE_CHANCE)  # печать избранных (шаг 12.3)
	if affix_count <= 0 and _rng.randf() >= chance:
		return affixes
	var pool: Array = DataRegistry.ELITE_AFFIXES.duplicate()
	var count := affix_count if affix_count > 0 else DataRegistry.BALANCE.elite_affix_count(depth)
	for i in mini(count, pool.size()):
		affixes.append(String(pool.pop_at(_rng.randi_range(0, pool.size() - 1)).id))
	return affixes


## Случайная клетка по весам spawn_weights, подальше от игроков. null — подходящей точки нет.
func pick_spawn_position() -> Variant:
	if _cells.is_empty():
		return null
	for min_distance in [SAFE_DISTANCE, FALLBACK_DISTANCE]:
		for attempt in ATTEMPTS:
			var cell := _cells[_rng.rand_weighted(_weights)]
			var jitter := Vector2(_rng.randf_range(-JITTER, JITTER), _rng.randf_range(-JITTER, JITTER))
			var pos := _world.director.cell_center(cell) + jitter
			if _world.director.distance_to_nearest_player(pos) >= min_distance:
				return pos
	return null


## Клетки с ненулевой вероятностью ENEMY_SPAWN. Если карта весов пуста — метки ENEMY_SPAWN
## с равным весом (валидатор гарантирует хотя бы одну, ФТ-04).
func _build_spawn_map(level: LevelData) -> void:
	_cells.clear()
	_weights.clear()
	for y in level.size:
		for x in level.size:
			var cell := Vector2i(x, y)
			var w := level.get_spawn_weight(cell)
			if w > 0 and Palette.is_passable(level.get_tile(cell)):
				_cells.append(cell)
				_weights.append(float(w))
	if _cells.is_empty():
		for cell in level.find_cells(Palette.Tile.ENEMY_SPAWN):
			_cells.append(cell)
			_weights.append(1.0)
