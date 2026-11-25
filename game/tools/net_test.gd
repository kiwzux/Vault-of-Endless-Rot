extends Node
## Сетевые испытания (ТЗ 4.6) без участия человека: хост и два клиента — три процесса Godot на одной
## машине, обмен через ENet по 127.0.0.1.
##  ТК-12 — подключение по IP:порт ≤ 5 с; обрыв клиента (процесс убит) не прерывает игру остальных;
##          уход хоста ведёт клиента в главное меню без аварийного завершения.
##  ТК-13 — набор объектов (тип, число) и синхронизируемые свойства у клиентов совпадают с хостом.
##  ТК-14 — контрольная сумма карты одинакова у всех, у клиентов инференса нет; действия с неверными
##          аргументами и чужие RPC хост отклоняет без изменения состояния.
##  ТК-15 — трафик хоста на клиента при 300 врагах, частота снимков, время передачи уровня.
##          С ключом --lag всё то же идёт при RTT 100 мс и 2 % потерь (tools/net/lag_peer.gd у всех участников).
## Запуск (хост сам запустит клиентов):
##   godot --headless --max-fps 60 --path game res://tools/net_test.tscn            — без задержки
##   godot --headless --max-fps 60 --path game res://tools/net_test.tscn -- --lag   — ТК-15: RTT 100 мс, потери 2 %
## Узел живёт в корне дерева (/root/NetTest) у всех процессов: сцена уровня его не удаляет.

const PORT := 24570
const CLIENTS := 2
const CLIENT_HEROES := [1, 2]  # Некромант, Чародейка; хост — Рыцарь
## Номер процесса «чужой сборки» (проверка версии при подключении).
const STRANGER_INDEX := 9
const RESULT_FILE := "user://net_test_client_%d.json"
const WATCHDOG := 150.0
const STRESS_ENEMIES := 300
const TRAFFIC_WINDOW := 3.0
## Порог НФТ-07: исходящий трафик хоста на клиента.
const TRAFFIC_LIMIT_KBPS := 100.0
const POS_TOLERANCE := 0.25
## ТК-15: задержка в одну сторону (RTT = 2 × LAG_MS) и доля потерянных пакетов.
const LAG_MS := 50
const LAG_LOSS := 0.02
const LagPeer := preload("res://tools/net/lag_peer.gd")
const VALUE_TOLERANCE := 0.001

var _failures := 0
var _role := "host"
var _index := 0
var _port := PORT
var _lag := false
## Хост: ответы клиентов на перепись (peer → словарь).
var _census := {}
var _client_pids: Array[int] = []
var _client_peers := {}  # index → peer id
## Сколько раз пришло Events.wave_started: у клиента — через WorldNet от хоста (ФТ-16).
var _waves_seen := 0
## То же для Events.player_revived («Последний вздох»).
var _revived_seen := 0
## Клиент: что сообщить хосту.
var _connect_msec := -1
var _join_started := 0
var _snapshots_seen := 0
var _result := {}
## Хост: отчёт клиента 1 из Убежища после конца забега.
var _hub_report := {}


func _ready() -> void:
	get_tree().current_scene = null  # смена сцены на уровень не удалит тестовый узел
	name = "NetTest"
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.trim_prefix("--role=")
		elif arg.begins_with("--index="):
			_index = arg.trim_prefix("--index=").to_int()
		elif arg.begins_with("--port="):
			_port = arg.trim_prefix("--port=").to_int()
		elif arg == "--lag":
			_lag = true
	# Свой профиль у каждого процесса: тест не трогает настоящий и не пишет в один файл из трёх процессов.
	MetaProfile.path = "user://test_profile_net_%s_%d.json" % [_role, _index]
	MetaProfile.legacy_path = MetaProfile.path + ".none"
	SaveFile.remove(MetaProfile.path)
	MetaProfile.load_profile()
	BalanceLog.path = "user://test_balance_log_net_%s_%d.jsonl" % [_role, _index]  # не в настоящий журнал
	if _lag:
		Net.peer_wrapper = func(enet: ENetMultiplayerPeer) -> MultiplayerPeer:
			return LagPeer.new(enet, LAG_MS, LAG_LOSS)
	get_tree().create_timer(WATCHDOG, true, false, true).timeout.connect(func() -> void:
		printerr("net_test (%s): не уложились в %d с" % [_role, WATCHDOG])
		_kill_clients()
		get_tree().quit(2))
	Events.wave_started.connect(func(_index: int) -> void: _waves_seen += 1)
	Events.player_revived.connect(func(_peer: int, _by: int) -> void: _revived_seen += 1)
	if _role == "client":
		_run_client()
	elif _role == "stranger":
		_run_stranger()
	else:
		_run_host()


