class_name LevelFlow
extends Node
## Хост: фазы уровня и структура забега (RunPlan).
## Обычный уровень: волны → таймер истёк → ровно 1 босс (ФТ-09) → гарантированный дроп Ключа →
## портал на метке EXIT → следующий уровень (ФТ-07). После третьего уровня портал ведёт в логово
## финального босса (CR-08): он появляется сразу, а после победы открываются два портала —
## «Завершить забег» (победа) и «Бесконечная гниль» (следующий круг, глубина растёт).
## Объекты карты (CR-06, CR-14, CR-16, шаг 8) создаются по слою объектов MapPlan (ObjectLayer, шаг 9): что и где
## стоит, решают метки карты CVAE и правила биома, а здесь — только создание узлов. Все игроки пали → поражение.

enum Phase { WAVES, BOSS, PORTAL, FINAL_BOSS, CHOICE, DEFEAT, VICTORY }

const PORTAL_ENTER_RADIUS := 14.0
## Обелисков за круг, чтобы в логове финального босса появилось место Грааля (DESIGN 6, фишка 3).
const GRAIL_OBELISKS := 3
const GRAIL_ID := &"grail"
const GRAIL_STATS := {&"might": 0.3, &"max_health": 50.0, &"regen": 1.0}
const ARTIFACT_MERCHANT := ObjectLayer.ARTIFACT_MERCHANT
const ALCHEMIST := ObjectLayer.ALCHEMIST

var phase := Phase.WAVES
var boss: Enemy
## Активные и потухшие порталы уровня.
var portals: Array[Portal] = []
## Портал на метке EXIT обычного уровня.
var portal: Portal
var merchants: Array[Merchant] = []
var obelisks_visited := 0
var grail_found := false
## Слой объектов текущего уровня (шаг 9).
var plan: MapPlan

var _world: World
## Идёт генерация следующего уровня: игроки ещё стоят в портале, повторный вход не запускаем.
var _advancing := false
## Клетки, занятые объектами слоя и местом Грааля: порталы победы на них не встают.
var _occupied: Array[Vector2i] = []


func _ready() -> void:
	_world = World.of(self)
	Events.level_loaded.connect(_on_level_loaded)
	Events.level_timer_expired.connect(_on_level_timer_expired)
	Events.enemy_died.connect(_on_enemy_died)
	Events.player_died.connect(_on_player_died)


func _on_level_loaded(level: LevelData) -> void:
	if not multiplayer.is_server():
		return
	boss = null
	portal = null
	portals.clear()
	merchants.clear()
	plan = _world.plan_for(level)
	_occupied = plan.occupied.duplicate()
	_spawn_plan(plan)
	if RunPlan.is_final(GameState.level_index):
		phase = Phase.FINAL_BOSS
		if obelisks_visited >= GRAIL_OBELISKS and not grail_found:
			_spawn_grail_site(level)
		# Логово: финальный босс ждёт сразу, таймер уровня здесь не нужен.
		boss = _world.waves.spawn_enemy(_world.waves.table.boss, _farthest_spawn_marker())
		Events.boss_spawned.emit(boss)
	else:
		phase = Phase.WAVES
		var exit := level.find_first(Palette.Tile.EXIT)
		portal = _spawn_portal(_world.director.cell_center(exit), Portal.Mode.NEXT, false)


## ФТ-09, ТК-09: по истечении таймера обычного уровня появляется ровно один босс.
func _on_level_timer_expired() -> void:
	if not multiplayer.is_server() or phase != Phase.WAVES:
		return
	phase = Phase.BOSS
	_world.waves.stop()
	var boss_data := _world.waves.table.boss
	boss = _world.waves.spawn_enemy(boss_data)
	if boss == null:  # все точки спавна под игроками — босс встаёт на самой дальней от них метке
		boss = _world.waves.spawn_enemy(boss_data, _farthest_spawn_marker())
	Events.boss_spawned.emit(boss)


func _on_enemy_died(enemy: Node, _killer_peer_id: int) -> void:
	if not multiplayer.is_server() or enemy != boss:
		return
	boss = null
	if phase == Phase.FINAL_BOSS:
		_offer_run_choice(enemy.global_position)
	else:
		# Фиксированный дроп обычного босса — Ключ, он открывает портал.
		_world.spawn_pickup({"kind": Pickup.Kind.KEY, "pos": enemy.global_position, "value": 1})
		# 17.10.2026: весь опыт и золото уровня летят к героям (кадром позже — вместе с добычей самого босса).
		collect_level_loot.call_deferred()
	Events.boss_defeated.emit()


## Хост: каждый кристалл опыта и всё золото на земле летят к ближайшему живому герою (победа над боссом уровня).
func collect_level_loot() -> void:
	if not multiplayer.is_server() or not is_inside_tree():
		return
	# Живые герои — прямо из мира: список EnemyDirector обновляется в физическом кадре и бывает ещё пуст.
	var heroes := _world.get_players().filter(func(p: Player) -> bool: return p.alive)
	if heroes.is_empty():
		return
	for node in _world.pickups.get_children():
		var pickup := node as Pickup
		if pickup == null:
			continue
		var nearest: Player = heroes[0]
		for hero: Player in heroes:
			if hero.global_position.distance_squared_to(pickup.global_position) \
					< nearest.global_position.distance_squared_to(pickup.global_position):
				nearest = hero
		pickup.attract(nearest, true)


