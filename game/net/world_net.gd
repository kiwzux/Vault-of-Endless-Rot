class_name WorldNet
extends Node
## Сетевая часть сцены уровня (курсовая Ворончихина В.А.): узел World/Net.
##
## ФТ-13 — репликация объектов. Дочерние MultiplayerSpawner следят за контейнерами World/Players,
## Enemies, Pickups, Props. Хост создаёт объект через spawn_*(data); spawn_function строит
## узел фабрикой сущности (Enemy.create, Pickup.create …) и на хосте, и на клиентах; удаление на хосте
## (queue_free) спавнер повторяет у клиентов.
## Снаряды и следы атак (World/Projectiles, шаг 5, часть 2) — без спавнера: хост копит за кадр события «выстрел»
## и «снят раньше конца пути» и шлёт их одной надёжной посылкой (_fire_batch, формат — ProjectileStream);
## клиент строит узлы той же ProjectileFactory и ведёт полёт сам. Кончившийся сам снаряд каждый убирает сам.
## ФТ-14 — синхронизация состояния. MultiplayerSynchronizer добавляются в spawn_function (NetSync):
## у героя позицию ведёт владелец, остальное — хост; у подбираемого — позиция, у объектов карты —
## состояние (портал открыт, сундук открыт, товар торговца). Позиции и здоровье врагов — снимок
## EnemySnapshot (см. там, почему не синхронизатор на каждом враге). Таймер и фаза уровня — StateSync.
## ФТ-15 — передача уровня. Уровень генерирует только хост; клиентам надёжным RPC уходят готовые
## LevelData.to_bytes() и контрольная сумма; клиент сверяет её и отвечает своей (level_acks).
## Латентный вектор не передаётся, на клиенте инференса нет. Клетка, изменённая посреди уровня (шаг 9: проломлена
## стена тайника), уходит отдельным надёжным RPC — одна клетка, а не карта целиком.
## ФТ-16 — события. Клиент → хост: выбор карты, переброс, инвентарь, покупка, зелье, объект по E;
## хост проверяет отправителя и аргументы, отклонённое действие состояние не меняет (rejected_events).
## Хост → клиенты: события HUD (волна, босс, портал, конец забега …), карты левел-апа — только их
## владельцу, цифры урона — ненадёжно, пачкой за кадр.

const NID_META := &"net_id"
## Номер снаряда в пачках событий (ProjectileStream).
const PID_META := &"shot_id"
const ENEMY_CHUNKS := 5
## Сколько ждать загрузки сцены уровня у клиентов перед первым уровнем.
const WAIT_CLIENTS_TIMEOUT := 15.0
## Клиент: враг догоняет позицию из снимка плавно; дальше SNAP_DISTANCE — переносится сразу (телепорт).
const SMOOTHING := 18.0
const SNAP_DISTANCE := 64.0
## Узел из события (босс) может прийти чуть позже события — столько кадров клиент его ждёт.
const RESOLVE_FRAMES := 30
const MAX_DAMAGE_BATCH := 64
## Клиент: вспышка врага от удара — как у хоста в Enemy.flash_hit.
const HIT_FLASH := Color(3.0, 3.0, 3.0)
const HIT_FLASH_MS := 100
## Подбираемое летит к герою быстро: его позиция уходит чаще.
const PICKUP_INTERVAL := 1.0 / 30.0
## Таймер уровня на клиентах — с шагом не больше этого.
const STATE_INTERVAL := 0.25

const PLAYER_OWNER_PROPS: PackedStringArray = ["position"]
const PLAYER_HOST_PROPS: PackedStringArray = [
	"health", "max_health", "mana", "max_mana", "alive", "level", "xp", "move_speed", "buffs", "bonuses",
	"gold", "potions", "kills", "rerolls", "chests_opened", "revivals_used", "ward_ready",
	"equipment", "item_stats", "items_collected", "upgrade_levels", "revive_progress", "chills", "banished", "banishes_left", "runes",
	"run_stats", "evolution_stages", "pending_choices",
]
## События Events, которые хост пересылает клиентам для HUD. Новые — только в конец.
const MIRRORED_EVENTS: Array[StringName] = [
	&"wave_started", &"boss_spawned", &"boss_defeated", &"portal_activated", &"run_ended",
	&"run_choice_offered", &"obelisk_visited", &"grail_found", &"statue_awakened", &"item_picked",
	&"chest_opened", &"second_wind", &"ward_blocked", &"gold_collected", &"trade_completed",
	&"challenge_started", &"challenge_finished", &"level_generation_failed", &"player_revived",
	&"interactable_used",
]