# --- Хост ---

func _run_host() -> void:
	for i in CLIENTS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_FILE % (i + 1)))
	if _lag:
		print("  ..   эмуляция сети: RTT %d мс, потери %d %%" % [LAG_MS * 2, roundi(LAG_LOSS * 100)])
	_check(Net.host(_port, DataRegistry.HEROES[0], {}) == OK, "хост создал сессию на порту %d" % _port)
	_check(Net.port_mapper.status == PortMapper.Status.IDLE and Net.host_port == _port,
			"UPnP: сессия без лобби роутер не трогает (порт хоста %d)" % Net.host_port)
	_check(PortMapper.is_private_address("192.168.1.5") and PortMapper.is_private_address("100.72.3.4")
			and PortMapper.is_private_address("10.0.0.1") and PortMapper.is_private_address("172.20.0.1")
			and PortMapper.is_private_address("") and not PortMapper.is_private_address("93.184.216.34")
			and not PortMapper.is_private_address("172.32.0.1") and not PortMapper.is_private_address("26.10.4.2"),
			"UPnP: частный и общий адрес провайдера (CGNAT) отличаются от внешнего")
	for i in CLIENTS:
		var log_path := ProjectSettings.globalize_path("user://net_test_client_%d.log" % (i + 1))
		var args := PackedStringArray(["--headless", "--max-fps", "60", "--log-file", log_path,
				"--path", ProjectSettings.globalize_path("res://"),
				"res://tools/net_test.tscn", "--", "--role=client", "--index=%d" % (i + 1), "--port=%d" % _port])
		if _lag:
			args.append("--lag")
		_client_pids.append(OS.create_process(OS.get_executable_path(), args))
	_check(await _wait(func() -> bool: return Net.players().size() == CLIENTS + 1, 20.0), "ТК-12: оба клиента в лобби")
	_check(await _wait(func() -> bool: return _heroes_chosen(), 5.0), "лобби: хост знает героев клиентов")
	await _check_stranger()
	Net.set_hardcore(true)
	Net.set_seals({&"seal_vigor": 1, &"seal_usury": 2, "no_such_seal": 3})  # шаг 12.3: мусор хост отбрасывает сам
	await get_tree().create_timer(0.3).timeout
	Net.start_run()

	_check(await _wait(func() -> bool: return _world() != null and _world().get_players().size() == CLIENTS + 1, 20.0),
			"старт забега: у хоста герои всех трёх участников")
	var world := _world()
	if world == null:
		_finish_host()
		return
	_check(RunConfig.hardcore, "«Хардкор» из лобби действует в забеге")
	_check(RunConfig.seals == {&"seal_vigor": 1, &"seal_usury": 2}, "шаг 12.3: печати из лобби действуют в забеге (%s)" % [RunConfig.seals])
	var first_guest := world.find_player(_client_peers.get(1, 0))
	_check(first_guest != null and first_guest.locked_skills.size() == 1 and first_guest.locked_skills[0] == &"meteor",
			"шаг 10: закрытые навыки клиента дошли до хоста, мусор отброшен")
	for p in world.get_players():
		p.invulnerable = true
	_check(await _wait(func() -> bool: return world.net.level_acks.size() == CLIENTS, 10.0), "ТК-14: оба клиента подтвердили уровень")
	_check_level_acks(world, "первый уровень")

	# Бой: волны, снаряды, лут. Затем перепись на остановленном мире (ТК-13). Дальнобойные в волнах редки
	# (ranged_spawn_weight) — двое арбалетчиков рядом с хостом, чтобы снаряды в бою были наверняка.
	var shooter_at := world.find_player(1).position
	for offset: Vector2 in [Vector2(90, 0), Vector2(-90, 0)]:
		world.spawn_enemy({"id": &"skeleton_crossbowman", "pos": shooter_at + offset})
	await get_tree().create_timer(6.0).timeout
	await _compare_census(world, "после 6 с боя")

	# ФТ-10/ФТ-16 в коопе: карты левел-апа уходят только владельцу, его выбор применяет хост.
	var guest := world.find_player(_client_peers.get(1, 0))
	if guest != null:
		world.upgrades.grant_xp(guest, Player.xp_to_next(guest.level) - guest.xp, false)
		_check(world.upgrades.current_offer(guest.peer_id()).size() == UpgradePool.CARD_COUNT, "ФТ-10: клиенту 1 предложены 3 карты")
		_check(await _wait(func() -> bool: return world.upgrades.current_offer(guest.peer_id()).is_empty(), 5.0),
				"ФТ-16: клиент 1 выбрал карту по RPC, хост применил выбор")
		# Шаг 4: руна забега в навыке героя клиента — сверяется переписью ниже (поле runes).
		var start_skill := guest.hero.starting_weapon
		_check(guest.add_rune(start_skill, &"rune_might") or &"rune_might" in guest.runes.get(start_skill, []),
				"шаг 4: в навык героя клиента 1 вставлена руна")

		# «Последний вздох» по сети: герой клиента пал, Рыцарь хоста встал рядом и поднял его.
		RunConfig.hardcore = false  # в «Хардкоре» воскрешения нет; проверка — только на хосте, где оно считается
		guest.invulnerable = false
		for attempt in 10:  # карты клиента случайны: Уклонение, Оберег и Второе дыхание могут сдержать удар
			if not guest.alive:
				break
			guest.health = 1.0  # один удар снимает не больше max_hit_share
			guest.take_damage(1.0e9)
		guest.invulnerable = true
		_check(not guest.alive, "герой клиента 1 пал")
		world.local_player().position = guest.position
		_check(await _wait(func() -> bool: return guest.alive, 6.0), "«Последний вздох» по сети: Рыцарь хоста поднял героя клиента 1")
		RunConfig.hardcore = true
		await _compare_census(world, "после воскрешения")

	# Шаг 9: проломленная стена тайника — клетка карты меняется у хоста и у всех клиентов (та же контрольная сумма).
	var opened := _breakable_wall(GameState.current_level)
	_check(opened != LevelData.INVALID_CELL, "шаг 9: на карте есть стена у пола")
	if opened != LevelData.INVALID_CELL:
		world.set_cell_tile(opened, Palette.Tile.FLOOR)
		await get_tree().create_timer(0.5).timeout
		await _compare_census(world, "после пролома стены тайника")

	# ТК-15: трафик при пределе живых врагов (300).
	await _stress_traffic(world)
	await _compare_census(world, "при %d врагах" % STRESS_ENEMIES)

	# ТК-14: недопустимые действия клиента 1.
	var rejected_before := world.net.rejected_events
	var phase_before := world.flow.phase
	_send_to(1, "misbehave")
	await get_tree().create_timer(1.5).timeout
	_check(world.net.rejected_events - rejected_before >= 5,
			"ТК-14: хост отклонил действия с неверными аргументами (%d)" % (world.net.rejected_events - rejected_before))
	_check(world.flow.phase == phase_before and Net.state == Net.State.IN_RUN, "ТК-14: чужой RPC события не изменил состояние хоста")
	await _compare_census(world, "после отклонённых действий")

	# ФТ-07/ФТ-15: переход на следующий уровень — новая карта у всех, инференс только у хоста.
	var index_before := GameState.level_index
	world.net.level_acks.clear()  # ждать подтверждений нового уровня, а не прежних
	world.flow._advance()
	_check(await _wait(func() -> bool: return GameState.level_index == index_before + 1 and world.net.level_acks.size() == CLIENTS, 10.0),
			"ТК-07: переход — клиенты получили новый уровень")
	_check_level_acks(world, "второй уровень")
	await _compare_census(world, "на втором уровне")

	# ТК-12: клиент 2 «упал» — остальные играют дальше.
	var peer2: int = _client_peers.get(2, 0)
	OS.kill(_client_pids[1])
	var lost_at := Time.get_ticks_msec()
	_check(await _wait(func() -> bool: return world.find_player(peer2) == null, 10.0), "ТК-12: хост заметил обрыв клиента 2")
	print("  ..   обрыв замечен за %.1f с" % ((Time.get_ticks_msec() - lost_at) / 1000.0))
	await get_tree().create_timer(1.0).timeout
	_check(is_instance_valid(world) and world.is_inside_tree() and world.flow.phase != LevelFlow.Phase.DEFEAT,
			"ТК-12: игра хоста продолжается")
	await _compare_census(world, "после ухода клиента 2")

	if _lag:
		var lag: Object = multiplayer.multiplayer_peer
		print("  ..   у хоста потеряно ненадёжных пакетов: %d, переслано надёжных: %d" % [lag.get("dropped"), lag.get("resent")])

	# Конец забега в коопе (14.10.2026): хост уводит всех в общее Убежище, сессия остаётся.
	_send_to(1, "expect_hub")
	await get_tree().create_timer(0.5).timeout
	world.leave_run()
	_check(await _wait(func() -> bool: return get_tree().current_scene is Sanctuary, 10.0)
			and Net.is_online() and Net.state == Net.State.LOBBY and Net.players().size() == 2,
			"конец забега: хост в Убежище, сессия осталась (в отряде %d)" % Net.players().size())
	_check(await _wait(func() -> bool: return _hub_report.get("in_hub", false), 10.0),
			"конец забега: клиент 1 тоже в Убежище и в отряде")
	var sees_guest := func() -> bool:
		var hub := get_tree().current_scene as Sanctuary
		return hub != null and hub.remote_heroes().has(_client_peers.get(1, 0))
	_check(await _wait(sees_guest, 5.0) and _hub_report.get("sees_host", false),
			"общее Убежище: хост и клиент 1 видят героев друг друга")

	# ТК-12: хост уходит — клиент 1 сам возвращается в главное меню.
	_send_to(1, "expect_host_leave")
	await get_tree().create_timer(0.5).timeout
	(get_tree().current_scene as Sanctuary).to_main_menu()
	_check(await _wait(func() -> bool: return FileAccess.file_exists(RESULT_FILE % 1), 15.0), "клиент 1 записал итог")
	_read_client_results()
	_finish_host()


