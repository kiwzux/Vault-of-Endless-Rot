class_name World
extends Node2D
## Сцена уровня. Контейнеры Players/Enemies/Projectiles/Pickups/Props — точки наблюдения
## MultiplayerSpawner (DESIGN 5.1); общие объекты создаёт только хост и только внутри них.
##
## Хост создаёт объекты через spawn_*(data): data — словарь из простых типов, его понимает фабрика
## сущности (Enemy.create, ProjectileFactory.create, Pickup.create, PropFactory.create).
## Создаёт их MultiplayerSpawner узла Net (WorldNet, ФТ-13): та же фабрика стоит в его spawn_function,
## и у клиентов появляется такой же узел. В одиночной игре спавнеры работают так же, без сети.

## Клиент нажал E у объекта карты (платный сундук, испытание). game/net: RPC хосту →
## apply_interact(get_remote_sender_id(), object_id).
signal interact_submitted(object_id: int)

const PLAYER_SCENE := preload("res://entities/player/player.tscn")

@onready var ground: TileMapLayer = $Level/Ground
@onready var art: TileMapLayer = $Level/Art
@onready var markers: TileMapLayer = $Level/Markers
@onready var players: Node2D = $Players
@onready var enemies: Node2D = $Enemies
@onready var projectiles: Node2D = $Projectiles
@onready var pickups: Node2D = $Pickups
@onready var props: Node2D = $Props
@onready var director: EnemyDirector = $Systems/EnemyDirector
@onready var waves: WaveSpawner = $Systems/WaveSpawner
@onready var upgrades: UpgradeSystem = $Systems/UpgradeSystem
@onready var flow: LevelFlow = $Systems/LevelFlow
@onready var loot: LootSystem = $Systems/LootSystem
@onready var passives: HeroPassiveSystem = $Systems/HeroPassives
@onready var economy: EconomySystem = $Systems/Economy
@onready var statuses: StatusSystem = $Systems/Statuses
## Статистика забега (как в Megabonk): урон по навыкам, убийства, опыт — для экрана конца забега.
@onready var run_stats: RunStats = $Systems/RunStats
@onready var net: WorldNet = $Net
## Падение убитых врагов доигрывается здесь у каждого участника (шаг 11.2), сетью не передаётся.
@onready var corpses: EnemyCorpses = $Corpses
## Тьма и свет уровня (шаг 11.8) — у каждого участника свои, по сети не передаются.
@onready var lights: LightMap = $LightMap
## «Сочность» (шаг 11.9): тряска своей камеры, стоп-кадр в одиночной игре, искры и брызги — тоже у каждого свои.
@onready var juice: Juice = $Juice
## Короткие эффекты навыков (шаг 11.21): вспышки выстрела, искры попаданий, разряды с неба — у каждого свои.
@onready var skill_fx: SkillFxLayer = $SkillFx
## Пост-эффекты (шаг 11.10): виньетка, красные края при ране, аберрация на малом здоровье.
@onready var post: PostFx = $PostFx
## Звуки боя (шаг 11.27): взмахи, заклинания, попадания, взрывы, смерти — у каждого свои, по сети не передаются.
@onready var sfx: CombatSound = $CombatSound
## Предметы обстановки (шаг 11.29): декор биома по плану из карты — у каждого свой, по сети не передаётся.
@onready var decor: LevelDecor = $Decor

## Окна, которые сейчас открыты и держат паузу (меню паузы, левел-ап, инвентарь, торговец).
var _pause_reasons := {}
## Хост: описание последней сгенерированной карты (шаг 9).
var _plan: MapPlan


## Ближайший предок-World: так сущности и системы находят сцену уровня без глобальных ссылок.
static func of(node: Node) -> World:
	var n := node
	while n != null and not (n is World):
		n = n.get_parent()
	return n as World


func _ready() -> void:
	# Метки уровня (рамки цвета палитры под сундуками, статуями, порталом) — только для отладки, по ключу
	# «-- --markers»: в обычной игре объекты на метках рисуют себя сами (шаг 11.20).
	markers.visible = OS.get_cmdline_user_args().has("--markers")
	if not multiplayer.is_server():
		return  # клиент получает LevelData от хоста через WorldNet (ФТ-15)
	var level := GameState.current_level
	if level == null:
		level = (await make_next_level()).level
		if not is_inside_tree():
			return  # игрок вышел в меню, пока шла генерация
	await net.wait_for_clients()  # в кооперативе: у всех участников загружена сцена уровня
	if not is_inside_tree():
		return
	load_level(level)
	spawn_player(multiplayer.get_unique_id(), RunConfig.get_hero(), RunConfig.talents, RunConfig.locked_skills)
	net.spawn_remote_players()


func load_level(level: LevelData) -> void:
	LevelBuilder.build(level, ground, markers, art)
	GameState.begin_level(level)