## Хост → клиенты (StateSync): секунд до конца таймера уровня и фаза LevelFlow.
var time_left := 0.0
var phase := 0
## ФТ-16: сколько действий клиентов хост отклонил.
var rejected_events := 0
## ФТ-15: хост — контрольная сумма последнего уровня, которую подтвердил каждый клиент, и через сколько
## миллисекунд после отправки пришло подтверждение (НФТ-07: передача локации ≤ 1 с).
var level_acks := {}
var level_ack_ms := {}
var _level_sent_msec := 0
## ФТ-15: клиент — сколько уровней получено и сколько отвергнуто (битый пакет, не та сумма).
var levels_received := 0
var levels_rejected := 0

var _world: World
var _next_nid := 1
## nid → Enemy, на хосте и на клиентах.
var _enemies := {}
## Клиент: nid → позиция из снимка.
var _targets := {}
var _snapshots: Array[EnemySnapshot] = []
var _snapshot_left := 0.0
var _overflow_warned := false
var _replicating := false
var _damage_points := PackedVector2Array()
var _damage_amounts := PackedFloat32Array()
var _inventory_signature := 0
## Клиент: peer id → здоровье героя в прошлом кадре.
var _last_health := {}
## Клиент: nid → когда погасить вспышку от удара (мс).
var _flashing := {}
## Снаряды пачками (шаг 5, часть 2). Хост: очередь событий кадра; клиент: номер снаряда → узел.
var stream := ProjectileStream.new()
## Хост: сколько байт пачек снарядов ушло (одна посылка на всех клиентов — RPC без rpc_id) и сколько посылок.
var stream_bytes := 0
var stream_batches := 0
## ТК-13 для снарядов: хост — сколько выстрелов отправил клиентам, клиент — сколько получил и построил.
var shots_sent := 0
var shots_received := 0
## Стенду (tools/bench, одиночная игра): копить и считать пачки, как в сети, но не отправлять.
var measure_stream := false
var _next_pid := 1
var _shots := {}

@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var pickup_spawner: MultiplayerSpawner = $PickupSpawner
@onready var prop_spawner: MultiplayerSpawner = $PropSpawner


func _ready() -> void:
	_world = World.of(self)
	player_spawner.spawn_function = _make_player
	enemy_spawner.spawn_function = _make_enemy
	pickup_spawner.spawn_function = _make_pickup
	prop_spawner.spawn_function = _make_prop
	if Net.is_online():  # одиночной игре нужны только спавнеры
		# Системы World (@onready) готовы только после World._ready — он идёт после детей.
		_world.ready.connect(_go_online, CONNECT_ONE_SHOT)


func _go_online() -> void:
	if multiplayer.is_server():
		Net.peer_left.connect(_on_peer_left)
		Events.level_loaded.connect(_send_level)
		Events.level_up_offered.connect(_send_cards)
		Events.damage_dealt.connect(_queue_damage)
		for event in MIRRORED_EVENTS:
			_connect_mirror(event)
	else:
		player_spawner.spawned.connect(_on_remote_player)
		var upgrades := _world.upgrades
		upgrades.choice_submitted.connect(func(card_id: StringName) -> void: _rpc_choice.rpc_id(1, card_id))
		upgrades.reroll_submitted.connect(func() -> void: _rpc_reroll.rpc_id(1))
		upgrades.banish_submitted.connect(func(card_id: StringName) -> void: _rpc_banish.rpc_id(1, card_id))
		_world.economy.buy_submitted.connect(func(id: StringName, index: int) -> void: _rpc_buy.rpc_id(1, id, index))
		_world.economy.drink_submitted.connect(func() -> void: _rpc_drink.rpc_id(1))
		_world.interact_submitted.connect(func(object_id: int) -> void: _rpc_interact.rpc_id(1, object_id))
		_start_replication()
		Net.report_world_ready()