## Стена, рядом с которой есть пол: её и «проламывает» проверка шага 9.
func _breakable_wall(level: LevelData) -> Vector2i:
	for cell in level.find_cells(Palette.Tile.WALL):
		for d: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
			if level.in_bounds(cell + d) and level.get_tile(cell + d) == Palette.Tile.FLOOR:
				return cell
	return LevelData.INVALID_CELL


func _heroes_chosen() -> bool:
	for peer in Net.players():
		if peer != 1 and Net.roster[peer].get("hero", &"") == &"":
			return false
	return Net.players().size() == CLIENTS + 1


func _check_level_acks(world: World, what: String) -> void:
	var checksum := GameState.current_level.checksum()
	for peer: int in world.net.level_acks:
		_check(world.net.level_acks[peer] == checksum, "ТК-14 (%s): контрольная сумма карты у участника %d совпала" % [what, peer])
		var ms: int = world.net.level_ack_ms.get(peer, 99999)
		_check(ms <= 1000, "НФТ-07 (%s): уровень доставлен участнику %d за %d мс (≤ 1000)" % [what, peer, ms])


## ТК-13: остановить мир хоста, дать репликации догнать, сверить у каждого клиента.
func _compare_census(world: World, what: String) -> void:
	get_tree().paused = true
	# Враги могли сдвинуться за кадр-другой после последнего снимка — критерий ТК-13 «в пределах
	# одного интервала репликации», поэтому снимок делается заново и сверяется уже он.
	world.net._pack_snapshots()
	await get_tree().create_timer(0.8).timeout
	var mine := _take_census()
	_census.clear()
	for peer in Net.players():
		if peer != 1:
			_census_request.rpc_id(peer)
	await _wait(func() -> bool: return _census.size() == Net.players().size() - 1, 5.0)
	for peer: int in _census:
		_compare(mine, _census[peer], "%s, участник %d" % [what, peer])
	get_tree().paused = false


