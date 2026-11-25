extends Node
## Стенд производительности (шаг 2, раздел 8 ТЗ): фиксированный сид, N врагов, M героев с пятью видами
## оружия 10-го уровня сверх стартового. Итог — в консоль и строкой JSON в user://bench.jsonl: прогоны
## до и после оптимизации сравниваются построчно.
##
## Что меряется:
## - тик логики хоста — все _physics_process за шаг физики (враги, оружие, снаряды, статусы, волны);
##   метки начала и конца — узлы с крайними приоритетами process_physics_priority;
## - кадр процесса — все _process за кадр (HUD, цифры урона, эффекты), так же метками;
## - отрисовка на CPU и GPU (RenderingServer, только с окном), вызовы отрисовки, узлы, снаряды.
## «Кадр при 60 FPS» = тик логики + кадр процесса + отрисовка CPU: должен быть меньше 16,7 мс.
## Худший случай — по 99-му перцентилю тика. Мониторы Performance.TIME_* здесь не годятся: Godot отдаёт
## в них худшее значение за последнюю секунду, а не среднее.
##
## С окном (учитывается отрисовка — так мерить на слабом ПК):
##   godot --path game res://tools/bench.tscn -- --enemies=300 --players=4 --seconds=20
## Без окна (только логика хоста): то же с --headless.
## VSync выключен и предела FPS нет: кадр без предела показывает запас, а не ожидание экрана.
## --probe (шаг 5): разбивка тика по системам (PerfProbe) — враги (из них расталкивание и move_and_slide),
## навигация, навыки, снаряды, подбираемое, статусы. Замер сам стоит ~0,1–0,2 мс, поэтому сравнивать тики
## нужно прогонами без --probe.
## --quality=0|1|2 (шаг 11.8): качество эффектов на этот прогон (0 — без карты света); строка «lights» в --probe.
## Герои — один процесс без сети (боты 2…M — узлы с чужим peer id, их водит стенд). Трафик кооператива
## меряет tools/net_test.tscn.

const WARMUP := 3.0
const BOT_RADIUS := 60.0
const BOT_SPEED := 0.8
## Сколько врагов досыпать за кадр, пока их меньше заданного.
const SPAWN_PER_FRAME := 20
const WEAPON_LEVEL := 10
const WEAPONS: Array[StringName] = [&"fireball", &"frost_ring", &"chain_lightning", &"throwing_daggers", &"orbiting_skulls"]
## --heavy (шаг 5): поздняя сборка «много снарядов» — навыки 20-го уровня, руны раскола и рикошета, Залп.
## Худший случай для сети: каждый снаряд и осколок — посылка спавнера.
const HEAVY_WEAPONS: Array[StringName] = [&"fire_nova", &"throwing_daggers", &"silver_bolts", &"bone_arrow", &"frost_ring"]
const HEAVY_LEVEL := 20
const HEAVY_RUNES := {&"throwing_daggers": [&"rune_split"], &"bone_arrow": [&"rune_split", &"rune_ricochet"],
	&"silver_bolts": [&"rune_split"]}
## Столько уровней у героев стенда: до следующего столько опыта, что левел-ап не наступит.
const BENCH_LEVEL := 500
const LOG_PATH := "user://bench.jsonl"
const FIRST := -100000
const LAST := 100000


## Метка конца тика и кадра: её колбэки идут последними.
class EndMark:
	extends Node
	var bench: Node

	func _physics_process(_delta: float) -> void:
		bench.end_tick()

	func _process(_delta: float) -> void:
		bench.end_frame()