# --- Хост: создание объектов (ФТ-13) ---

func spawn_player(data: Dictionary) -> Player:
	return player_spawner.spawn(data) as Player


func spawn_enemy(data: Dictionary) -> Enemy:
	var with_id := data.duplicate()
	with_id["nid"] = _next_nid
	_next_nid += 1
	return enemy_spawner.spawn(with_id) as Enemy


## Хост: снаряд или след атаки. В сети (или для замера стенда) — ещё и событие в пачку кадра.
func spawn_projectile(data: Dictionary) -> Node2D:
	if not multiplayer.is_server():
		return null
	var node := ProjectileFactory.create(data)
	if node == null:
		return null
	if Net.is_online() or measure_stream:
		var pid := _next_pid
		_next_pid += 1
		stream.queue_spawn(pid, data)
		node.tree_exiting.connect(_on_shot_gone.bind(node, pid), CONNECT_ONE_SHOT)
	_world.projectiles.add_child(node, true)
	return node


## Хост: снаряд ушёл из мира. Кончился сам — у клиентов он кончится так же; иначе — событие «снят».
func _on_shot_gone(node: Node2D, pid: int) -> void:
	if not bool(node.get("natural_end")):
		stream.queue_removal(pid)


## Хост: пачка событий кадра — всем клиентам одной посылкой.
func _flush_stream() -> void:
	if stream.is_empty():
		return
	var shots := stream.queued()
	var bytes := stream.take()
	var send := Net.is_online() and _replicating and not multiplayer.get_peers().is_empty()
	if send or measure_stream:
		stream_bytes += bytes.size()
		stream_batches += 1
	if send:
		shots_sent += shots
		_fire_batch.rpc(bytes)


## Клиент: выстрелы и снятые снаряды кадра хоста. Испорченная пачка отбрасывается целиком.
@rpc("authority", "call_remote", "reliable")
func _fire_batch(bytes: Variant) -> void:
	if not (bytes is PackedByteArray):
		return
	var batch: Variant = ProjectileStream.decode(bytes)
	if batch == null:
		push_warning("WorldNet: пачка снарядов от хоста испорчена — отброшена")
		return
	for shot: Array in batch["shots"]:
		var node := ProjectileFactory.create(shot[1])
		if node == null:
			continue
		shots_received += 1
		var pid: int = shot[0]
		_shots[pid] = node
		node.tree_exiting.connect(func() -> void: _shots.erase(pid), CONNECT_ONE_SHOT)
		_world.projectiles.add_child(node, true)
	for pid in batch["removed"]:
		var node: Node = _shots.get(pid)
		if node != null and is_instance_valid(node):
			node.queue_free()


func spawn_pickup(data: Dictionary) -> Pickup:
	return pickup_spawner.spawn(data) as Pickup


func spawn_prop(data: Dictionary) -> Node2D:
	return prop_spawner.spawn(data) as Node2D


## Хост: дождаться, пока у всех участников загрузится сцена уровня (не дольше WAIT_CLIENTS_TIMEOUT).
## Кто не успел — отключается: без сцены он не примет ни уровень, ни объекты.
func wait_for_clients() -> void:
	if not Net.is_host():
		return
	var left := WAIT_CLIENTS_TIMEOUT
	while left > 0.0 and not _clients_ready():
		await get_tree().process_frame
		left -= get_process_delta_time()
	for peer in Net.players():
		if peer != 1 and not Net.world_ready_peers.has(peer):
			push_warning("WorldNet: участник %d не загрузил уровень за %d с — отключён" % [peer, WAIT_CLIENTS_TIMEOUT])
			Net.kick(peer)
	_start_replication()