func _compare(host: Dictionary, client: Dictionary, what: String) -> void:
	var counts_ok: bool = host["counts"] == client["counts"]
	_check(counts_ok, "ТК-13 (%s): набор объектов совпал %s" % [what, client["counts"]] if counts_ok
			else "ТК-13 (%s): набор объектов хост %s ≠ клиент %s" % [what, host["counts"], client["counts"]])
	_check(int(host.get("shots", 0)) > 0 and client.get("shots") == host.get("shots"),
			"ТК-13 (%s): снаряды пачками — все %d выстрелов хоста дошли и построены (у клиента %d)"
			% [what, int(host.get("shots", 0)), int(client.get("shots", 0))])
	_check(client["checksum"] == host["checksum"] and client["level_index"] == host["level_index"],
			"ТК-14 (%s): та же карта и номер уровня" % what)
	_check(not client["generator"], "ТК-14 (%s): у клиента модель не загружалась — инференса нет" % what)
	_check(int(host.get("heat", 0)) > 0 and client.get("heat") == host.get("heat") and client.get("seals") == host.get("seals"),
			"шаг 12.3 (%s): печати хоста у клиента те же — Скверна %d" % [what, int(host.get("heat", 0))])
	_check(client.get("decor") == host.get("decor"), "шаг 11.29 (%s): предметы обстановки у клиента те же, что у хоста" % what)
	_check(client["waves_seen"] == host["waves_seen"] and client["revived_seen"] == host["revived_seen"],
			"ФТ-16 (%s): события у клиента — волны %d, воскрешения %d; у хоста — %d, %d" % [
			what, client["waves_seen"], client["revived_seen"], host["waves_seen"], host["revived_seen"]])
	var bad := PackedStringArray()
	for peer: int in host["players"]:
		var a: Array = host["players"][peer]
		var b: Array = client["players"].get(peer, [])
		if b.is_empty() or (a[0] as Vector2).distance_to(b[0]) > POS_TOLERANCE:
			bad.append("позиция героя %d" % peer)
			continue
		for i in range(1, a.size()):
			if not _same(a[i], b[i]):
				bad.append("герой %d поле %d: %s ≠ %s" % [peer, i, a[i], b[i]])
	var enemies_bad := 0
	var example := ""
	for nid: int in host["enemies"]:
		var a: Array = host["enemies"][nid]
		var b: Array = client["enemies"].get(nid, [])
		if b.is_empty() or (a[0] as Vector2).distance_to(b[0]) > POS_TOLERANCE \
				or absf(a[1] - b[1]) > a[2] / EnemySnapshot.HEALTH_SCALE + VALUE_TOLERANCE:
			enemies_bad += 1
			if example == "":
				example = " (враг %d: хост %s, клиент %s)" % [nid, a, b]
	if enemies_bad > 0:
		bad.append("врагов с расхождением: %d из %d%s" % [enemies_bad, host["enemies"].size(), example])
	for key: String in host["props"]:
		if not _same(host["props"][key], client["props"].get(key)):
			bad.append("объект %s" % key)
	_check(bad.is_empty(), "ТК-13 (%s): синхронизируемые свойства совпали (героев %d, врагов %d)" % [
		what, host["players"].size(), host["enemies"].size()] if bad.is_empty() else "ТК-13 (%s): %s" % [what, "; ".join(bad)])


