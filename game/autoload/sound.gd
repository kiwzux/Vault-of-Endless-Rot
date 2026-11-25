extends Node
## Звук (шаг 11.13): эмбиент по месту и звуки интерфейса, у каждого участника свой — в сеть ничего не уходит.
## Музыка выбирается сама раз в MUSIC_CHECK секунд: меню и лобби — menu_music, Убежище — hub_music, уровень —
## BiomeData.music его биома, а пока среди врагов есть живой босс — boss_music (видно у хоста и у клиентов,
## сигнал хоста не нужен). Смена трека — плавный переход двумя плеерами. Звуки интерфейса: наведение и нажатие
## любой кнопки (подключаются сами, когда кнопка появляется в дереве), левел-ап своего героя, выбор карты
## (play_ui(&"magic")), надеть предмет (play_ui(&"equip")). Данные — data/audio/audio.tres (AudioConfig).
## Боевые слои (шаг 11.28): каждые MOOD_STEP секунд считается напряжённость вокруг своего героя (враги рядом,
## элита весомее, свежая рана) — у каждого участника своя, по тому, что он видит. Разгорелся бой — эмбиент биома
## плавно сменяет его боевой трек (BiomeData.battle_music), бой утих и прошло battle_hold — снова эмбиент
## (пороги с запасом — музыка не дёргается). В затишье эмбиент глуше и тише (срез и усиление на шине Music),
## с напряжённостью раскрывается; вне уровня, в бою и с боссом шина без изменений.

## Конфиг грузится при старте, а не preload: на свежей копии проекта звуки ещё не импортированы, и preload
## сорвал бы запуск (и сам импорт --import). Нет конфига — тишина.
const CONFIG_PATH := "res://data/audio/audio.tres"
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const MUSIC_CHECK := 1.0
const SILENT_DB := -40.0
const MOOD_STEP := 0.25
## Срез «открытой» шины, Гц: выше слышимого.
const OPEN_CUTOFF := 20000.0
## С какой скоростью шина глохнет и раскрывается, доли в секунду: без скачков при смене трека.
const MOOD_RATE := 0.6

var _music: Array[AudioStreamPlayer] = []
var _active := 0
var _current: AudioStream
var _fade: Tween
var _check_left := 0.0
var _ui_players := {}
var _last_hover := -1.0
var _config: AudioConfig
## Боевые слои: напряжённость 0…1, идёт ли бой, сколько секунд подряд тихо, жив ли босс (с последней проверки).
var _intensity := 0.0
var _battle := false
var _calm_for := 0.0
var _boss := false
var _mood := 1.0
var _mood_left := 0.0
var _watched: Player
var _health_seen := 0.0
var _hurt_at := -1000.0
var _music_bus := -1
var _lowpass: AudioEffectLowPassFilter
var _amplify: AudioEffectAmplify


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # музыка и щелчки меню звучат и на паузе
	if ResourceLoader.exists(CONFIG_PATH):
		_config = load(CONFIG_PATH) as AudioConfig
	if _config == null:
		set_process(false)
		return
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		player.volume_db = SILENT_DB
		add_child(player)
		_music.append(player)
	get_tree().node_added.connect(_on_node_added)
	Events.level_up_offered.connect(_on_level_up_offered)
	_music_bus = AudioServer.get_bus_index(MUSIC_BUS)
	if _music_bus >= 0:  # срез и усиление затишья — последними на шине музыки, пока выключены
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = OPEN_CUTOFF
		AudioServer.add_bus_effect(_music_bus, _lowpass)
		_amplify = AudioEffectAmplify.new()
		AudioServer.add_bus_effect(_music_bus, _amplify)
		_apply_mood()


## Выход: отпустить треки и звуки, иначе Godot сообщает о ресурсах, оставшихся в памяти при закрытии.
func _exit_tree() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if _lowpass != null:
		for i in range(AudioServer.get_bus_effect_count(_music_bus) - 1, -1, -1):
			var effect := AudioServer.get_bus_effect(_music_bus, i)
			if effect == _lowpass or effect == _amplify:
				AudioServer.remove_bus_effect(_music_bus, i)
		_lowpass = null
		_amplify = null
	for player: AudioStreamPlayer in _music + Array(_ui_players.values(), TYPE_OBJECT, &"AudioStreamPlayer", null):
		player.stop()
		player.stream = null
	_current = null
	_config = null


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	_mood_left -= delta
	if _mood_left <= 0.0:
		var step := MOOD_STEP - _mood_left
		_mood_left = MOOD_STEP
		_update_mood(scene, step)
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = MUSIC_CHECK
		var next := music_for(scene)
		# Эмбиент ↔ боевой трек того же биома — быстрый переход, всё остальное — обычный.
		var biome := current_biome() if scene is World else null
		var layers := [biome.music, biome.battle_music] if biome != null else []
		play_music(next, _config.battle_crossfade if layers.has(next) and layers.has(_current) else -1.0)


## Трек для сцены: меню, Убежище или уровень (биом; в бою — боевой трек биома; пока жив босс — трек босса).
func music_for(scene: Node) -> AudioStream:
	if _config == null:
		return null
	if scene is World:
		_boss = _boss_alive(scene)
		if _boss:
			return _config.boss_music
		var biome := current_biome()
		if biome != null and _battle and biome.battle_music != null:
			return biome.battle_music
		return biome.music if biome != null and biome.music != null else _config.menu_music
	if scene is Sanctuary:
		return _config.hub_music
	return _config.menu_music


## Идёт ли бой (боевой трек биома вместо эмбиента).
func in_battle() -> bool:
	return _battle


