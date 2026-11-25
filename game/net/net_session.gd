extends Node
## Автозагрузка Net — сетевая сессия «хост–клиенты» (ФТ-12, ОГР-04). Курсовая Ворончихина В.А.
##
## Хост создаёт сессию (ENetMultiplayerPeer.create_server), до MAX_CLIENTS клиентов подключаются по IP:порт
## (create_client). Сессией управляет MultiplayerAPI дерева сцен, хост — авторитетный узел (peer id 1).
## Одиночная игра — та же игра без сессии: в дереве OfflineMultiplayerPeer, is_server() == true.
##
## Лобби: каждый участник выбирает героя; ранги его талантов из хаба (MetaProfile) уходят хосту вместе с
## выбором. Состав (roster) хранит и рассылает хост; он же включает «Хардкор» и начинает забег.
## После начала забега новые подключения отклоняются: подключиться можно только в лобби.
## Общее Убежище (14.10.2026): созданная или найденная сессия сразу ведёт в Убежище (окно подключения — сцена
## Lobby); пока сессия в лобби, участники видят героев друг друга в зале (send_hub_state, ~20 Гц, ненадёжно),
## выбирают героя у статуй, хост начинает забег у Врат. Конец забега (победа, поражение, выход хоста) —
## return_to_hub: все участники возвращаются в Убежище, сессия остаётся, подключаться снова можно.
##
## Отключения: клиент ушёл — хост убирает его героя, остальные играют дальше (WorldNet);
## хост ушёл — клиент возвращается в главное меню с сообщением (души за забег начисляются).
##
## Версия (14.10.2026): подключившийся клиент сначала присылает метку своей сборки (BuildInfo, _hello). Хост
## принимает его в сессию (_welcome, состав лобби) только при той же метке; иначе отвечает своей меткой (_refuse)
## и отключает. Клиент, который за HELLO_TIMEOUT метку не прислал (старая сборка без рукопожатия), отключается.
## До приёма участник не входит в состав: его выбор героя, состояние в Убежище и готовность уровня не принимаются.
##
## UPnP (18.10.2026): хост из лобби просит роутер открыть порт сессии (port_mapper, PortMapper); leave закрывает.

signal session_started
## reason — ключ перевода.
signal session_failed(reason: String)
signal session_ended(reason: String)
signal roster_changed
signal peer_left(peer_id: int)
## Убежище: где сейчас герой участника peer_id и кем он встал (send_hub_state).
signal hub_state_received(peer_id: int, hero_id: StringName, pos: Vector2)

const DEFAULT_PORT := 24565
## До 4 игроков: хост и 3 клиента (ОГР-04).
const MAX_CLIENTS := 3
const MAX_PLAYERS := MAX_CLIENTS + 1
## ФТ-12: подключение по IP:порт не дольше 5 с — дальше считаем, что хост не отвечает.
const CONNECT_TIMEOUT := 5.0
## Хост: столько секунд ждёт метку сборки от подключившегося клиента.
const HELLO_TIMEOUT := 5.0
## Хост: после отказа (другая сборка) отключает клиента с задержкой — чтобы ответ с причиной успел дойти.
const REFUSE_KICK_DELAY := 0.5
## Разрыв без прощания (процесс упал, кабель выдернут) замечается за ENET_TIMEOUT_MAX мс.
const ENET_TIMEOUT_LIMIT := 32
const ENET_TIMEOUT_MIN := 2000
const ENET_TIMEOUT_MAX := 5000
## Троттлинг ENet: по колебаниям RTT ENet сам выбрасывает часть ненадёжных пакетов. Снимки врагов идут
## ненадёжно и уже уложены в бюджет НФТ-07, поэтому понижение троттлинга выключено (замедление 0):
## без этого до клиента доходило 16–22 снимка в секунду из 30 при 60 FPS у всех участников.
const ENET_THROTTLE_INTERVAL := 5000
const ENET_THROTTLE_ACCELERATION := 2
const ENET_THROTTLE_DECELERATION := 0
## Предел числа талантов в пакете от клиента: защищает от испорченных данных.
const MAX_TALENTS := 32
const MAX_LOCKED := 64

