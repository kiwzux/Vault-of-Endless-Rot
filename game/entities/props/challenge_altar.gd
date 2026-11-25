class_name ChallengeAltar
extends MapObject
## Испытание (CR-16) — святилище в духе Diablo: герой сам вызывает бой клавишей E ради награды.
##  - Алтарь испытания (trial_altar): минута натиска — сверх волн лезут враги крепче обычного,
##    элиты втрое чаще (WaveSpawner.start_surge). Отряд продержался — награда.
##  - Проклятый тотем (cursed_totem): стая из TOTEM_PACK чемпионов с двумя аффиксами; перебить всех
##    за TOTEM_DURATION секунд — награда, не успели — тотем рассыпается ни с чем.
## Награда (LootSystem.challenge_reward): редкий предмет, золото, опыт. Испытание идёт и во время босса.
## Где стоят: на метке STATUE вместо статуи и у метки ENEMY_SPAWN — решает LevelFlow (ОГР-02).

const TRIAL := &"trial_altar"
const CURSED := &"cursed_totem"
const STATUE := &"statue"
const TRIAL_DURATION := 60.0
const TOTEM_DURATION := 45.0
const TOTEM_PACK := 3
const TOTEM_AFFIXES := 2
const TOTEM_RING := 40.0
const NAME_KEYS := {
	&"trial_altar": "CHALLENGE_TRIAL", &"cursed_totem": "CHALLENGE_CURSED", &"statue": "CHALLENGE_STATUE",
}
const START_KEYS := {
	&"trial_altar": "BANNER_TRIAL_STARTED", &"cursed_totem": "BANNER_CURSED_STARTED", &"statue": "BANNER_STATUE",
}
const RUNE := Color(0.85, 0.15, 0.1)
const CURSE_FLAME := Color(0.65, 0.3, 0.95)

@export var kind: StringName = TRIAL
## Секунд до конца испытания (хост → все, для кольца над алтарём).
@export var time_left := 0.0
@export var active := false:
	set(value):
		active = value
		refresh_art()

var _duration := 1.0
var _pack: Array[Enemy] = []
var _time := 0.0


static func name_key(p_kind: StringName) -> String:
	return NAME_KEYS.get(p_kind, "CHALLENGE_TRIAL")


static func banner_key(p_kind: StringName, _started: bool) -> String:
	return START_KEYS.get(p_kind, "BANNER_TRIAL_STARTED")


static func result_key(_kind: StringName, success: bool) -> String:
	return "BANNER_CHALLENGE_WON" if success else "BANNER_CHALLENGE_FAILED"


func _init() -> void:
	requires_key = true


func _ready() -> void:
	super()
	interact_radius = 28.0
	_duration = TOTEM_DURATION if kind == CURSED else TRIAL_DURATION  # клиенту — для кольца времени
	set_physics_process(multiplayer.is_server())


func activate(_player: Player) -> bool:
	used = true
	active = true
	if kind == CURSED:
		_duration = TOTEM_DURATION
		_summon_pack()
	else:
		_duration = TRIAL_DURATION
		_world.waves.start_surge(TRIAL_DURATION)
	time_left = _duration
	Events.challenge_started.emit(kind, _duration)
	return true


func _physics_process(delta: float) -> void:
	if not active:
		return
	time_left = maxf(time_left - delta, 0.0)
	if kind == CURSED:
		if _pack_alive() == 0:
			_finish(true)
		elif time_left <= 0.0:
			_finish(false)
	elif time_left <= 0.0:
		_finish(not _world.director.players_alive().is_empty())


func _summon_pack() -> void:
	var waves := _world.waves
	for i in TOTEM_PACK:
		var offset := Vector2.RIGHT.rotated(TAU * i / TOTEM_PACK) * TOTEM_RING
		var pos := global_position + offset if not _world.is_blocked(global_position + offset) else global_position
		var enemy := waves.spawn_enemy(waves.pick_current_enemy(), pos, waves.elite_affixes(TOTEM_AFFIXES), waves.wave_stage())
		if enemy != null:
			_pack.append(enemy)


func _pack_alive() -> int:
	var n := 0
	for enemy in _pack:
		if is_instance_valid(enemy) and not enemy.dead:
			n += 1
	return n


func _finish(success: bool) -> void:
	active = false
	time_left = 0.0
	if kind == TRIAL:
		_world.waves.stop_surge()
	if success:
		_world.loot.challenge_reward(global_position + Vector2(0, 12))
	Events.challenge_finished.emit(kind, success)


func prompt_text(_player: Player, near: bool) -> String:
	var title := tr(name_key(kind))
	return tr("CHALLENGE_PROMPT").format({"name": title}) if near else title


func prompt_color(_player: Player) -> Color:
	return Color(0.95, 0.45, 0.35)


func _process(delta: float) -> void:
	super(delta)
	_time += delta
	queue_redraw()


## Шаг 11.20: горит, пока не тронут или пока идёт испытание; после — потухший.
func art_id() -> StringName:
	var lit := not used or active
	if kind == CURSED:
		return &"cursed_totem" if lit else &"cursed_totem_used"
	return &"trial_altar" if lit else &"trial_altar_used"


func _draw() -> void:
	if _art == null:
		if kind == CURSED:
			_draw_totem()
		else:
			_draw_altar()
	if active and _duration > 0.0:  # кольцо времени — над спрайтом (он рисуется поверх узла)
		var center := Vector2(0, -(_art.height() + 10.0)) if _art != null else Vector2(0, -6)
		var radius := 8.0 if _art != null else 16.0
		draw_arc(center, radius, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 3.0)
		draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * time_left / _duration, 32, RUNE, 2.0)


func _draw_altar() -> void:
	var stone := Color(0.32, 0.29, 0.28) if not used or active else Color(0.22, 0.2, 0.2)
	draw_rect(Rect2(-12, -4, 24, 9), stone.darkened(0.2))
	draw_rect(Rect2(-9, -10, 18, 7), stone)
	var glow := 0.5 + 0.5 * sin(_time * 4.0) if not used or active else 0.0
	for i in 3:
		draw_rect(Rect2(-7 + i * 6, -8, 2, 3), Color(RUNE, 0.4 + 0.6 * glow))
	if active:
		draw_circle(Vector2(0, -14), 3.0 + glow, Color(1.0, 0.5, 0.2, 0.8))


func _draw_totem() -> void:
	var wood := Color(0.25, 0.18, 0.14) if not used or active else Color(0.15, 0.12, 0.1)
	draw_rect(Rect2(-2, -22, 4, 26), wood)
	draw_circle(Vector2(0, -24), 4.5, Color(0.85, 0.82, 0.72) if not used or active else Color(0.45, 0.42, 0.38))
	draw_rect(Rect2(-2, -25, 1.5, 1.5), Color.BLACK)
	draw_rect(Rect2(0.5, -25, 1.5, 1.5), Color.BLACK)
	if not used or active:
		var flick := 0.6 + 0.4 * sin(_time * 6.0)
		draw_circle(Vector2(0, -31), 2.5 + flick, Color(CURSE_FLAME, 0.75))