func _same(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= VALUE_TOLERANCE
	return a == b


## ТК-15: 300 врагов на карте, замер исходящего трафика хоста и частоты снимков у клиентов.
func _stress_traffic(world: World) -> void:
	var markers := GameState.current_level.find_cells(Palette.Tile.ENEMY_SPAWN)
	var id := world.waves.table.waves[0].enemies[0].id
	var need := STRESS_ENEMIES - world.director.hostile_count()
	for i in need:
		var cell: Vector2i = markers[i % markers.size()]
		world.spawn_enemy({"id": id, "pos": world.director.cell_center(cell) + Vector2(i % 7 - 3, i % 5 - 2) * 6.0})
	world.waves.stop()
	var enet := Net.enet
	await get_tree().create_timer(0.5).timeout
	enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	for peer in Net.players():
		if peer != 1:
			_rate_request.rpc_id(peer, true)
	var started := Time.get_ticks_msec()
	var frames_before := Engine.get_process_frames()
	var stream_before := world.net.stream_bytes
	var shots_before := world.net.shots_sent
	await get_tree().create_timer(TRAFFIC_WINDOW).timeout
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	print("  ..   хост при %d врагах: %.0f FPS" % [world.director.hostile_count(), (Engine.get_process_frames() - frames_before) / seconds])
	print("  ..   снаряды пачками: %.0f выстрелов/с, %.2f КБ/с данных на клиента (шаг 5, часть 2)" % [
		(world.net.shots_sent - shots_before) / seconds, (world.net.stream_bytes - stream_before) / 1024.0 / seconds])
	var sent := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var per_client := sent / 1024.0 / seconds / CLIENTS
	var alive := world.director.hostile_count()
	_check(per_client <= TRAFFIC_LIMIT_KBPS, "НФТ-07: трафик хоста %.1f КБ/с на клиента при %d врагах (≤ %d)" % [
		per_client, alive, TRAFFIC_LIMIT_KBPS])
	_census.clear()
	for peer in Net.players():
		if peer != 1:
			_rate_request.rpc_id(peer, false)
	await _wait(func() -> bool: return _census.size() == CLIENTS, 5.0)
	for peer: int in _census:
		var hz: float = _census[peer].get("snapshot_hz", 0.0)
		_check(hz >= NetSync.REPLICATION_HZ, "НФТ-07: снимки врагов у участника %d — %.1f Гц (≥ 20), у него %.0f FPS" % [
			peer, hz, _census[peer].get("fps", 0.0)])


func _take_census() -> Dictionary:
	var world := _world()
	var result := {
		"counts": {}, "players": {}, "enemies": {}, "props": {},
		"checksum": GameState.current_level.checksum() if GameState.current_level != null else "",
		"level_index": GameState.level_index, "generator": LevelService.is_generator_loaded(),
		"waves_seen": _waves_seen, "revived_seen": _revived_seen,
		"heat": RunConfig.heat(), "seals": var_to_str(RunConfig.seals),  # шаг 12.3: печати хоста у всех
		"decor": DecorPlan.signature(GameState.current_level) if GameState.current_level != null else 0,  # шаг 11.29
	}
	if world == null:
		return result
	# Снаряды (шаг 5, часть 2) клиент ведёт сам и долетевшие убирает сам, пока хост на паузе переписи, — их число
	# в моменте не сверяется. Сверяется доставка: сколько выстрелов хост отправил и сколько клиент построил.
	result["counts"] = {
		"players": world.players.get_child_count(), "enemies": world.enemies.get_child_count(),
		"pickups": world.pickups.get_child_count(), "props": world.props.get_child_count(),
	}
	result["shots"] = world.net.shots_sent if multiplayer.is_server() else world.net.shots_received
	for p in world.get_players():
		result["players"][p.peer_id()] = [p.position, p.health, p.max_health, p.alive, p.level, p.xp, p.gold,
				p.kills, p.potions, p.items_collected, p.equipment.size(), p.upgrade_levels, p.runes]
	for e: Node in world.enemies.get_children():
		if e is Enemy:
			result["enemies"][e.get_meta(WorldNet.NID_META, 0)] = [e.position, e.health, e.max_health]
	for node in world.props.get_children():
		if node is Portal:
			result["props"][String(node.name)] = node.active
		elif node is MapObject:
			result["props"][String(node.name)] = node.used
		elif node is Merchant:
			result["props"][String(node.name)] = node.offers.size()
	return result


func _send_to(index: int, command: String) -> void:
	var peer: int = _client_peers.get(index, 0)
	if peer != 0:
		_command.rpc_id(peer, command)


func _read_client_results() -> void:
	var text := FileAccess.get_file_as_string(RESULT_FILE % 1)
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		_check(false, "итог клиента 1 читается")
		return
	print("  ..   клиент 1: подключение за %d мс" % int(data.get("connect_ms", -1)))
	_check(int(data.get("connect_ms", 99999)) <= 5000, "ТК-12: подключение по IP:порт за ≤ 5 с")
	_check(data.get("host_left_menu", false), "ТК-12: после ухода хоста клиент в главном меню, без падения")
	_check(data.get("notice_shown", false), "ТК-12: клиенту показано сообщение «Хост покинул игру»")


func _finish_host() -> void:
	await get_tree().create_timer(0.5).timeout
	_kill_clients()
	print("Провалено проверок: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## Проверка версии: процесс с другой меткой сборки хост не пускает, а клиент узнаёт причину и метку хоста.
func _check_stranger() -> void:
	var result_path := RESULT_FILE % STRANGER_INDEX
	DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
	var log_path := ProjectSettings.globalize_path("user://net_test_client_%d.log" % STRANGER_INDEX)
	_client_pids.append(OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--max-fps", "60",
			"--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tools/net_test.tscn", "--",
			"--role=stranger", "--index=%d" % STRANGER_INDEX, "--port=%d" % _port])))
	var arrived := await _wait(func() -> bool: return FileAccess.file_exists(result_path), 15.0)
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path)) if arrived else null
	_check(report is Dictionary and report.get("reason") == "NET_VERSION_MISMATCH"
			and report.get("args", {}).get("host") == BuildInfo.id() and Net.players().size() == CLIENTS + 1,
			"версия: другая сборка не принята, клиент знает причину и метку хоста: %s" % [report])
	_check(await _wait(func() -> bool: return multiplayer.get_peers().size() == CLIENTS, 5.0),
			"версия: хост отключил чужую сборку, в сессии только свои")