## Хост: героев всех клиентов — по составу лобби (герой и таланты каждого участника).
func spawn_remote_players() -> void:
	if not Net.is_host():
		return
	for peer in Net.players():
		var entry: Dictionary = Net.roster[peer]
		var hero := DataRegistry.hero(entry.get("hero", &""))
		if peer != 1 and hero != null and Net.world_ready_peers.has(peer):
			_world.spawn_player(peer, hero, entry.get("talents", {}), entry.get("locked", []))


func _clients_ready() -> bool:
	for peer in Net.players():
		if peer != 1 and not Net.world_ready_peers.has(peer):
			return false
	return true


# --- spawn_function: одинаковые узлы на хосте и у клиентов ---

## data: {"peer", "hero", "talents", "locked", "pos"}. Пришло по сети, поэтому всё проверяется.
func _make_player(data: Variant) -> Node:
	if not (data is Dictionary):
		return null
	var peer := int(data.get("peer", 0))
	var hero := DataRegistry.hero(StringName(str(data.get("hero", ""))))
	if peer <= 0 or hero == null:
		return null
	var player: Player = World.PLAYER_SCENE.instantiate()
	player.name = str(peer)
	player.hero = hero
	player.talents = Net.sanitize_talents(data.get("talents", {}))
	player.locked_skills = Net.sanitize_locked(data.get("locked", []))
	player.position = data.get("pos", Vector2.ZERO)
	NetSync.add(player, "OwnerSync", PLAYER_OWNER_PROPS, false, 0.0, false, false)
	NetSync.add(player, "HostSync", PLAYER_HOST_PROPS, true, NetSync.INTERVAL, true)
	return player


func _make_enemy(data: Variant) -> Node:
	var enemy := Enemy.create(data) if data is Dictionary else null
	if enemy == null:
		return null
	var nid := int(data.get("nid", 0))
	enemy.set_meta(NID_META, nid)
	_enemies[nid] = enemy
	enemy.tree_exiting.connect(_forget_enemy.bind(nid))
	return enemy


func _make_pickup(data: Variant) -> Node:
	var pickup := Pickup.create(data) if data is Dictionary else null
	if pickup != null:
		NetSync.add(pickup, "Sync", ["position"], true, PICKUP_INTERVAL, false, false)
	return pickup


func _make_prop(data: Variant) -> Node:
	var prop := PropFactory.create(data) if data is Dictionary else null
	if prop == null:
		return null
	var props: PackedStringArray = []
	if prop is Portal:
		props = ["active"]
	elif prop is Merchant:
		props = ["offers", "dealt"]
	elif prop is ChallengeAltar:
		props = ["used", "active", "time_left"]
	elif prop is GrailSite:
		props = ["used", "progress"]
	elif prop is Interactable:
		props = ["used", "stage", "hits"]
	elif prop is MapObject:
		props = ["used"]
	if not props.is_empty():
		NetSync.add(prop, "Sync", props, true)
	return prop


func _forget_enemy(nid: int) -> void:
	_enemies.erase(nid)
	_targets.erase(nid)


## Клиент: герой появился у нас — та же настройка, что у хоста в World.spawn_player.
func _on_remote_player(node: Node) -> void:
	if node is Player:
		_world.setup_player(node)


# --- Синхронизация состояния (ФТ-14) ---

## Синхронизаторы, которые не создаются спавнером (снимок врагов, таймер уровня). Хост заводит их,
## только когда у всех клиентов есть сцена уровня: иначе MultiplayerAPI не найдёт узел у клиента.
func _start_replication() -> void:
	if _replicating:
		return
	_replicating = true
	for i in ENEMY_CHUNKS:
		var chunk := EnemySnapshot.new()
		chunk.name = "EnemyState%d" % i
		var sync := NetSync.add(chunk, "Sync", ["data"], false, NetSync.INTERVAL, false, false)
		if not multiplayer.is_server():
			sync.synchronized.connect(_apply_snapshot.bind(chunk))
		add_child(chunk)
		_snapshots.append(chunk)
	NetSync.add(self, "StateSync", ["time_left", "phase"], true, STATE_INTERVAL)