enum State { OFFLINE, CONNECTING, LOBBY, IN_RUN }

var state := State.OFFLINE
## Хост: порт сессии (для подсказки друзьям).
var host_port := 0
## peer id → {"hero": StringName, "talents": {id: ранг}, "locked": [id навыка]}. Источник истины — хост.
var roster := {}
var hardcore := false
## Печати Скверны на забег (шаг 12.3): {id печати: ранг}. Ставит хост, приходят всем с составом лобби.
var seals := {}
## Клиенты, у которых загрузилась сцена уровня (хост ждёт их перед загрузкой уровня, WorldNet).
var world_ready_peers := {}
## Сообщение для главного меню после разрыва (ключ перевода); читается один раз.
var _notice := ""
var _connect_left := 0.0
## Клиент: соединение есть, ждём ответа хоста на метку сборки.
var _handshaking := false
## Клиент: выбор героя, который уйдёт хосту сразу после приёма в сессию.
var _pending_entry := {}
## Хост: подключившиеся, но ещё не приславшие метку сборки, peer id → секунд осталось.
var _unverified := {}
## Подстановки в текст причины session_failed (метки сборок при NET_VERSION_MISMATCH).
var failure_args := {}
## Соединение ENet текущей сессии (null — вне сессии): тайм-ауты, отключение участника, статистика трафика.
var enet: ENetMultiplayerPeer
## Только для испытаний ТК-15: обёртка над ENet, которая добавляет задержку и потери
## (tools/net/lag_peer.gd). В игре не задаётся — в дереве стоит сам ENetMultiplayerPeer (ОГР-04).
var peer_wrapper := Callable()
## UPnP хоста: открыть порт сессии на роутере (вызывает лобби; испытания его не трогают — роутер не просится).
var port_mapper: PortMapper


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # разрыв и тайм-аут подключения — и во время паузы
	port_mapper = PortMapper.new()
	port_mapper.name = "PortMapper"
	add_child(port_mapper)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if not _unverified.is_empty():
		for peer_id: int in _unverified.keys():
			_unverified[peer_id] -= delta
			if _unverified[peer_id] <= 0.0:
				_unverified.erase(peer_id)
				push_warning("Net: участник %d не прислал метку сборки — другая версия игры, отключён" % peer_id)
				kick(peer_id)
	if state != State.CONNECTING:
		return
	_connect_left -= delta
	if _connect_left <= 0.0:
		# Соединение было, а приёма нет: хост не знает рукопожатия — у него другая (старая) сборка.
		_fail("NET_VERSION_UNCONFIRMED" if _handshaking else "NET_CONNECT_TIMEOUT")


## Идёт сетевая сессия (хост с ENet или подключённый клиент).
func is_online() -> bool:
	return state in [State.LOBBY, State.IN_RUN]


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


## Участники сессии по возрастанию peer id (хост первый); вне сессии — пусто.
func players() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(roster.keys())
	ids.sort()
	return ids


# --- Создание и подключение ---

## ФТ-12: хост создаёт сессию. OK — лобби открыто.
func host(port: int, hero: HeroData, talents: Dictionary, locked: Array = []) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		session_failed.emit("NET_HOST_FAILED")
		return err
	_install(peer)
	state = State.LOBBY
	host_port = port
	roster = {1: _entry(hero, talents, locked)}
	hardcore = false
	seals = {}
	session_started.emit()
	roster_changed.emit()
	return OK


## ФТ-12: клиент подключается к хосту по IP:порт. Итог — session_started или session_failed.
func join(address: String, port: int, hero: HeroData, talents: Dictionary, locked: Array = []) -> Error:
	leave()
	failure_args = {}
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		session_failed.emit("NET_CONNECT_FAILED")
		return err
	_install(peer)
	state = State.CONNECTING
	_connect_left = CONNECT_TIMEOUT
	roster = {}
	_pending_entry = _entry(hero, talents, locked)
	return OK


## Участник принят хостом (метка сборки совпала). У хоста — все подключённые, кроме ждущих проверки.
func is_verified(peer_id: int) -> bool:
	return peer_id in multiplayer.get_peers() and not _unverified.has(peer_id)


