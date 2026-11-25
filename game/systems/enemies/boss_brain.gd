class_name BossBrain
extends RefCounted
## Хост: приёмы босса по фазам (шаг 12). Босс по очереди применяет приёмы из EnemyData.attacks: случайно
## по весу, без повтора подряд, только доступные в его фазе и на этой дистанции. Приём — замах с телеграфом,
## удар, передышка (в поздних фазах короче: EnemyData.phase_tempo).
##
## Фазы — пороги здоровья EnemyData.phase_thresholds (Enemy следит за ними у всех участников). Новая фаза:
## текущий приём обрывается, босс замирает на STAGGER с (вспышка), затем — приём, открытый этой фазой.
## Случайность — от сида забега, уровня и босса: бой воспроизводим по коду забега.

## Первый приём — не сразу: дать герою увидеть босса.
const FIRST_DELAY := 1.5
const STAGGER := 1.2
## Подходящего приёма нет (все дальше max_range) — новая проверка через столько секунд, босс идёт к цели.
const RETRY_DELAY := 0.3

var boss: Enemy
var phase := 0
var rng := RandomNumberGenerator.new()

var _attack: BossAttack
var _cast: BossCast
var _windup_left := 0.0
var _striking := false
var _cooldown := FIRST_DELAY
var _last: BossAttack
var _stagger := 0.0
## Фаза, чей приём выбрать следующим (после смены фазы); < 0 — любой.
var _prefer_phase := -1


func _init(p_boss: Enemy) -> void:
	boss = p_boss
	rng.seed = hash([RunConfig.run_seed, GameState.level_index, String(p_boss.data_id), "boss"])


## Тик приёмов. true — босс сейчас стоит или ведёт себя сам (замах, удар, рывок, смена фазы): шаг
## steering не нужен; moving() — двигался ли он сам в этом тике.
func tick(target: Player, delta: float) -> bool:
	if _stagger > 0.0:
		_stagger -= delta
		return true
	if _attack != null:
		return _tick_attack(delta)
	_cooldown -= delta
	if _cooldown > 0.0 or target == null:
		return false
	_start(target)
	return _attack != null and _attack.root


func moving() -> bool:
	return _cast != null and _cast.moving


## Идёт ли приём и какой (для проверок и отладки).
func current() -> BossAttack:
	return _attack


func is_winding_up() -> bool:
	return _attack != null and not _striking


## Enemy: здоровье перешло порог — новая фаза.
func on_phase(new_phase: int) -> void:
	phase = new_phase
	_attack = null
	_cast = null
	_striking = false
	_stagger = STAGGER
	_cooldown = 0.0
	_prefer_phase = new_phase


func _start(target: Player) -> void:
	var dist := boss.global_position.distance_to(target.global_position)
	var options: Array[BossAttack] = []
	for attack in boss.data.attacks:
		if attack != null and attack.min_phase <= phase and (attack.max_range <= 0.0 or dist <= attack.max_range):
			options.append(attack)
	if options.size() > 1:
		options.erase(_last)
	if _prefer_phase >= 0:
		var fresh := options.filter(func(a: BossAttack) -> bool: return a.min_phase == _prefer_phase)
		_prefer_phase = -1
		if not fresh.is_empty():
			options.assign(fresh)
	if options.is_empty():
		_cooldown = RETRY_DELAY
		return
	var weights := PackedFloat32Array()
	for attack in options:
		weights.append(maxf(attack.weight, 0.01))
	_attack = options[rng.rand_weighted(weights)]
	_cast = BossCast.new(boss, World.of(boss), target, phase, rng)
	_striking = false
	_windup_left = _attack.windup
	_attack.telegraph(_cast)


func _tick_attack(delta: float) -> bool:
	var attack := _attack
	if not _striking:
		_windup_left -= delta
		if _windup_left > 0.0:
			return attack.root
		_striking = true
		attack.strike(_cast)
		if _attack == null:
			return true  # удар перевёл босса в новую фазу
	_cast.time += delta
	_cast.moving = false
	if attack.tick(_cast, delta):
		return attack.root or _cast.moving
	_last = attack
	_attack = null
	_cast = null
	_striking = false
	_cooldown = attack.recovery * pow(boss.data.phase_tempo, phase)
	return false