var _enemies := 300
var _players := 4
var _seconds := 20.0
var _world: World
var _host: Player
var _bots: Array[Player] = []
var _clock := 0.0
var _measured := 0.0
var _tick_begin := 0
var _frame_begin := 0
var _frame_ms := PackedFloat32Array()
var _tick_ms := PackedFloat32Array()
var _process_ms := PackedFloat32Array()
var _render_cpu_ms := PackedFloat32Array()
var _render_gpu_ms := PackedFloat32Array()
var _draw_calls := PackedFloat32Array()
var _alive := PackedFloat32Array()
var _max_nodes := 0
var _max_projectiles := 0
var _measuring := false
var _finished := false
var _probe := false
var _heavy := false
## Сколько узлов создано в World/Projectiles после разогрева: снаряды (Projectile) и следы (CombatFx).
## До шага 5, часть 2 каждый был отдельной надёжной посылкой спавнера каждому клиенту — _spawn_bytes оценивает её
## данные словарём, как их слал MultiplayerSpawner. Теперь они уходят пачками кадра (ProjectileStream): стенд
## включает WorldNet.measure_stream и считает настоящие байты пачек (_stream_from — их счётчик на начало замера).
var _spawned_shots := 0
var _spawned_fx := 0
var _spawn_bytes := 0
var _stream_from := -1
## Сколько тиков было до включения PerfProbe: разбивка делится на тики после разогрева.
var _probe_from := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # стенд работает и на паузе: снимает её сам (см. _process)
	process_priority = FIRST
	process_physics_priority = FIRST
	_parse_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var mark := EndMark.new()
	mark.bench = self
	mark.process_mode = Node.PROCESS_MODE_ALWAYS
	mark.process_priority = LAST
	mark.process_physics_priority = LAST
	add_child(mark)

	RunConfig.start_new_run(DataRegistry.HEROES[0], false, 4242)
	_world = load(ScenePaths.WORLD).instantiate()
	add_child(_world)
	_world.net.measure_stream = true
	Events.level_up_offered.connect(func(peer_id: int, _cards: Array) -> void: _drain_offers.call_deferred(peer_id))
	_world.projectiles.child_entered_tree.connect(_count_spawn)
	while _world.find_player(1) == null:
		await get_tree().process_frame  # уровень генерируется в фоне
	_host = _world.find_player(1)
	_world.waves.active = false  # врагов держит стенд: ровно столько, сколько задано
	_arm(_host)
	for i in range(1, _players):
		var bot := _world.spawn_player(i + 1, DataRegistry.HEROES[i % DataRegistry.HEROES.size()])
		if bot != null:
			_arm(bot)
			_bots.append(bot)
	_measuring = true
	print("Стенд: врагов %d, героев %d, %.0f с (разогрев %.0f с), рендер %s, видеокарта: %s" % [
		_enemies, _players, _seconds, WARMUP, ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		RenderingServer.get_video_adapter_name()])


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			_enemies = maxi(int(arg.get_slice("=", 1)), 0)
		elif arg.begins_with("--players="):
			_players = clampi(int(arg.get_slice("=", 1)), 1, 4)
		elif arg.begins_with("--seconds="):
			_seconds = maxf(float(arg.get_slice("=", 1)), 1.0)
		elif arg == "--probe":
			_probe = true
		elif arg == "--heavy":
			_heavy = true
		elif arg.begins_with("--quality="):  # шаг 11.8: качество эффектов на этот прогон, без записи в настройки
			Settings.effects_quality = clampi(int(arg.get_slice("=", 1)), 0, Settings.QUALITY_KEYS.size() - 1)


## Герой стенда: неуязвим, без левел-апов, с пятью видами оружия 10-го уровня сверх стартового.
func _arm(player: Player) -> void:
	player.invulnerable = true
	player.level = BENCH_LEVEL
	for id in HEAVY_WEAPONS if _heavy else WEAPONS:
		var weapon := DataRegistry.upgrade(id)
		if weapon != null and player.get_upgrade_level(id) == 0:
			player.apply_upgrade(weapon, HEAVY_LEVEL if _heavy else WEAPON_LEVEL)
	if _heavy:
		player.apply_upgrade(DataRegistry.upgrade(&"volley"), 10)
		for skill_id: StringName in HEAVY_RUNES:
			for rune_id: StringName in HEAVY_RUNES[skill_id]:
				player.add_rune(skill_id, rune_id)


func _drain_offers(peer_id: int) -> void:
	var guard := 0
	while not _world.upgrades.current_offer(peer_id).is_empty() and guard < 50:
		_world.upgrades.apply_choice(peer_id, _world.upgrades.current_offer(peer_id)[0])
		guard += 1
	_world.get_node("LevelUpPanel").hide()
	_world.request_pause(&"level_up", false)