## Выйти из сессии: закрыть соединение и вернуть одиночный режим. reason — сообщение для меню.
func leave(reason: String = "") -> void:
	if reason != "":
		_notice = reason
	var was_online := is_online()
	if port_mapper != null:
		port_mapper.close()
	if enet != null:
		enet.close()
		enet = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	state = State.OFFLINE
	roster = {}
	world_ready_peers = {}
	_unverified = {}
	_handshaking = false
	if was_online:
		session_ended.emit(reason)


## Сообщение о разрыве для главного меню; после чтения стирается.
func take_notice() -> String:
	var text := _notice
	_notice = ""
	return text


## Адреса IPv4 этого ПК (локальная сеть, Radmin VPN) — их хост сообщает друзьям; без петли и автонастройки.
static func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append(address)
	if result.is_empty():
		result.append("127.0.0.1")
	return result


## Хост: отключить участника (не успел загрузить уровень, пришёл после начала забега).
func kick(peer_id: int) -> void:
	if enet != null and multiplayer.is_server() and peer_id in multiplayer.get_peers():
		enet.disconnect_peer(peer_id)


## Сжатие пакетов ENet (одинаковое у хоста и клиентов) и передача соединения MultiplayerAPI.
func _install(peer: ENetMultiplayerPeer) -> void:
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	enet = peer
	multiplayer.multiplayer_peer = peer_wrapper.call(peer) if peer_wrapper.is_valid() else peer


## Настройка соединения с участником: быстрое обнаружение разрыва (не подтверждает пакеты — отключён
## за ENET_TIMEOUT_MAX мс) и троттлинг без выбрасывания снимков.
func _tune_peer(peer_id: int) -> void:
	var packet_peer := enet.get_peer(peer_id) if enet != null else null
	if packet_peer != null:
		packet_peer.set_timeout(ENET_TIMEOUT_LIMIT, ENET_TIMEOUT_MIN, ENET_TIMEOUT_MAX)
		packet_peer.throttle_configure(ENET_THROTTLE_INTERVAL, ENET_THROTTLE_ACCELERATION, ENET_THROTTLE_DECELERATION)


# --- Лобби ---

## Свой выбор героя (ранги его талантов и закрытые навыки профиля) — хосту.
func choose_hero(hero: HeroData, talents: Dictionary, locked: Array = []) -> void:
	if not is_online() or state == State.IN_RUN:
		return
	if multiplayer.is_server():
		roster[1] = _entry(hero, talents, locked)
		_broadcast_lobby()
	else:
		_register.rpc_id(1, hero.id, talents, sanitize_locked(locked))


## Хост: «Хардкор» на весь забег для всех участников.
func set_hardcore(on: bool) -> void:
	if is_host() and state == State.LOBBY:
		hardcore = on
		_broadcast_lobby()


## Хост: печати Скверны на весь забег для всех участников (шаг 12.3).
func set_seals(chosen: Dictionary) -> void:
	if is_host() and state == State.LOBBY:
		seals = SealData.sanitize(chosen)
		_broadcast_lobby()


## Хост: начать забег. Все участники получают сид, сложность и состав и загружают сцену уровня.
func start_run() -> void:
	if not is_host() or state != State.LOBBY:
		return
	for peer_id: int in _unverified.keys():  # не успевшие пройти проверку версии в забег не попадают
		kick(peer_id)
	_unverified = {}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_begin_run.rpc(rng.randi(), hardcore, seals, roster)


## Хост: забег окончен (победа, поражение или выход хоста) — все участники возвращаются в Убежище,
## сессия остаётся открытой (лобби).
## Хост уходит первым и зовёт клиентов кадром позже: удаление объектов уровня (MultiplayerSpawner) доходит до клиентов
## раньше команды — по тому же надёжному каналу, пока их уровень ещё на месте.
func return_to_hub() -> void:
	if not is_host() or state != State.IN_RUN:
		return
	_return_to_hub()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_host():
		_return_to_hub.rpc()