func _kill_clients() -> void:
	for pid in _client_pids:
		if OS.is_process_running(pid):
			OS.kill(pid)


# --- Клиент ---

func _run_client() -> void:
	var hero: HeroData = DataRegistry.HEROES[CLIENT_HEROES[_index - 1]]
	# Как игрок у панели левел-апа: берёт первую карту из своего предложения.
	Events.level_up_offered.connect(func(peer_id: int, cards: Array) -> void:
		if peer_id == multiplayer.get_unique_id() and _world() != null:
			_world().upgrades.submit_choice.call_deferred(cards[0]["id"]))
	Net.session_started.connect(func() -> void: _connect_msec = Time.get_ticks_msec() - _join_started, CONNECT_ONE_SHOT)
	Net.session_failed.connect(func(reason: String) -> void:
		printerr("клиент %d: %s" % [_index, reason])
		get_tree().quit(3))
	_join_started = Time.get_ticks_msec()
	Net.join("127.0.0.1", _port, hero, {}, [&"meteor", "нет_такого", 42])  # шаг 10: закрытые навыки профиля
	await _wait(func() -> bool: return Net.is_online(), 10.0)
	_hello.rpc_id(1, _index)


## Участник с другой сборкой: подключается и записывает, чем кончилось (ждём отказ NET_VERSION_MISMATCH).
func _run_stranger() -> void:
	BuildInfo.override_for_tests("чужая сборка")
	var report := func(reason: String) -> void:
		var file := FileAccess.open(RESULT_FILE % _index, FileAccess.WRITE)
		file.store_string(JSON.stringify({"reason": reason, "args": Net.failure_args}))
		file.close()
		get_tree().quit()
	Net.session_failed.connect(report)
	Net.session_started.connect(report.bind("accepted"))
	Net.join("127.0.0.1", _port, DataRegistry.HEROES[0], {})