func _physics_process(delta: float) -> void:
	if not _replicating:
		if multiplayer.is_server():
			_flush_stream()  # замер стенда; в сети до старта репликации события отбрасываются — сцены у клиентов ещё нет
		return
	if multiplayer.is_server():
		time_left = GameState.level_time_left
		phase = _world.flow.phase
		_snapshot_left -= delta
		if _snapshot_left <= 0.0:
			_snapshot_left = NetSync.INTERVAL
			_pack_snapshots()
		_flush_damage()
		_flush_stream()
	else:
		GameState.level_time_left = time_left
		_world.flow.phase = phase as LevelFlow.Phase


func _process(delta: float) -> void:
	if not _replicating or multiplayer.is_server():
		return
	var weight := 1.0 - exp(-SMOOTHING * delta)
	for nid: int in _targets:
		var enemy: Enemy = _enemies.get(nid)
		if enemy == null:
			continue
		var target: Vector2 = _targets[nid]
		enemy.position = target if enemy.position.distance_to(target) > SNAP_DISTANCE else enemy.position.lerp(target, weight)
	_fade_flashes()
	_watch_inventory()
	_watch_health()


func _pack_snapshots() -> void:
	var parts: Array = []
	parts.resize(ENEMY_CHUNKS)
	for i in ENEMY_CHUNKS:
		parts[i] = []
	for nid: int in _enemies:
		var enemy: Enemy = _enemies[nid]
		if enemy.is_inside_tree() and not enemy.dead:
			parts[nid % ENEMY_CHUNKS].append(enemy)
	var dropped := 0
	for i in ENEMY_CHUNKS:
		dropped += _snapshots[i].pack(parts[i])
	if dropped > 0 and not _overflow_warned:
		_overflow_warned = true
		push_warning("WorldNet: в снимок не поместилось врагов: %d" % dropped)


func _apply_snapshot(chunk: EnemySnapshot) -> void:
	for record: Array in chunk.unpack():
		var enemy: Enemy = _enemies.get(record[0])
		if enemy == null:
			continue
		_targets[record[0]] = record[1]
		var health: float = record[2] * enemy.max_health
		if health < enemy.health - 0.01:
			_flash_enemy(record[0], enemy)  # удар считал хост — здесь только видно, что враг его получил
		enemy.health = health
		if record[3] & EnemySnapshot.FLAG_ENRAGED and not enemy.enraged:
			enemy._enrage()  # тот же облик, что у хоста; скорость на клиенте не используется
		enemy.set_status_flags(record[3] & ~EnemySnapshot.FLAG_ENRAGED)  # оттенок статусов (шаг 2)


## Клиент: вспышка раненого врага. Не tween на каждый удар, как у хоста (Enemy.flash_hit): при 300
## врагах и 30 снимках в секунду это тысячи объектов в секунду и проседание кадров клиента.
## Здесь — один общий таймер: вспышка гаснет в _process.
func _flash_enemy(nid: int, enemy: Enemy) -> void:
	enemy.body.self_modulate = HIT_FLASH
	enemy.body.position = enemy.recoil_offset()  # отдача (шаг 11.9) гаснет вместе со вспышкой
	_flashing[nid] = Time.get_ticks_msec() + HIT_FLASH_MS


func _fade_flashes() -> void:
	if _flashing.is_empty():
		return
	var now := Time.get_ticks_msec()
	for nid: int in _flashing.keys():
		if now >= _flashing[nid]:
			var enemy: Enemy = _enemies.get(nid)
			if enemy != null:
				enemy.body.self_modulate = Color.WHITE
				enemy.body.position = Vector2.ZERO
			_flashing.erase(nid)


## Клиент: экипировка и накопленные предметы своего героя пришли от хоста — окнам героя и торговца пора обновиться.
func _watch_inventory() -> void:
	var me := _world.local_player()
	if me == null:
		return
	var signature := hash([me.items_collected, me.equipment])
	if signature != _inventory_signature:
		_inventory_signature = signature
		Events.inventory_changed.emit(me.peer_id())