## ФТ-07: цикл «CVAE → BFS-валидатор → журнал» для уровня GameState.level_index (только хост).
## Корутина: генерация идёт в фоновом потоке. Без обученной модели — тестовая арена (LevelService).
## Результат — описание карты MapPlan (шаг 9): планировка и слой объектов; LevelFlow создаёт объекты по нему.
func make_next_level() -> MapPlan:
	_plan = await LevelService.generate_map(get_tree(), MapRequest.for_run(GameState.level_index))
	return _plan


## Хост: описание карты для загруженной планировки level. Если карта пришла не из make_next_level
## (тест, заранее готовая LevelData) — слой объектов строится по ней тем же ObjectLayer.
func plan_for(level: LevelData) -> MapPlan:
	if _plan == null or _plan.level != level:
		_plan = ObjectLayer.plan(level, MapRequest.for_run(GameState.level_index))
	return _plan


## Хост: убрать врагов, снаряды, подбираемое и объекты карты перед загрузкой следующего уровня.
func clear_level_objects() -> void:
	for container: Node in [enemies, projectiles, pickups, props]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()


func player_spawn_position() -> Vector2:
	return ground.map_to_local(GameState.current_level.find_first(Palette.Tile.PLAYER_SPAWN))


## talents — ранги талантов героя из хаба (CR-04); для удалённого игрока они пришли в лобби (Net.roster).
## locked — навыки, ещё не открытые в профиле игрока (шаг 10): в его левел-апе их нет.
func spawn_player(peer_id: int, hero: HeroData, talents: Dictionary = {}, locked: Array = []) -> Player:
	var player := net.spawn_player({
		"peer": peer_id, "hero": hero.id, "talents": talents.duplicate(), "locked": locked.duplicate(),
		"pos": player_spawn_position(),
	})
	if player != null:
		setup_player(player)
	return player


## Герой появился в сцене (у хоста — после spawn_player, у клиента — когда его создал спавнер).
func setup_player(player: Player) -> void:
	var size: int = GameState.current_level.size if GameState.current_level != null else LevelData.ALLOWED_SIZES.back()
	player.set_camera_limits(Rect2i(Vector2i.ZERO, Vector2i.ONE * size * Palette.tile_size()))
	Events.player_spawned.emit(player)


func get_players() -> Array[Player]:
	var result: Array[Player] = []
	for child in players.get_children():
		if child is Player:
			result.append(child)
	return result


func find_player(peer_id: int) -> Player:
	return players.get_node_or_null(str(peer_id)) as Player


## Герой этого узла сети (на хосте — герой хоста).
func local_player() -> Player:
	return find_player(multiplayer.get_unique_id())


## Ближайший живой враг (не союзник) к точке не дальше reach — у хоста и у клиентов: по нему снаряд врага
## находит стрелка, чтобы тот сыграл удар (ProjectileFactory, шаг 11.2).
func enemy_near(pos: Vector2, reach: float) -> Enemy:
	var best: Enemy = null
	var best_distance := reach * reach
	for child in enemies.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.ally and not enemy.dead:
			var distance := enemy.global_position.distance_squared_to(pos)
			if distance < best_distance:
				best_distance = distance
				best = enemy
	return best


func spawn_enemy(data: Dictionary) -> Enemy:
	return net.spawn_enemy(data)


## Летящие снаряды врагов медленнее и слабее (BalanceConfig.enemy_projectile_speed_mult, _damage_mult); хост меняет
## их до отправки — у клиентов снаряд тот же. Взрывы и зоны на земле (без скорости) — без изменений.
func spawn_projectile(data: Dictionary) -> Node2D:
	if data.get("hostile", false) and data.has("speed"):
		data = data.duplicate()
		data["speed"] = float(data["speed"]) * DataRegistry.BALANCE.enemy_projectile_speed_mult
		if data.has("damage"):
			data["damage"] = float(data["damage"]) * DataRegistry.BALANCE.enemy_projectile_damage_mult
	return net.spawn_projectile(data)


## Предел снарядов героев (шаг 5, BalanceConfig.max_hero_projectiles): узлов в World/Projectiles уже столько,
## что новые выстрелы, осколки, зоны и ловушки героев не создаются.
func projectiles_full() -> bool:
	return projectiles.get_child_count() >= DataRegistry.BALANCE.max_hero_projectiles


func spawn_pickup(data: Dictionary) -> Pickup:
	return net.spawn_pickup(data)


func spawn_prop(data: Dictionary) -> Node2D:
	return net.spawn_prop(data)


## Объект карты по его номеру на уровне (MapObject.object_id); null — нет такого.
func find_map_object(object_id: int) -> MapObject:
	for child in props.get_children():
		if child is MapObject and child.object_id == object_id:
			return child
	return null


