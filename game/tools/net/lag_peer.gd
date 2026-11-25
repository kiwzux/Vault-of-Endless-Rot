extends MultiplayerPeerExtension
## Эмуляция плохой сети для испытания ТК-15 (ТЗ 4.6: «сетевые испытания … с эмуляцией задержки и потерь
## пакетов»). Только для tools/net_test: игра всегда работает напрямую через ENetMultiplayerPeer (ОГР-04).
##
## Обёртка над ENetMultiplayerPeer: исходящие пакеты уходят как есть, входящие выдаются MultiplayerAPI
## не раньше чем через delay_ms. Обёртка стоит у всех участников, поэтому RTT = 2 × delay_ms.
## Потери (loss — доля):
##  - ненадёжный пакет просто пропадает;
##  - надёжный ENet переслал бы — здесь он приходит позже ещё на один RTT.
## Очередь общая и не перемешивается: опоздавший надёжный пакет задерживает и следующие за ним,
## как это и бывает при повторной отправке.

var inner: ENetMultiplayerPeer
var delay_ms := 50
var loss := 0.02
## Сколько пакетов «потеряно» и «переслано» — для отчёта испытания.
var dropped := 0
var resent := 0

var _queue: Array[Dictionary] = []
var _last_release := 0
var _rng := RandomNumberGenerator.new()
var _target_peer := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _init(p_inner: ENetMultiplayerPeer, p_delay_ms: int, p_loss: float, seed: int = 0) -> void:
	inner = p_inner
	delay_ms = p_delay_ms
	loss = p_loss
	_rng.seed = seed if seed != 0 else hash(Time.get_ticks_usec())
	inner.peer_connected.connect(func(id: int) -> void: peer_connected.emit(id))
	inner.peer_disconnected.connect(func(id: int) -> void:
		_queue = _queue.filter(func(packet: Dictionary) -> bool: return packet["peer"] != id)
		peer_disconnected.emit(id))


func _poll() -> void:
	inner.poll()
	var now := Time.get_ticks_msec()
	while inner.get_available_packet_count() > 0:
		var packet := {
			"peer": inner.get_packet_peer(), "channel": inner.get_packet_channel(), "mode": inner.get_packet_mode(),
		}
		packet["data"] = inner.get_packet()
		var release := now + delay_ms
		if _rng.randf() < loss:
			if packet["mode"] != MultiplayerPeer.TRANSFER_MODE_RELIABLE:
				dropped += 1
				continue
			resent += 1
			release += delay_ms * 2
		_last_release = maxi(_last_release, release)
		packet["time"] = _last_release
		_queue.append(packet)


func _get_available_packet_count() -> int:
	var now := Time.get_ticks_msec()
	var count := 0
	for packet in _queue:
		if packet["time"] > now:
			break
		count += 1
	return count


func _get_packet_script() -> PackedByteArray:
	return _queue.pop_front()["data"] if not _queue.is_empty() else PackedByteArray()


func _get_packet_peer() -> int:
	return _queue[0]["peer"] if not _queue.is_empty() else 0


func _get_packet_channel() -> int:
	return _queue[0]["channel"] if not _queue.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _queue[0]["mode"] if not _queue.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _put_packet_script(buffer: PackedByteArray) -> Error:
	inner.set_target_peer(_target_peer)
	inner.transfer_channel = _channel
	inner.transfer_mode = _mode
	return inner.put_packet(buffer)


func _get_max_packet_size() -> int:
	return 1 << 24


func _set_target_peer(peer: int) -> void:
	_target_peer = peer


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _get_unique_id() -> int:
	return inner.get_unique_id()


func _is_server() -> bool:
	return inner.get_unique_id() == 1


func _is_server_relay_supported() -> bool:
	return inner.is_server_relay_supported()


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return inner.get_connection_status()


func _set_refuse_new_connections(enable: bool) -> void:
	inner.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return inner.refuse_new_connections


func _disconnect_peer(peer: int, force: bool) -> void:
	inner.disconnect_peer(peer, force)


func _close() -> void:
	inner.close()
	_queue.clear()