## Свой герой в Убежище — остальным участникам (Sanctuary, ~20 раз в секунду). Только в лобби.
func send_hub_state(hero_id: StringName, pos: Vector2) -> void:
	if is_online() and state == State.LOBBY and not multiplayer.get_peers().is_empty():
		_hub_state.rpc(hero_id, pos)


## Клиент: сцена уровня загружена, можно присылать уровень и объекты (вызывает WorldNet).
func report_world_ready() -> void:
	if is_online() and not multiplayer.is_server():
		_world_ready.rpc_id(1)


func _entry(hero: HeroData, talents: Dictionary, locked: Array) -> Dictionary:
	return {"hero": hero.id, "talents": talents.duplicate(), "locked": sanitize_locked(locked)}


## Ранги талантов от клиента: только известные id и целые ранги в пределах данных.
static func sanitize_talents(raw: Variant) -> Dictionary:
	var result := {}
	if not (raw is Dictionary):
		return result
	for id: Variant in raw:
		if result.size() >= MAX_TALENTS:
			break
		var talent := DataRegistry.talent(StringName(str(id)))
		var rank: Variant = raw[id]
		if talent != null and rank is int:
			result[talent.id] = clampi(rank, 0, talent.max_rank)
	return result


## Закрытые навыки от клиента (шаг 10): только известные id навыков, без повторов, не больше MAX_LOCKED.
## Список только сужает пул левел-апа самого игрока; подмена открывает лишь его собственные карты (ЛР2, 4.4.4).
static func sanitize_locked(raw: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not (raw is Array):
		return result
	for id: Variant in raw:
		if result.size() >= MAX_LOCKED:
			break
		var upgrade := DataRegistry.upgrade(StringName(str(id))) if (id is StringName or id is String) else null
		if upgrade != null and not upgrade.id in result:
			result.append(upgrade.id)
	return result


func _broadcast_lobby() -> void:
	_sync_lobby.rpc(roster, hardcore, seals)
	roster_changed.emit()


## Клиент → хост: выбор героя. Хост проверяет отправителя и данные (ФТ-16).
@rpc("any_peer", "call_remote", "reliable")
func _register(hero_id: Variant, talents: Variant, locked: Variant) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or state != State.LOBBY or not is_verified(sender):
		return
	var hero := DataRegistry.hero(StringName(str(hero_id))) if (hero_id is StringName or hero_id is String) else null
	if hero == null:
		push_warning("Net: участник %d прислал неизвестного героя — отклонено" % sender)
		return
	roster[sender] = {"hero": hero.id, "talents": sanitize_talents(talents), "locked": sanitize_locked(locked)}
	_broadcast_lobby()


## Хост → клиенты: состав лобби, сложность и печати Скверны.
@rpc("authority", "call_remote", "reliable")
func _sync_lobby(p_roster: Dictionary, p_hardcore: bool, p_seals: Dictionary) -> void:
	if state != State.LOBBY:  # ещё не принят хостом (проверка версии)
		return
	roster = p_roster
	hardcore = p_hardcore
	seals = SealData.sanitize(p_seals)
	roster_changed.emit()


## Хост → все: забег начался.
@rpc("authority", "call_local", "reliable")
func _begin_run(seed: int, p_hardcore: bool, p_seals: Dictionary, p_roster: Dictionary) -> void:
	if state != State.LOBBY:  # не принят хостом — в забег не идёт (хост его и так отключает)
		return
	roster = p_roster
	hardcore = p_hardcore
	seals = SealData.sanitize(p_seals)
	world_ready_peers = {}
	state = State.IN_RUN
	if multiplayer.is_server():
		multiplayer.multiplayer_peer.refuse_new_connections = true
	var mine: Dictionary = roster.get(multiplayer.get_unique_id(), {})
	var hero := DataRegistry.hero(mine.get("hero", &""))
	if hero == null:
		hero = DataRegistry.HEROES[0]
	MetaProfile.set_last_hero(hero)
	RunConfig.start_new_run(hero, hardcore, seed, mine.get("talents", {}), mine.get("locked", []), seals)
	get_tree().change_scene_to_file(ScenePaths.WORLD)


## Хост → клиенты (и сам хост — локальным вызовом): в Убежище. Каждый участник сам начисляет себе души за забег
## (World.finish_run) — профиль у каждого свой.
@rpc("authority", "call_remote", "reliable")
func _return_to_hub() -> void:
	state = State.LOBBY
	world_ready_peers = {}
	if multiplayer.is_server():
		multiplayer.multiplayer_peer.refuse_new_connections = false
	var world := get_tree().current_scene as World
	if world != null:
		world.finish_run(ScenePaths.HUB, false)
	else:
		get_tree().change_scene_to_file(ScenePaths.HUB)


## Участник → остальные: его герой в Убежище. Чужие данные проверяются: известный герой, участник сессии.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _hub_state(hero_id: Variant, pos: Variant) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if state != State.LOBBY or not (pos is Vector2) or not (hero_id is StringName or hero_id is String):
		return
	var hero := DataRegistry.hero(StringName(str(hero_id)))
	if hero != null and roster.has(sender):
		hub_state_received.emit(sender, hero.id, pos)


@rpc("any_peer", "call_remote", "reliable")
func _world_ready() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and roster.has(sender):
		world_ready_peers[sender] = true


# --- Проверка версии ---

## Клиент → хост: метка сборки. Та же — участник принят: ответ и состав лобби; другая — отказ и отключение.
@rpc("any_peer", "call_remote", "reliable")
func _hello(build: Variant) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _unverified.has(sender):
		return
	_unverified.erase(sender)
	if build is String and build == BuildInfo.id():
		_welcome.rpc_id(sender)
		_sync_lobby.rpc_id(sender, roster, hardcore, seals)
		return
	push_warning("Net: участник %d — другая сборка (%s, у хоста %s), отключён" % [sender, str(build), BuildInfo.id()])
	_refuse.rpc_id(sender, BuildInfo.id())
	get_tree().create_timer(REFUSE_KICK_DELAY, true, false, true).timeout.connect(kick.bind(sender))


## Хост → клиент: принят в сессию.
@rpc("authority", "call_remote", "reliable")
func _welcome() -> void:
	if state != State.CONNECTING:
		return
	_handshaking = false
	state = State.LOBBY
	session_started.emit()
	if not _pending_entry.is_empty():
		_register.rpc_id(1, _pending_entry["hero"], _pending_entry["talents"], _pending_entry["locked"])


## Хост → клиент: другая сборка игры; host_build — метка хоста (для сообщения игроку).
@rpc("authority", "call_remote", "reliable")
func _refuse(host_build: Variant) -> void:
	if state != State.CONNECTING:
		return
	failure_args = {"mine": BuildInfo.id(), "host": str(host_build)}
	_fail("NET_VERSION_MISMATCH")


# --- События MultiplayerAPI ---

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_tune_peer(peer_id)
	if state != State.LOBBY:
		# Забег уже идёт: подключиться можно только в лобби (refuse_new_connections это и так запрещает).
		kick(peer_id)
		return
	_unverified[peer_id] = HELLO_TIMEOUT  # состав лобби — после проверки версии (_hello)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		roster.erase(peer_id)
		roster_changed.emit()
		return
	_unverified.erase(peer_id)
	roster.erase(peer_id)
	world_ready_peers.erase(peer_id)
	peer_left.emit(peer_id)
	if state == State.LOBBY:
		_broadcast_lobby()


## Соединение есть — сначала проверка версии: метка сборки хосту, приём — в _welcome.
func _on_connected_to_server() -> void:
	_tune_peer(1)
	_handshaking = true
	_connect_left = CONNECT_TIMEOUT
	_hello.rpc_id(1, BuildInfo.id())


func _on_connection_failed() -> void:
	_fail("NET_CONNECT_FAILED")


## ФТ-12: хост отключился — в главное меню с сообщением, без аварийного завершения (и из забега, и из Убежища).
func _on_server_disconnected() -> void:
	var world := get_tree().current_scene as World
	var in_hub := get_tree().current_scene is Sanctuary
	leave("NET_HOST_LEFT")
	if world != null:
		world.finish_run(ScenePaths.MAIN_MENU)
	elif in_hub:
		get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)


func _fail(reason: String) -> void:
	leave()
	session_failed.emit(reason)
