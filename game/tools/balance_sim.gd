extends Node
## Симуляция баланса (шаг 12): бот проходит круг забега за каждого героя — настоящие волны, опыт, левел-апы,
## боссы — и время боя с каждым боссом пишет журнал боёв (BalanceLog) в свой файл; в конце — таблица.
## Бот — «сильный игрок» без умения уклоняться: герой неуязвим и стоит на месте (враги идут к нему), опыт с земли
## собирается весь, карты выбираются жадно (эволюция → прокачка своего навыка → новый навык → руна → пассивка).
## Босс сразу после появления встаёт рядом с героем (живой игрок сам идёт к нему), а если отошёл или застрял дальше
## PULL_DISTANCE дольше PULL_AFTER с — подтягивается снова; сколько раз — поле pulls в журнале (без этого
## стоящий бот не доставал боссов, державшихся на дистанции или за стеной, и бой кончался тайм-аутом).
## Экипировки, золота, талантов и святилищ у бота нет — живой игрок с ними сильнее: время боя здесь — верхняя оценка.
## Запуск: godot --headless --path game res://tools/balance_sim.tscn --fixed-fps 60
##           [-- --heroes=knight,necromancer] [--stages=4] [--boss-limit=240] [--seed=1] [--xp-share=1.0]
## --xp-share — доля кристаллов опыта, которую бот подбирает (остальные пропадают): 1 — весь опыт, верхняя оценка
## уровня героя; подбирается по журналу живой игры (на каком уровне игроки встречают боссов).
## Журнал — user://balance_sim.jsonl (дописывается; --fresh — начать заново).

const Table := preload("res://tools/balance_table.gd")
const LOG_PATH := "user://balance_sim.jsonl"
## Бой дольше этого (с игрового времени) — «timeout»: босс добивается, в журнал — оставшаяся доля здоровья.
const DEFAULT_BOSS_LIMIT := 240.0
## Как часто кристаллы опыта притягиваются к герою (живой игрок собирает их, пробегая по полю).
const COLLECT_INTERVAL := 0.5
## Босс дальше этого от героя — вне досягаемости большинства навыков; столько секунд подряд — подтянуть.
const PULL_DISTANCE := 160.0
const PULL_AFTER := 3.0
## На столько клеток от героя ставится босс.
const PULL_RING := 2
const CARD_EVOLUTION := 100.0
const CARD_OWNED_SKILL := 70.0
const CARD_NEW_SKILL := 60.0
const CARD_RUNE := 40.0
const CARD_PASSIVE := 30.0

var _world: World
var _hero_ids: Array[StringName] = []
var _stages := 4
var _boss_limit := DEFAULT_BOSS_LIMIT
var _seed := 1
var _xp_share := 1.0
var _xp_rng := RandomNumberGenerator.new()
var _collect_left := 0.0
var _first_entry := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var fresh := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--heroes="):
			for id in arg.trim_prefix("--heroes=").split(",", false):
				_hero_ids.append(StringName(id))
		elif arg.begins_with("--stages="):
			_stages = clampi(arg.trim_prefix("--stages=").to_int(), 1, 4)
		elif arg.begins_with("--boss-limit="):
			_boss_limit = maxf(arg.trim_prefix("--boss-limit=").to_float(), 10.0)
		elif arg.begins_with("--seed="):
			_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--xp-share="):
			_xp_share = clampf(arg.trim_prefix("--xp-share=").to_float(), 0.05, 1.0)
		elif arg == "--fresh":
			fresh = true
	if _hero_ids.is_empty():
		for hero: HeroData in DataRegistry.HEROES:
			_hero_ids.append(hero.id)
	BalanceLog.path = LOG_PATH
	if fresh:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH))
	_first_entry = Table.read(LOG_PATH).size()
	Settings.hit_stop = false  # замедление времени при ударах — только для глаз
	Events.level_up_offered.connect(func(peer_id: int, _cards: Array) -> void:
		if peer_id == 1:
			_pick_cards.call_deferred())
	for id in _hero_ids:
		var hero := DataRegistry.hero(id)
		if hero == null:
			printerr("нет героя %s" % id)
			continue
		await _run(hero)
	var entries := Table.read(LOG_PATH).slice(_first_entry)
	print("\nСимуляция: героев %d, этапов %d, боёв %d (журнал %s)" % [_hero_ids.size(), _stages, entries.size(),
			ProjectSettings.globalize_path(LOG_PATH)])
	print(Table.fights(entries))
	get_tree().quit()


func _physics_process(delta: float) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	_collect_left -= delta
	if _collect_left > 0.0:
		return
	_collect_left = COLLECT_INTERVAL
	var hero := _world.find_player(1)
	if hero == null:
		return
	for node in _world.pickups.get_children():
		if node is Pickup and node.kind == Pickup.Kind.XP and not node.is_queued_for_deletion():
			if _xp_rng.randf() < _xp_share:
				node.global_position = hero.global_position
			else:
				node.queue_free()  # этот кристалл «игрок» не подобрал