@rpc("any_peer", "call_remote", "reliable")
func _hello(index: int) -> void:
	_client_peers[index] = multiplayer.get_remote_sender_id()


@rpc("authority", "call_remote", "reliable")
func _census_request() -> void:
	_census_reply.rpc_id(1, _take_census())


@rpc("any_peer", "call_remote", "reliable")
func _census_reply(data: Dictionary) -> void:
	_census[multiplayer.get_remote_sender_id()] = data


## start — начать счёт снимков врагов; иначе — ответить частотой.
@rpc("authority", "call_remote", "reliable")
func _rate_request(start: bool) -> void:
	var world := _world()
	if world == null:
		return
	var chunk := world.net.get_node_or_null("EnemyState0")
	var sync := chunk.get_node_or_null("Sync") as MultiplayerSynchronizer if chunk != null else null
	if sync == null:
		return
	if start:
		_snapshots_seen = 0
		_result["rate_started"] = Time.get_ticks_msec()
		_result["rate_frames"] = Engine.get_process_frames()
		sync.synchronized.connect(_count_snapshot)
	else:
		sync.synchronized.disconnect(_count_snapshot)
		var seconds := (Time.get_ticks_msec() - int(_result["rate_started"])) / 1000.0
		_census_reply.rpc_id(1, {"snapshot_hz": _snapshots_seen / seconds,
				"fps": (Engine.get_process_frames() - int(_result["rate_frames"])) / seconds})