## Вызывает свой герой по клавише E у объекта карты.
func submit_interact(object_id: int) -> void:
	if multiplayer.is_server():
		apply_interact(multiplayer.get_unique_id(), object_id)
	else:
		interact_submitted.emit(object_id)


## Хост: игрок peer_id активирует объект карты. Проверяется всё (ФТ-16): герой жив и стоит рядом,
## объект существует, работает по клавише и ещё не использован; дальше решает сам объект (цена сундука).
## false — отклонено, состояние не менялось.
func apply_interact(peer_id: int, object_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	var player := find_player(peer_id)
	var target := find_map_object(object_id)
	if player == null or not player.alive or target == null or not target.requires_key or target.used:
		return false
	if not target.in_reach(player):
		return false
	return target.activate(player)


## Хост: клетка карты меняется посреди уровня (шаг 9: проломлена стена тайника) — у себя и у всех клиентов.
## Планировку по-прежнему рисует модель (ОГР-02): меняется одна клетка, которую открыл игрок.
func set_cell_tile(cell: Vector2i, tile: int) -> void:
	if not multiplayer.is_server():
		return
	apply_cell_tile(cell, tile)
	net.send_cell(cell, tile)


## У каждого участника: данные карты, физика клетки, графика уровня и событие для поля потока и миникарты.
## Графика перерисовывается целиком: соседние тайлы (кромки стен) зависят от новой клетки.
func apply_cell_tile(cell: Vector2i, tile: int) -> void:
	var level := GameState.current_level
	if level == null or not level.in_bounds(cell) or tile < 0 or tile >= Palette.class_count() \
			or Palette.is_marker(tile) or level.get_tile(cell) == tile:
		return
	level.set_tile(cell, tile)
	ground.set_cell(cell, LevelBuilder.SOURCE_ID, Vector2i(tile, 0))
	LevelArt.build(level, art)
	Events.level_cell_changed.emit(cell, tile)


## Стена, опасная клетка или край карты. Работает и на клиентах: им нужна для полёта снарядов.
func is_blocked(pos: Vector2) -> bool:
	var level := GameState.current_level
	if level == null:
		return false
	var cell := ground.local_to_map(pos)
	return not level.in_bounds(cell) or not Palette.is_passable(level.get_tile(cell))


## Пауза на время окна интерфейса — только в одиночной игре: в сети остальные игроки продолжают бой.
## Мир стоит, пока открыто хотя бы одно окно.
func request_pause(reason: StringName, on: bool) -> void:
	if on:
		_pause_reasons[reason] = true
	else:
		_pause_reasons.erase(reason)
	get_tree().paused = not _pause_reasons.is_empty() and multiplayer.get_peers().is_empty()


func is_ui_open(reason: StringName) -> bool:
	return _pause_reasons.has(reason)


## Открыто окно интерфейса: герой не двигается и не пьёт зелья, клавиши достаются окну.
func input_blocked() -> bool:
	return not _pause_reasons.is_empty()


## Души, которые даст забег своему игроку, если выйти сейчас (CR-04): убийства, пройденные уровни,
## победа; в ХК — ×2. Считает каждый участник для себя: профиль у каждого свой.
func souls_earned() -> int:
	var player := local_player()
	var kills := player.kills if player != null else 0
	var victory := flow.phase == LevelFlow.Phase.VICTORY
	return DataRegistry.META_RULES.run_reward(kills, GameState.level_index, victory, RunConfig.reward_mult())


## Выход из забега в хаб (меню паузы, экран конца забега): души начисляются один раз.
## В кооперативе хост уводит в Убежище всех — сессия остаётся (Net.return_to_hub); клиент, вышедший сам,
## покидает сессию. target — куда уйти (после разрыва с хостом — главное меню, ФТ-12).
func leave_run(target: String = ScenePaths.HUB) -> void:
	if Net.is_host() and Net.state == Net.State.IN_RUN and target == ScenePaths.HUB:
		Net.return_to_hub()
		return
	finish_run(target)


## Начислить души за забег (один раз), снять паузу, закончить забег и уйти в target.
## leave_session — закрыть сетевую сессию; false — общий возврат в Убежище (Net._return_to_hub).
func finish_run(target: String, leave_session: bool = true) -> void:
	if not RunConfig.reward_claimed:
		RunConfig.reward_claimed = true
		RunConfig.last_reward = souls_earned()
		var chronicle: ChronicleRecorder = $Systems/Chronicle
		MetaProfile.grant(RunConfig.last_reward, flow.phase == LevelFlow.Phase.VICTORY, chronicle.summary())
	_pause_reasons.clear()
	get_tree().paused = false
	GameState.end_run()
	if leave_session:
		Net.leave()
	get_tree().change_scene_to_file(target)