func on_key_collected(_player: Player) -> void:
	if phase != Phase.BOSS:
		return
	phase = Phase.PORTAL
	portal.active = true
	Events.portal_activated.emit()


func on_obelisk_visited() -> void:
	obelisks_visited += 1
	Events.obelisk_visited.emit(obelisks_visited, GRAIL_OBELISKS)


## Грааль — реликвия всего отряда до конца забега.
func on_grail_dug(player: Player) -> void:
	if grail_found:
		return
	grail_found = true
	for p in _world.get_players():
		p.add_bonus(GRAIL_ID, GRAIL_STATS)
	Events.grail_found.emit(player.peer_id())


func _on_player_died(_peer_id: int) -> void:
	if not multiplayer.is_server() or phase in [Phase.DEFEAT, Phase.VICTORY]:
		return
	for p in _world.get_players():
		if p.alive:
			return
	phase = Phase.DEFEAT
	_world.waves.stop()
	GameState.running = false
	Events.run_ended.emit(false)


func _physics_process(_delta: float) -> void:
	if phase not in [Phase.PORTAL, Phase.CHOICE] or _advancing or not multiplayer.is_server():
		return
	for p in _world.director.players_alive():
		for gate in portals:
			if gate.active and p.global_position.distance_to(gate.global_position) <= PORTAL_ENTER_RADIUS:
				_enter(gate)
				return


func _enter(gate: Portal) -> void:
	match gate.mode:
		Portal.Mode.FINISH:
			phase = Phase.VICTORY
			_world.waves.stop()
			GameState.running = false
			Events.run_ended.emit(true)
		Portal.Mode.CONTINUE:
			# Новый круг: обелиски и Грааль считаются заново.
			obelisks_visited = 0
			grail_found = false
			_advance()
		_:
			_advance()


## Победа над финальным боссом: два портала рядом с местом его гибели.
func _offer_run_choice(pos: Vector2) -> void:
	phase = Phase.CHOICE
	_world.waves.stop()
	var near := _world.director.world_to_cell(pos)
	var taken := _occupied.duplicate()
	var first := _world.director.free_cell_near(near, 1, taken)
	taken.append(first)
	var second := _world.director.free_cell_near(near, 3, taken)
	_spawn_portal(_world.director.cell_center(first), Portal.Mode.CONTINUE, true)
	_spawn_portal(_world.director.cell_center(second), Portal.Mode.FINISH, true)
	Events.run_choice_offered.emit()


## ФТ-07: переход запускает цикл «генерация → проверка → загрузка» на хосте;
## клиенты получают готовую LevelData через game/net (ФТ-15).
func _advance() -> void:
	_advancing = true
	GameState.level_index += 1
	var next := await _world.make_next_level()
	_advancing = false
	if not is_inside_tree():
		return  # игрок вышел в меню, пока шла генерация
	_world.clear_level_objects()
	_world.load_level(next.level)
	var spawn := _world.player_spawn_position()
	for p in _world.get_players():
		p.revive()  # павшие встают в начале нового уровня, в т. ч. в ХК (DESIGN 1)
		p.teleport(spawn)


func _spawn_portal(pos: Vector2, mode: Portal.Mode, active: bool) -> Portal:
	var gate := _world.spawn_prop({"kind": &"portal", "pos": pos, "mode": mode, "active": active}) as Portal
	portals.append(gate)
	return gate


## Объекты слоя по порядку. У каждого номер на уровне (MapObject.object_id, с 1): по нему клиент просит хост
## открыть сундук, начать испытание или активировать точку.
func _spawn_plan(map_plan: MapPlan) -> void:
	var next_id := 1
	for entry in map_plan.objects:
		var kind: StringName = entry["kind"]
		var pos := _world.director.cell_center(entry["cell"])
		if kind == &"merchant":
			var info := DataRegistry.merchant(entry["merchant"])
			if info == null:
				continue
			var merchant := _world.spawn_prop({
				"kind": &"merchant", "merchant": info.id, "pos": pos, "offers": _world.economy.make_stock(info),
			}) as Merchant
			if merchant != null:
				merchants.append(merchant)
			continue
		var data := {"kind": kind, "pos": pos, "id": next_id}
		if kind == &"interactable":
			data["type"] = entry["type"]
			data["lore"] = entry.get("lore", &"")
			if entry.has("room"):
				data["room"] = entry["room"]  # треснувшая стена: середина её тайника (шаг 9)
		next_id += 1
		var prop := _world.spawn_prop(data)
		if prop is Chest and entry.get("mimic", false):
			(prop as Chest).mimic = true  # шаг 8: мимик знает только хост


func _spawn_grail_site(level: LevelData) -> void:
	var cell := level.find_first(Palette.Tile.OBELISK)
	if cell == LevelData.INVALID_CELL:
		cell = _world.director.free_cell_near(level.find_first(Palette.Tile.PLAYER_SPAWN), 3, _occupied)
	_occupied.append(cell)
	_world.spawn_prop({"kind": &"grail_site", "pos": _world.director.cell_center(cell)})


func _farthest_spawn_marker() -> Vector2:
	var best := Vector2.ZERO
	var best_d := -1.0
	for cell in GameState.current_level.find_cells(Palette.Tile.ENEMY_SPAWN):
		var pos := _world.director.cell_center(cell)
		var d := _world.director.distance_to_nearest_player(pos)
		if d > best_d:
			best_d = d
			best = pos
	return best