func _count_snapshot() -> void:
	_snapshots_seen += 1


@rpc("authority", "call_remote", "reliable")
func _command(command: String) -> void:
	var world := _world()
	match command:
		"misbehave":
			if world == null:
				return
			var net := world.net
			net._rpc_choice.rpc_id(1, &"no_such_card")
			net._rpc_choice.rpc_id(1, 42)
			net._rpc_banish.rpc_id(1, 42)  # сумки нет (17.10.2026) — вместо надеть/уничтожить: неверное изгнание
			net._rpc_buy.rpc_id(1, 7, "x")
			net._rpc_buy.rpc_id(1, &"no_such_merchant", 0)
			net._rpc_interact.rpc_id(1, 9999)
			net._rpc_reroll.rpc_id(1)  # предложения карт нет — отказ
			net._event.rpc_id(1, &"run_ended", [true])  # событие хоста от клиента: MultiplayerAPI отбросит
		"expect_host_leave":
			_result["connect_ms"] = _connect_msec
			_watch_host_leave()
		"expect_hub":
			_watch_hub()


## Клиент: после конца забега — в Убежище, сессия жива, герой хоста виден в зале.
func _watch_hub() -> void:
	var arrived := func() -> bool:
		return get_tree().current_scene is Sanctuary and Net.is_online() and Net.state == Net.State.LOBBY
	var host_seen := func() -> bool:
		var hub := get_tree().current_scene as Sanctuary
		return hub != null and hub.remote_heroes().has(1)
	var in_hub: bool = await _wait(arrived, 15.0)
	var sees_host: bool = await _wait(host_seen, 5.0)
	_hub_reply.rpc_id(1, {"in_hub": in_hub, "sees_host": sees_host})


@rpc("any_peer", "call_remote", "reliable")
func _hub_reply(data: Dictionary) -> void:
	_hub_report = data


func _watch_host_leave() -> void:
	await _wait(func() -> bool: return not Net.is_online(), 15.0)
	await get_tree().create_timer(1.0).timeout
	var scene := get_tree().current_scene
	_result["host_left_menu"] = scene != null and scene.scene_file_path == ScenePaths.MAIN_MENU
	var notice := scene.get_node_or_null("%Notice") as Label if scene != null else null
	_result["notice_shown"] = notice != null and notice.visible and notice.text == tr("NET_HOST_LEFT")
	var file := FileAccess.open(RESULT_FILE % _index, FileAccess.WRITE)
	file.store_string(JSON.stringify(_result))
	file.close()
	get_tree().quit(0)


# --- Общее ---

func _world() -> World:
	return get_tree().current_scene as World


func _wait(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
	print(("  OK   " if ok else "  FAIL ") + message)
