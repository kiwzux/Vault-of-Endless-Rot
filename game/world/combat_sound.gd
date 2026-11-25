class_name CombatSound
extends Node2D
## Звуки боя (шаг 11.27; техзадание, раздел 9): взмах и заклинание по стихии навыка, попадание и удачный удар,
## взрыв, удар с неба, телеграф босса, выстрел врага, смерть врага (элиты, босса), рана и гибель своего героя,
## подбор опыта и золота, появление босса. Звуки синтезированы кодом (art/gen_sfx.py), каталог —
## data/audio/sfx/*.tres (SfxData): событие ищет звук по id, новый звук — WAV и .tres.
## Как Juice — у каждого участника свои и выводятся из того, что он и так видит: события Events (удары у клиентов
## приходят пачкой от хоста), узлы снарядов и следов (ProjectileFactory), уход узла врага, синхронизированные
## alive, xp и gold своего героя. По сети ничего не уходит.
## Пул: VOICES проигрывателей в мире (панорама и затухание до камеры своего героя) и SCREEN_VOICES «у себя».
## У звука — предел одновременных и перерыв (SfxData): сотни попаданий в секунду дают несколько звуков;
## дальше max_distance от своего героя звук не звучит вовсе. Громкость — ползунок «Звуки» (шина SFX).
## Без окна (проверки) не играет ничего, но счёт сыгранного (played) идёт.

const DIR := "res://data/audio/sfx/"
const BUS := &"SFX"
const VOICES := 20
const SCREEN_VOICES := 6
## Затухание с расстоянием (AudioStreamPlayer2D.attenuation): чуть круче линейного.
const ATTENUATION := 1.6
## Звуки, которые зовёт код (проверка: у каждого есть данные).
const EVENTS: Array[StringName] = [&"swing", &"cast_physical", &"cast_fire", &"cast_cold", &"cast_lightning",
	&"cast_poison", &"cast_blood", &"cast_dark", &"cast_holy", &"hit", &"hit_crit", &"explode", &"thunder", &"smite",
	&"warn", &"enemy_shot", &"death", &"death_big", &"boss_death", &"boss_roar", &"hero_hurt", &"hero_death",
	&"pickup_gem", &"pickup_gold"]

static var _catalog := {}
static var _loaded := false

## id → сколько раз прозвучал (проверки и стенд).
var played := {}

var _world: World
var _silent := false
var _voices: Array[AudioStreamPlayer2D] = []
var _voice_ids: Array[StringName] = []
var _screen: Array[AudioStreamPlayer] = []
var _screen_ids: Array[StringName] = []
var _last := {}
## Свой герой и то, что о нём уже известно: звук подбора — по росту опыта и золота, гибели — по alive.
var _watched: Player
var _xp := 0
var _level_seen := 0
var _gold := 0
var _alive := true


func _ready() -> void:
	_world = World.of(self)
	_silent = DisplayServer.get_name() == "headless"
	load_catalog()
	if not _silent:
		for i in VOICES:
			var voice := AudioStreamPlayer2D.new()
			voice.bus = BUS
			voice.attenuation = ATTENUATION
			add_child(voice)
			_voices.append(voice)
			_voice_ids.append(&"")
		for i in SCREEN_VOICES:
			var voice := AudioStreamPlayer.new()
			voice.bus = BUS
			add_child(voice)
			_screen.append(voice)
			_screen_ids.append(&"")
	Events.damage_dealt.connect(_on_damage_dealt)
	Events.boss_spawned.connect(func(_boss: Node) -> void: play(&"boss_roar"))