## Круг забега одним героем: этапы до логова, на каждом — волны до босса, бой, ключ и портал.
func _run(hero: HeroData) -> void:
	print("— %s" % hero.id)
	RunConfig.start_new_run(hero, false, hash([_seed, hero.id]))
	_xp_rng.seed = hash([_seed, hero.id, "xp"])
	_world = load(ScenePaths.WORLD).instantiate()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	await _wait_until(func() -> bool: return _world.find_player(1) != null, 30.0)
	var player := _world.find_player(1)
	if player == null:
		printerr("%s: герой не появился" % hero.id)
	else:
		player.invulnerable = true
		for stage in _stages:
			if not await _stage(player):
				break
	_world.queue_free()
	_world = null
	GameState.end_run()
	await _frames(2)


## Один этап: дождаться босса (таймер уровня), бой, затем ключ и портал. false — дальше идти нельзя.
func _stage(player: Player) -> bool:
	var index := GameState.level_index
	await _wait_until(func() -> bool: return _world.flow.boss != null, GameState.LEVEL_DURATION + 30.0)
	var boss := _world.flow.boss
	if boss == null:
		printerr("уровень %d: босс не появился" % (index + 1))
		return false
	var boss_id := boss.data_id
	var log := _world.get_node("Systems/BalanceLog") as BalanceLog
	_pull(boss, player)
	var pulls := 0
	var far_for := 0.0
	var fought := 0.0
	while is_instance_valid(boss) and not boss.dead and fought < _boss_limit:
		await _frames(30)
		fought += 0.5
		if not is_instance_valid(boss) or boss.dead:
			break
		far_for = far_for + 0.5 if boss.global_position.distance_to(player.global_position) > PULL_DISTANCE else 0.0
		if far_for >= PULL_AFTER:
			_pull(boss, player)
			pulls += 1
			far_for = 0.0
			log.extra = {"pulls": pulls}
	if is_instance_valid(boss) and not boss.dead:
		BalanceLog.write({"build": BuildInfo.id(), "boss": String(boss.data_id), "depth": index, "players": 1,
				"boss_hp": roundi(boss.max_health), "left": snappedf(boss.health / boss.max_health, 0.01),
				"seconds": fought, "outcome": "timeout", "pulls": pulls,
				"heroes": [{"hero": String(player.hero.id), "level": player.level, "dps": 0}]})
		log.cancel()  # бой уже записан — добивание не пишется
		boss.take_damage(1.0e9, 1)
	print("  этап %d: %s, герой %d ур., бой %.0f с, подтянут ×%d" % [index + 1, boss_id, player.level, fought, pulls])
	if RunPlan.is_final(index):
		return false
	await _frames(2)
	var key := _find_key()
	if key != null:
		player.teleport(key.global_position)
	await _wait_until(func() -> bool: return _world.flow.phase == LevelFlow.Phase.PORTAL, 5.0)
	if _world.flow.portal == null:
		return false
	player.teleport(_world.flow.portal.global_position)
	await _wait_until(func() -> bool: return GameState.level_index == index + 1, 30.0)
	await _frames(2)
	return GameState.level_index == index + 1


## Босс — на свободную клетку пола в PULL_RING клетках от героя.
func _pull(boss: Enemy, player: Player) -> void:
	var director := _world.director
	var cell := director.free_cell_near(director.world_to_cell(player.global_position), PULL_RING)
	boss.global_position = director.cell_center(cell)


## Жадный выбор карт левел-апа, пока они есть; окно левел-апа не ставит мир на паузу.
func _pick_cards() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var player := _world.find_player(1)
	var guard := 0
	while player != null and not _world.upgrades.current_offer(1).is_empty() and guard < 100:
		var best: StringName = &""
		var best_score := -1.0
		for id: StringName in _world.upgrades.current_offer(1):
			var score := _score(player, id)
			if score > best_score:
				best = id
				best_score = score
		_world.upgrades.apply_choice(1, best)
		guard += 1
	var panel := _world.get_node_or_null("LevelUpPanel")
	if panel != null:
		panel.hide()
	_world.request_pause(&"level_up", false)


static func _score(player: Player, card_id: StringName) -> float:
	if UpgradePool.parse_evolution_card(card_id) != &"":
		return CARD_EVOLUTION
	if UpgradePool.is_rune_card(card_id):
		return CARD_RUNE
	var upgrade := DataRegistry.upgrade(card_id)
	if upgrade is SkillData:
		if (upgrade as SkillData).is_evolution:
			return CARD_EVOLUTION
		return CARD_OWNED_SKILL if player.get_upgrade_level(card_id) > 0 else CARD_NEW_SKILL
	return CARD_PASSIVE


func _find_key() -> Pickup:
	for child in _world.pickups.get_children():
		if child is Pickup and child.kind == Pickup.Kind.KEY:
			return child
	return null


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## timeout — в игровом времени (генерация уровня идёт в фоне — ждём и не меньше 5 с реального времени).
func _wait_until(condition: Callable, timeout: float) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	var frames := 0
	while frames < ceili(timeout * Engine.physics_ticks_per_second) or Time.get_ticks_msec() < deadline:
		if condition.call():
			return
		await get_tree().physics_frame
		frames += 1