func _physics_process(_delta: float) -> void:
	_tick_begin = Time.get_ticks_usec()


func end_tick() -> void:
	if _measuring and not _finished and _clock >= WARMUP:
		_tick_ms.append((Time.get_ticks_usec() - _tick_begin) / 1000.0)


func _process(delta: float) -> void:
	_frame_begin = Time.get_ticks_usec()
	if not _measuring or _finished:
		return
	var pause_menu: PauseMenu = _world.get_node("PauseMenu")
	if pause_menu.visible:
		pause_menu.close()  # окно стенда потеряло фокус — меню паузы открылось само; мерить надо бой
	_clock += delta
	_move_bots()
	_refill_enemies()
	if _clock < WARMUP:
		return
	if _probe and not PerfProbe.enabled:
		PerfProbe.reset()
		PerfProbe.enabled = true
		_probe_from = _tick_ms.size()
	var viewport := get_viewport().get_viewport_rid()
	_frame_ms.append(delta * 1000.0)
	_render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport)
			+ RenderingServer.get_frame_setup_time_cpu())
	_render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	_draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_alive.append(_world.director.hostile_count())
	_max_nodes = maxi(_max_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_max_projectiles = maxi(_max_projectiles, _world.projectiles.get_child_count())
	_measured += delta
	if _measured >= _seconds:
		_finish()


func end_frame() -> void:
	if _measuring and not _finished and _clock >= WARMUP:
		_process_ms.append((Time.get_ticks_usec() - _frame_begin) / 1000.0)


## Боты ходят кругом вокруг героя хоста: враги тянутся к разным целям, оружие бьёт с разных сторон.
func _move_bots() -> void:
	for i in _bots.size():
		var bot := _bots[i]
		if is_instance_valid(bot):
			var angle := _clock * BOT_SPEED + TAU * i / _bots.size()
			bot.position = _host.position + Vector2.RIGHT.rotated(angle) * BOT_RADIUS


## Оценка посылки спавнера: данные spawn_function (var_to_bytes) — у снаряда и следа свои поля.
func _count_spawn(node: Node) -> void:
	if not _measuring or _finished or _clock < WARMUP:
		return
	if _stream_from < 0:
		_stream_from = _world.net.stream_bytes
	if node is Projectile:
		var p := node as Projectile
		_spawned_shots += 1
		_spawn_bytes += var_to_bytes({
			"type": p.kind, "pos": p.position, "dir": p.direction, "speed": p.speed, "range": p.max_distance,
			"damage": p.damage, "crit": p.crit, "pierce": p.pierce, "hostile": p.hostile, "owner": p.owner_peer,
			"color": p.color, "radius": p.blast_radius, "fuse": p.fuse, "explode": p.explode, "return": p.returns,
		}).size()
	elif node is CombatFx:
		_spawned_fx += 1
		var fx := node as CombatFx
		_spawn_bytes += var_to_bytes({"type": fx.kind, "pos": fx.position, "radius": fx.radius, "color": fx.color,
			"dir": fx.direction, "points": fx.points}).size()


func _refill_enemies() -> void:
	var missing := _enemies - _world.director.hostile_count()
	for i in mini(missing, SPAWN_PER_FRAME):
		_world.waves.spawn_enemy(_world.waves.pick_current_enemy())


func _finish() -> void:
	_finished = true
	var frames := _sorted(_frame_ms)
	var ticks := _sorted(_tick_ms)
	var at_60 := _mean(_tick_ms) + _mean(_process_ms) + _mean(_render_cpu_ms)
	var worst_60 := _percentile(ticks, 0.99) + _percentile(_sorted(_process_ms), 0.99) + _mean(_render_cpu_ms)
	var result := {
		"time": Time.get_datetime_string_from_system(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"headless": DisplayServer.get_name() == "headless",
		"enemies": _enemies,
		"players": _players,
		"quality": Settings.effects_quality,
		"seconds": snappedf(_measured, 0.1),
		"frame_at_60_ms": snappedf(at_60, 0.01),
		"frame_at_60_p99_ms": snappedf(worst_60, 0.01),
		"tick_ms_avg": snappedf(_mean(_tick_ms), 0.01),
		"tick_ms_p99": snappedf(_percentile(ticks, 0.99), 0.01),
		"process_ms_avg": snappedf(_mean(_process_ms), 0.01),
		"render_cpu_ms_avg": snappedf(_mean(_render_cpu_ms), 0.01),
		"render_gpu_ms_avg": snappedf(_mean(_render_gpu_ms), 0.01),
		"frames": frames.size(),
		"frame_ms_avg": snappedf(_mean(_frame_ms), 0.01),
		"frame_ms_p99": snappedf(_percentile(frames, 0.99), 0.01),
		"fps_avg": snappedf(1000.0 / maxf(_mean(_frame_ms), 0.001), 0.1),
		"draw_calls_avg": snappedf(_mean(_draw_calls), 0.1),
		"alive_avg": snappedf(_mean(_alive), 0.1),
		"nodes_max": _max_nodes,
		"projectiles_max": _max_projectiles,
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
	}
	print("Кадр при 60 FPS ≈ %.2f мс из 16.7, в худшем (p99) %.2f мс" % [at_60, worst_60])
	print("  тик логики %.2f мс (p99 %.2f); процесс %.2f мс; отрисовка CPU %.2f, GPU %.2f мс" % [
		result["tick_ms_avg"], result["tick_ms_p99"], result["process_ms_avg"],
		result["render_cpu_ms_avg"], result["render_gpu_ms_avg"]])
	print("  без предела FPS: %.0f FPS, p99 кадра %.2f мс; вызовов отрисовки %.0f; живых врагов %.0f; узлов до %d; снарядов до %d" % [
		result["fps_avg"], result["frame_ms_p99"], result["draw_calls_avg"], result["alive_avg"], _max_nodes, _max_projectiles])
	print("  видеопамять: текстуры %.0f МБ, всего %.0f МБ" % [result["texture_mem_mb"], result["video_mem_mb"]])
	var per_second := maxf(_measured, 0.1)
	result["shots_per_s"] = snappedf(_spawned_shots / per_second, 0.1)
	result["fx_per_s"] = snappedf(_spawned_fx / per_second, 0.1)
	result["spawn_kb_per_s"] = snappedf(_spawn_bytes / per_second / 1024.0, 0.1)
	result["stream_kb_per_s"] = snappedf((_world.net.stream_bytes - maxi(_stream_from, 0)) / per_second / 1024.0, 0.01)
	print("  создано в World/Projectiles: снарядов %.0f/с, следов %.0f/с — пачками %.2f КБ/с на клиента (спавнером было бы ≈ %.1f КБ/с данных)" % [
		result["shots_per_s"], result["fx_per_s"], result["stream_kb_per_s"], result["spawn_kb_per_s"]])
	if _probe:
		PerfProbe.enabled = false
		var ticks_probed := maxi(_tick_ms.size() - _probe_from, 1)
		var sections := {}
		var parts := PackedStringArray()
		var names: Array = PerfProbe.totals.keys()
		names.sort()
		for section: StringName in names:
			var per_tick: float = PerfProbe.totals[section] / 1000.0 / ticks_probed
			sections[section] = snappedf(per_tick, 0.001)
			parts.append("%s %.2f (%d вызовов)" % [section, per_tick, PerfProbe.calls[section] / ticks_probed])
		result["probe_ms"] = sections
		print("  разбивка тика, мс: " + "; ".join(parts))
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify(result))
		print("Записано в %s" % ProjectSettings.globalize_path(LOG_PATH))
	get_tree().quit(0)


static func _sorted(values: PackedFloat32Array) -> PackedFloat32Array:
	var copy := values.duplicate()
	copy.sort()
	return copy


static func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


static func _percentile(sorted: PackedFloat32Array, share: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(ceili(share * sorted.size()) - 1, 0, sorted.size() - 1)]