## Каталог звуков — при первом мире, а не preload: на свежей копии проекта WAV ещё не импортированы (как AudioConfig).
static func load_catalog() -> void:
	if _loaded:
		return
	_loaded = true
	for file in ResourceLoader.list_directory(DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var data := load(DIR + file) as SfxData
		if data != null and not data.streams.is_empty() and not data.streams.has(null):
			_catalog[data.id] = data


static func sound(id: StringName) -> SfxData:
	load_catalog()
	return _catalog.get(id)


## Сыграть звук id в точке мира at (Vector2.INF — «у себя»). false — не прозвучал: нет звука, перерыв,
## предел одновременных или слишком далеко от своего героя.
func play(id: StringName, at := Vector2.INF) -> bool:
	var data: SfxData = _catalog.get(id)
	if data == null:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(id, -1000.0)) < data.cooldown:
		return false
	var in_world := data.positional and at != Vector2.INF
	if in_world and not _near(at, data.max_distance):
		return false
	if _sounding(id, in_world) >= data.max_voices:
		return false
	_last[id] = now
	played[id] = int(played.get(id, 0)) + 1
	if _silent:
		return true
	var stream: AudioStream = data.streams[randi() % data.streams.size()]
	var pitch := 1.0 + randf_range(-data.pitch_jitter, data.pitch_jitter)
	if in_world:
		var i := _free_voice(_voices)
		var voice := _voices[i]
		voice.stop()
		voice.stream = stream
		voice.volume_db = data.volume_db
		voice.pitch_scale = pitch
		voice.max_distance = data.max_distance
		voice.global_position = at
		voice.play()
		_voice_ids[i] = id
	else:
		var i := _free_voice(_screen)
		var voice := _screen[i]
		voice.stop()
		voice.stream = stream
		voice.volume_db = data.volume_db
		voice.pitch_scale = pitch
		voice.play()
		_screen_ids[i] = id
	return true


## Тишина и без перерывов: следующий звук любого id прозвучит сразу (проверки: перерыв и длина звука идут
## в реальном времени, а проверки с --fixed-fps бегут быстрее него).
func forget_cooldowns() -> void:
	_last.clear()
	for voice in _voices:
		voice.stop()
	for voice in _screen:
		voice.stop()


## Удар навыка героя (ProjectileFactory): взмах — свистом клинка, остальное — звуком стихии навыка.
func cast(element: StringName, kind: StringName, at: Vector2) -> void:
	if kind == &"slash":
		play(&"swing", at)
		return
	var id := StringName("cast_%s" % element)
	play(id if _catalog.has(id) else &"cast_physical", at)


## Удар с неба бьёт в цель: молния — громом, остальное — тяжёлым ударом со звоном.
func strike(element: StringName, at: Vector2) -> void:
	play(&"thunder" if element == &"lightning" else &"smite", at)


## Узел врага ушёл (Enemy._exit_tree, как Juice.enemy_gone): обычный — хруст, элита и мини-босс — рык, босс — взрыв.
func enemy_gone(enemy: Enemy, killed: bool) -> void:
	if not killed or enemy.data == null or enemy.ally or not is_inside_tree():
		return
	if enemy.data.is_boss:
		play(&"boss_death")
	elif enemy.is_elite() or enemy.data.loot_rarity >= 0:
		play(&"death_big", enemy.global_position)
	else:
		play(&"death", enemy.global_position)


func _on_damage_dealt(pos: Vector2, amount: float, crit: bool) -> void:
	if amount > 0.0:
		play(&"hit_crit" if crit else &"hit", pos)


func _process(_delta: float) -> void:
	var me := _world.local_player() if _world != null else null
	if me != _watched:  # новый герой (начало уровня, подключение): прежний опыт — не подбор
		_watched = me
		if me != null:
			_xp = me.xp
			_level_seen = me.level
			_gold = me.gold
			_alive = me.alive
		return
	if me == null:
		return
	if me.xp > _xp or me.level > _level_seen:  # левел-ап сбрасывает остаток опыта — это тоже подбор
		play(&"pickup_gem")
	_level_seen = me.level
	if me.gold > _gold:
		play(&"pickup_gold")
	if _alive and not me.alive:
		play(&"hero_death")
	_xp = me.xp
	_gold = me.gold
	_alive = me.alive


## Свой герой ближе distance к точке at (нет героя — слышно везде).
func _near(at: Vector2, distance: float) -> bool:
	var me := _world.local_player() if _world != null else null
	return me == null or me.global_position.distance_squared_to(at) <= distance * distance


## Сколько звуков id звучит сейчас (в мире или «у себя»). Без окна — 0: проигрывателей нет.
func _sounding(id: StringName, in_world: bool) -> int:
	var count := 0
	if in_world:
		for i in _voices.size():
			if _voice_ids[i] == id and _voices[i].playing:
				count += 1
	else:
		for i in _screen.size():
			if _screen_ids[i] == id and _screen[i].playing:
				count += 1
	return count


## Свободный проигрыватель; все заняты — тот, что звучит дольше всех (его хвост уже тихий).
func _free_voice(pool: Array) -> int:
	var oldest := 0
	var oldest_at := -1.0
	for i in pool.size():
		if not pool[i].playing:
			return i
		var at: float = pool[i].get_playback_position()
		if at > oldest_at:
			oldest_at = at
			oldest = i
	return oldest