## Клиент: здоровье героев приходит от хоста; убыло — герой вспыхивает, как у хоста при ударе.
func _watch_health() -> void:
	for player in _world.get_players():
		var peer := player.peer_id()
		if player.health < _last_health.get(peer, player.health) - 0.01:
			player.flash_hit()
		_last_health[peer] = player.health


# --- Передача уровня (ФТ-15) ---

## Хост: уровень загружен у себя → готовая карта всем клиентам.
func _send_level(level: LevelData) -> void:
	level_acks.clear()
	level_ack_ms.clear()
	_level_sent_msec = Time.get_ticks_msec()
	_receive_level.rpc(level.to_bytes(), level.checksum(), GameState.level_index)


@rpc("authority", "call_remote", "reliable")
func _receive_level(bytes: Variant, checksum: Variant, level_index: Variant) -> void:
	var level := LevelData.from_bytes(bytes) if bytes is PackedByteArray else null
	if level == null or not (checksum is String) or level.checksum() != checksum or not (level_index is int):
		levels_rejected += 1
		push_error("WorldNet: уровень от хоста повреждён или не сходится контрольная сумма")
		_level_ack.rpc_id(1, "")
		return
	levels_received += 1
	GameState.level_index = level_index
	_world.load_level(level)
	var me := _world.local_player()
	if me != null:
		me.teleport(_world.player_spawn_position())
	_level_ack.rpc_id(1, level.checksum())


@rpc("any_peer", "call_remote", "reliable")
func _level_ack(checksum: Variant) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not Net.roster.has(sender) or not (checksum is String):
		return
	level_acks[sender] = checksum
	level_ack_ms[sender] = Time.get_ticks_msec() - _level_sent_msec
	if checksum != GameState.current_level.checksum():
		push_error("WorldNet: у участника %d карта не совпала с картой хоста" % sender)


## Хост: клетка карты сменилась (World.set_cell_tile) — всем клиентам.
func send_cell(cell: Vector2i, tile: int) -> void:
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_receive_cell.rpc(cell, tile, GameState.level_index)


## Клиент: клетка от хоста; пакет чужого уровня (опоздал к переходу) или битый — отбрасывается.
@rpc("authority", "call_remote", "reliable")
func _receive_cell(cell: Variant, tile: Variant, level_index: Variant) -> void:
	if not (cell is Vector2i and tile is int and level_index is int) or level_index != GameState.level_index:
		return
	_world.apply_cell_tile(cell, tile)


# --- События хост → клиенты (ФТ-16) ---

func _connect_mirror(event: StringName) -> void:
	for info: Dictionary in Events.get_signal_list():
		if info["name"] == event:
			var relay: Callable = [_relay0, _relay1, _relay2, _relay3][info["args"].size()]
			Events.connect(event, relay.bind(event))
			return


func _relay0(event: StringName) -> void:
	_mirror(event, [])


func _relay1(a: Variant, event: StringName) -> void:
	_mirror(event, [a])


func _relay2(a: Variant, b: Variant, event: StringName) -> void:
	_mirror(event, [a, b])


## Шаг 8: interactable_used (точка, участник, исход).
func _relay3(a: Variant, b: Variant, c: Variant, event: StringName) -> void:
	_mirror(event, [a, b, c])


## Узлы в аргументах уходят путём относительно World: у клиента это тот же узел, его создал спавнер.
func _mirror(event: StringName, args: Array) -> void:
	var packed: Array = []
	for arg: Variant in args:
		packed.append({"node": _world.get_path_to(arg)} if arg is Node else arg)
	_event.rpc(event, packed)


@rpc("authority", "call_remote", "reliable")
func _event(event: Variant, packed: Variant) -> void:
	if not (event is StringName) or event not in MIRRORED_EVENTS or not (packed is Array):
		return
	var args: Array = []
	for arg: Variant in packed:
		if arg is Dictionary and arg.has("node"):
			var node := await _resolve(arg["node"])
			if node == null:
				return  # объект уже исчез — событие о нём устарело
			args.append(node)
		else:
			args.append(arg)
	if event == &"run_ended" and args.size() == 1 and args[0] is bool:
		_world.flow.phase = LevelFlow.Phase.VICTORY if args[0] else LevelFlow.Phase.DEFEAT
	Events.emit_signal.callv([event] + args)


