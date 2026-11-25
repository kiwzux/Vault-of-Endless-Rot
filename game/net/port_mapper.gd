class_name PortMapper
extends Node
## UPnP (18.10.2026): хост просит роутер открыть UDP-порт сессии — друзья по Интернету подключаются к внешнему
## адресу роутера без Radmin VPN и ручного проброса. Узел — ребёнок автозагрузки Net (Net.port_mapper);
## порт открывает лобби после создания сессии, закрывают Net.leave и выход из игры.
##
## Поиск роутера и запросы к нему блокируют (поиск — DISCOVER_MS на каждый сетевой интерфейс, на ПК с VPN
## до ~8 с), поэтому идут в отдельном потоке; итог разбирается
## в _process. Порт открывается с арендой LEASE: если игра упадёт, роутер сам закроет его позже. Роутер без
## UPnP, отказ роутера и «общий адрес провайдера» (CGNAT: внешний адрес роутера сам частный) — свои статусы:
## Убежище показывает хосту, что делать (Radmin VPN или проброс порта). По сети ничего не передаётся.

signal changed

enum Status { IDLE, WORKING, OPEN, NO_ROUTER, REFUSED, SHARED_ADDRESS }

## Сколько ждать ответа роутера при поиске, мс.
const DISCOVER_MS := 2000
const LEASE := 4 * 3600
const DESCRIPTION := "Vault of Endless Rot"
## Частные и служебные диапазоны IPv4: адрес из них из Интернета не достижим.
const PRIVATE_RANGES := [["10.0.0.0", 8], ["172.16.0.0", 12], ["192.168.0.0", 16], ["100.64.0.0", 10],
		["169.254.0.0", 16], ["127.0.0.0", 8], ["0.0.0.0", 8]]

var status := Status.IDLE
## Внешний адрес роутера (OPEN, SHARED_ADDRESS).
var external_address := ""
var port := 0
## Код ответа UPnP при NO_ROUTER и REFUSED (UPNP.UPNPResult).
var error_code := 0

## Задачи потоков: [Thread, вид ("open" / "close"), поколение].
var _jobs: Array = []
## Каждое open/close — новое поколение: итог устаревшего открытия не показывается, его порт сразу закрывается.
var _generation := 0
## Роутер с открытым портом — для закрытия.
var _upnp: UPNP


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_shutdown()


## Открыть UDP-порт p_port на роутере (в фоне; итог — status и сигнал changed).
func open(p_port: int) -> void:
	close()
	port = p_port
	status = Status.WORKING
	_start(_open_job.bind(p_port), "open")
	changed.emit()


## Закрыть открытый порт (в фоне) и забыть итог.
func close() -> void:
	_generation += 1
	if _upnp != null:
		_start(_close_job.bind(_upnp, port), "close")
		_upnp = null
	if status != Status.IDLE:
		status = Status.IDLE
		external_address = ""
		error_code = 0
		changed.emit()


## Адрес IPv4 из частного или служебного диапазона (за ним — ещё один NAT, из Интернета не достать).
## Не адрес IPv4 — тоже true.
static func is_private_address(address: String) -> bool:
	var value := _ipv4(address)
	if value < 0:
		return true
	for block: Array in PRIVATE_RANGES:
		var mask := (0xFFFFFFFF << (32 - int(block[1]))) & 0xFFFFFFFF
		if value & mask == _ipv4(block[0]) & mask:
			return true
	return false


static func _ipv4(address: String) -> int:
	var parts := address.strip_edges().split(".")
	if parts.size() != 4:
		return -1
	var value := 0
	for part in parts:
		if not part.is_valid_int() or part.to_int() < 0 or part.to_int() > 255:
			return -1
		value = (value << 8) | part.to_int()
	return value


func _process(_delta: float) -> void:
	for job: Array in _jobs.duplicate():
		var thread: Thread = job[0]
		if thread.is_alive():
			continue
		_jobs.erase(job)
		var result: Variant = thread.wait_to_finish()
		if job[1] == "open" and result is Dictionary:
			_apply(result, job[2])
	set_process(not _jobs.is_empty())


func _apply(result: Dictionary, generation: int) -> void:
	var upnp: UPNP = result.get("upnp")
	if generation != _generation:
		if upnp != null:  # хост уже ушёл или открыл другой порт: этот — закрыть
			_start(_close_job.bind(upnp, int(result["port"])), "close")
		return
	_upnp = upnp
	status = result["status"]
	external_address = result.get("address", "")
	error_code = result.get("code", 0)
	changed.emit()


func _start(job: Callable, kind: String) -> void:
	var thread := Thread.new()
	thread.start(job)
	_jobs.append([thread, kind, _generation])
	set_process(true)


## Выход из игры: дождаться потоков и закрыть все открытые порты сразу, без потоков.
func _shutdown() -> void:
	for job: Array in _jobs:
		var result: Variant = (job[0] as Thread).wait_to_finish()
		if job[1] == "open" and result is Dictionary and result.get("upnp") != null:
			(result["upnp"] as UPNP).delete_port_mapping(int(result["port"]), "UDP")
	_jobs.clear()
	if _upnp != null:
		_upnp.delete_port_mapping(port, "UDP")
		_upnp = null


# --- В потоке: только свои аргументы, без полей узла ---

## Найти роутер, открыть порт, узнать внешний адрес. {"status", "code"} или ещё "address", "upnp", "port".
func _open_job(p_port: int) -> Dictionary:
	var upnp := UPNP.new()
	var found := upnp.discover(DISCOVER_MS, 2, "InternetGatewayDevice")
	if found != UPNP.UPNP_RESULT_SUCCESS or upnp.get_device_count() == 0 or upnp.get_gateway() == null \
			or not upnp.get_gateway().is_valid_gateway():
		return {"status": Status.NO_ROUTER, "code": found}
	var code := upnp.add_port_mapping(p_port, p_port, DESCRIPTION, "UDP", LEASE)
	if code in [UPNP.UPNP_RESULT_ONLY_PERMANENT_LEASE_SUPPORTED, UPNP.UPNP_RESULT_INVALID_DURATION]:
		code = upnp.add_port_mapping(p_port, p_port, DESCRIPTION, "UDP", 0)  # роутер не умеет аренду — бессрочно
	if code != UPNP.UPNP_RESULT_SUCCESS:
		return {"status": Status.REFUSED, "code": code}
	var address := upnp.query_external_address()
	return {"status": Status.SHARED_ADDRESS if is_private_address(address) else Status.OPEN, "address": address,
			"upnp": upnp, "port": p_port, "code": code}


func _close_job(upnp: UPNP, p_port: int) -> int:
	return upnp.delete_port_mapping(p_port, "UDP")