## Напряжённость вокруг своего героя, 0…1: враги ближе battle_radius (элита и босс — по elite_weight)
## на battle_full, плюс hurt_boost, пока рана свежее hurt_memory. Нет героя или он пал — 0.
func battle_target(world: World) -> float:
	if _config == null or world == null:
		return 0.0
	var me := world.local_player()
	if me == null or not me.alive:
		return 0.0
	var now := Time.get_ticks_msec() / 1000.0
	if me != _watched:
		_watched = me
		_health_seen = me.health
	if me.health < _health_seen - 0.5:
		_hurt_at = now
	_health_seen = me.health
	var reach := _config.battle_radius * _config.battle_radius
	var weight := 0.0
	for node in world.enemies.get_children():
		var enemy := node as Enemy
		if enemy == null or enemy.dead or enemy.ally or enemy.data == null:
			continue
		if enemy.global_position.distance_squared_to(me.global_position) <= reach:
			weight += _config.elite_weight if enemy.data.is_boss or enemy.is_elite() else 1.0
	var target := weight / maxf(_config.battle_full, 1.0)
	if now - _hurt_at < _config.hurt_memory:
		target += _config.hurt_boost
	return clampf(target, 0.0, 1.0)


## Шаг напряжённости к target за delta секунд и переключение боя с запасом между порогами (проверки зовут сами).
func step_battle(target: float, delta: float) -> void:
	if _config == null:
		return
	var rate := _config.rise_rate if target > _intensity else _config.fall_rate
	_intensity = move_toward(_intensity, target, rate * delta)
	if not _battle:
		if _intensity >= _config.battle_on:
			_battle = true
			_calm_for = 0.0
		return
	_calm_for = _calm_for + delta if _intensity <= _config.battle_off else 0.0
	if _calm_for >= _config.battle_hold:
		_battle = false


func _update_mood(scene: Node, delta: float) -> void:
	if scene is World:
		step_battle(battle_target(scene), delta)
	else:
		_intensity = 0.0
		_battle = false
		_calm_for = 0.0
		_watched = null
	var target := _intensity if scene is World and not _battle and not _boss else 1.0
	_mood = move_toward(_mood, target, MOOD_RATE * delta)
	_apply_mood()


## Затишье на шине музыки: mood 1 — шина как есть (эффекты выключены), 0 — срез calm_cutoff_hz и calm_volume_db.
func _apply_mood() -> void:
	if _lowpass == null or _config == null:
		return
	var muffled := _mood < 0.999
	for i in AudioServer.get_bus_effect_count(_music_bus):
		var effect := AudioServer.get_bus_effect(_music_bus, i)
		if effect == _lowpass or effect == _amplify:
			AudioServer.set_bus_effect_enabled(_music_bus, i, muffled)
	_lowpass.cutoff_hz = _config.calm_cutoff_hz * pow(OPEN_CUTOFF / _config.calm_cutoff_hz, _mood)
	_amplify.volume_db = lerpf(_config.calm_volume_db, 0.0, _mood)


func _boss_alive(world: World) -> bool:
	for node in world.enemies.get_children():
		var enemy := node as Enemy
		if enemy != null and not enemy.dead and enemy.data != null and enemy.data.is_boss:
			return true
	return false


func current_biome() -> BiomeData:
	var level := GameState.current_level
	if level == null:
		return null
	var names := Palette.biomes()
	return DataRegistry.biome(StringName(names[level.biome])) if level.biome >= 0 and level.biome < names.size() else null


## Сменить трек с плавным переходом за fade секунд (меньше 0 — AudioConfig.crossfade; тот же трек — ничего
## не делает). null — тишина.
func play_music(stream: AudioStream, fade := -1.0) -> void:
	if stream == _current or _music.is_empty():
		return
	_current = stream
	if DisplayServer.get_name() == "headless":
		return  # проверки без окна: трек выбирается, но не играет — иначе плеер держит поток до выхода
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var old := _music[_active]
	_active = 1 - _active
	var next := _music[_active]
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var time := fade if fade >= 0.0 else _config.crossfade
	# Старый затихает, пока новый нарастает (одновременно — без провала тишины посередине).
	_fade = create_tween().set_parallel()
	_fade.tween_property(old, ^"volume_db", SILENT_DB, time)
	if stream != null:
		next.stream = stream
		next.volume_db = SILENT_DB
		next.play()
		_fade.tween_property(next, ^"volume_db", _config.music_db, time)
	_fade.chain().tween_callback(old.stop)


## Текущий трек (для проверок).
func current_music() -> AudioStream:
	return _current


## Звук интерфейса по имени (AudioConfig.ui): hover, confirm, equip, level_up, magic.
func play_ui(sound: StringName) -> void:
	var stream := _config.ui(sound) if _config != null else null
	if stream == null:
		return
	if DisplayServer.get_name() == "headless":
		return
	var player: AudioStreamPlayer = _ui_players.get(sound)
	if player == null:
		player = AudioStreamPlayer.new()
		player.bus = SFX_BUS
		player.stream = stream
		player.volume_db = _config.ui_db
		player.max_polyphony = 3
		add_child(player)
		_ui_players[sound] = player
	player.play()


func _hover() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hover < _config.hover_cooldown:
		return
	_last_hover = now
	play_ui(&"hover")


## Кнопки получают звук сами: наведение мышью и нажатие. Переключатели и списки — тоже кнопки (BaseButton).
func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null:
		return
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			_hover())
	button.pressed.connect(play_ui.bind(&"confirm"))


func _on_level_up_offered(peer_id: int, _cards: Array) -> void:
	if peer_id == multiplayer.get_unique_id():
		play_ui(&"level_up")