func _resolve(path: Variant) -> Node:
	if not (path is NodePath):
		return null
	for i in RESOLVE_FRAMES:
		var node := _world.get_node_or_null(path)
		if node != null:
			return node
		await get_tree().process_frame
	return null


## Хост: карты левел-апа — только их владельцу (у хоста их показывает его же панель).
func _send_cards(peer_id: int, cards: Array) -> void:
	if peer_id != multiplayer.get_unique_id() and Net.roster.has(peer_id):
		_receive_cards.rpc_id(peer_id, cards)


@rpc("authority", "call_remote", "reliable")
func _receive_cards(cards: Variant) -> void:
	if cards is Array and cards.size() > 0 and cards.size() <= UpgradePool.CARD_COUNT:
		Events.level_up_offered.emit(multiplayer.get_unique_id(), cards)


func _queue_damage(pos: Vector2, amount: float, crit: bool) -> void:
	if _damage_points.size() < MAX_DAMAGE_BATCH:
		_damage_points.append(pos)
		_damage_amounts.append(-amount if crit else amount)  # знак — удачный удар


func _flush_damage() -> void:
	if _damage_points.is_empty():
		return
	_damage_batch.rpc(_damage_points, _damage_amounts)
	_damage_points = PackedVector2Array()
	_damage_amounts = PackedFloat32Array()


## Цифры урона — украшение: ненадёжная доставка, потеря пакета ничего не ломает.
@rpc("authority", "call_remote", "unreliable")
func _damage_batch(points: Variant, amounts: Variant) -> void:
	if not (points is PackedVector2Array and amounts is PackedFloat32Array) or points.size() != amounts.size():
		return
	for i in points.size():
		Events.damage_dealt.emit(points[i], absf(amounts[i]), amounts[i] < 0.0)


# --- Действия клиентов → хост (ФТ-16): проверка отправителя и аргументов ---

## Отправитель — участник сессии, у которого есть герой на уровне; 0 — нет такого.
func _participant() -> int:
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or _world.find_player(sender) == null:
		return 0
	return sender


## Учёт отклонённого действия: состояние хоста при этом не менялось.
func _check(accepted: bool, action: String, sender: int) -> void:
	if not accepted:
		rejected_events += 1
		print_verbose("WorldNet: отклонено %s от участника %d" % [action, sender])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_choice(card_id: Variant) -> void:
	var sender := _participant()
	var ok := sender != 0 and (card_id is StringName or card_id is String)
	_check(ok and _world.upgrades.apply_choice(sender, StringName(card_id)), "выбор карты", sender)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_reroll() -> void:
	var sender := _participant()
	_check(sender != 0 and _world.upgrades.apply_reroll(sender), "переброс карт", sender)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_banish(card_id: Variant) -> void:
	var sender := _participant()
	var ok := sender != 0 and (card_id is StringName or card_id is String)
	_check(ok and _world.upgrades.apply_banish(sender, StringName(card_id)), "изгнание карты", sender)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_buy(merchant_id: Variant, index: Variant) -> void:
	var sender := _participant()
	var ok := sender != 0 and (merchant_id is StringName or merchant_id is String) and index is int
	_check(ok and _world.economy.apply_buy(sender, StringName(merchant_id), index), "покупка", sender)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_drink() -> void:
	var sender := _participant()
	_check(sender != 0 and _world.economy.apply_drink(sender), "зелье", sender)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_interact(object_id: Variant) -> void:
	var sender := _participant()
	_check(sender != 0 and object_id is int and _world.apply_interact(sender, object_id), "объект карты", sender)


# --- Отключения (ФТ-12) ---

## Хост: клиент ушёл — его герой исчезает у всех, остальные играют дальше.
func _on_peer_left(peer_id: int) -> void:
	level_acks.erase(peer_id)
	var player := _world.find_player(peer_id)
	if player == null:
		return
	player.get_parent().remove_child(player)
	player.queue_free()
	Events.player_died.emit(peer_id)  # LevelFlow проверит, остался ли в отряде живой герой
