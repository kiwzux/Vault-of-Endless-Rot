class_name Enemy
extends Node2D
## Враг, босс или скелет-союзник Некроманта. Логика (steering, урон, смерть, дроп) работает только
## на хосте; клиенты получают позицию через MultiplayerSynchronizer (game/net, ФТ-14). Создаётся
## фабрикой create(data) — её же game/net назначит в spawn_function спавнера контейнера World/Enemies.
##
## Steering: желаемое направление = поле потока к ближайшему игроку (обход стен) или прямо на него
## вблизи + расталкивание соседей; скорость сглаживается, стены — по логической сетке клеток
## (EnemyDirector.slide). Физического тела у врага нет (шаг 5): с врагами ничего не сталкивается,
## а 300 тел в пространстве физики стоили времени и хосту, и клиентам.
##
## Тики ИИ (шаг 5): ближайший герой и расталкивание пересчитываются раз в THINK_EVERY тиков (у каждого
## врага свой сдвиг, нагрузка ровная); движение, удары и приёмы — каждый тик.
##
## Особые враги (поля EnemyData, раздел Special): рывок с замахом, самоподрыв вплотную, деление при
## смерти, лечение раненых соседей, телепорт ближе к герою, веер выстрелов и навесной огонь.
##
## Полоска здоровья над головой: у раненого врага, у элит, мини-босса и боссов — всегда.
## Для неё game/net синхронизирует health хост → все (max_health клиент считает сам из данных).
##
## Урон (шаг 2): take_hit(HitInfo) — Губитель великанов, сопротивления стихиям (EnemyData.resistances),
## уязвимость от порчи, Вампиризм, Казнь, затем статусы удара (StatusSystem). Статусы меняют врага через
## set_status_effects: замедление, оглушение (стоит и не бьёт), страх (бежит от героев), уязвимость.
## Клиенты видят статусы оттенком — флаги из снимка врага (set_status_flags).
##
## Телеграфы (шаг 6): опасный приём сначала показывает область удара на земле (Projectile «warn» или круг
## взрыва) — рывок полосой (направление больше не меняется во время замаха), кольцо босса кругом, самоподрыв
## кругом взрыва. Аффиксы-поведения элит (EliteAffixData): огненный след, морозная вспышка, телепорт к герою,
## призыв подручных — у каждого свой телеграф. Всё это узлы World/Projectiles: клиенты видят их без новой синхронизации.
## Те же поведения бывают врождёнными у вида (EnemyData.innate_affixes) — тогда враг не элита.
##
## Боссы (шаг 12): приёмы из данных (EnemyData.attacks — кольцо, спираль, веер, дождь взрывов, рывки, волна,
## призыв, лужи, крест) по фазам здоровья — BossBrain. Фаза считается из здоровья у всех участников: облик
## ярости и баннер HUD клиенты видят без новой синхронизации.
##
## Облик (шаг 11.2): спрайт из общего атласа врагов (EnemyArt), тень, аура элиты и полоски здоровья — из того же
## атласа, поэтому толпа рисуется почти одним пакетом. Кадр выбирает EnemyAnimator у всех участников (animate):
## ходьба — по пройденному пути, удар вплотную — когда рядом герой, выстрел — по появлению снаряда врага
## (ProjectileFactory), смерть доигрывает EnemyCorpses после того, как узел исчез. Новых сетевых данных нет.
## Оттенок союзника и ярости живёт в modulate вместе с оттенком статусов, вспышка удара — в self_modulate.

const SCENE_PATH := "res://entities/enemies/enemy.tscn"
const DIRECT_CHASE_DISTANCE := 40.0
const SEPARATION_WEIGHT := 1.2
const ACCELERATION := 10.0
const CONTACT_INTERVAL := 0.5
const SHARD_COLOR := Color(0.95, 0.4, 0.3)
## Элита-«чемпион» (DESIGN 3): крепче, крупнее, дороже — множители в BalanceConfig.
const ELITE_AURA := Color(0.35, 0.55, 1.0)
const EXPLOSION_RADIUS := 36.0
const EXPLOSION_FUSE := 0.7
const ENRAGE_SPEED_MULT := 1.3
const ENRAGE_RING_MULT := 0.6
## Скелет-союзник (Некромантия): живёт ограниченное время, бьёт врагов, за хозяином не отстаёт.
const ALLY_LIFETIME := 20.0
const ALLY_SIGHT := 220.0
const ALLY_LEASH := 160.0
const ALLY_DAMAGE_MULT := 1.5
## Призванный союзник — призрачно-зелёный, ярость босса — красноватая (шаг 11.2: оттенок спрайта).
const ALLY_TINT := Color(0.7, 1.0, 0.8, 0.85)
const ENRAGE_TINT := Color(1.35, 0.7, 0.6)
## Тень под ногами: центр ниже позиции на столько px, ширина — радиусов врага.
const SHADOW_Y := 3.0
const SHADOW_WIDTH := 2.6
## Удар вплотную в анимации: герой ближе радиуса врага, радиуса героя и этого запаса, px.
const MELEE_REACH := 6.0
## Медленнее этого враг считается стоящим (покой, а не ходьба), px/с.
const WALK_MIN_SPEED := 4.0
## Враг «идёт», пока сдвигался не раньше этого, с (шаг 11.24): позиция меняется в физическом шаге (у клиентов — со
## снимками сети), а кадр анимации считается чаще — без запаса ходьба перемежалась кадрами покоя и дёргалась.
const MOVE_GRACE := 0.15
const HEALTH_BAR_BACK := Color(0.05, 0.02, 0.02, 0.8)
const HEALTH_BAR_FILL := Color(0.85, 0.15, 0.12)
const HEALTH_BAR_BOSS := Color(0.75, 0.2, 0.8)
## Особые враги: замах рывка подсвечивает фигуру; целитель и телепорт оставляют вспышку.
const CHARGE_TELL := Color(2.4, 1.5, 1.1)
const HEAL_COLOR := Color(0.45, 1.0, 0.5)
const BLINK_COLOR := Color(0.65, 0.5, 1.0)
## Самоподрыв (шаг 6): круг взрыва растёт столько секунд — от камикадзе можно отскочить.
const SUICIDE_FUSE := 0.4
## Телеграфы (шаг 6): цвет опасной области; замах кольца босса и меток призыва, с; запас круга кольца, px.
const TELL_COLOR := Color(1.0, 0.3, 0.2)
const RING_WINDUP := 0.6
const RING_TELL_MARGIN := 26.0
const SUMMON_WINDUP := 0.6
const SUMMON_MARK_RADIUS := 8.0
## Трупный взрыв (модификатор навыка): почти сразу, цвет крови.
const KILL_BLAST_FUSE := 0.12
const KILL_BLAST_COLOR := Color(0.85, 0.15, 0.15)
## Рывок не начинается вплотную — там враг и так бьёт.
const CHARGE_MIN_DISTANCE := 24.0
## Раз во столько тиков физики враг заново выбирает ближайшего героя и считает расталкивание.
const THINK_EVERY := 2
enum ChargeState { NONE, WINDUP, DASH }

@export var data_id: StringName
@export var health_mult := 1.0
@export var damage_mult := 1.0
@export var elite_affixes := PackedStringArray()
@export var ally := false
## Хозяин союзника (peer id); ему засчитываются убийства.
@export var owner_peer := 0
## Хост: чей урон наносит союзник — навык призыва или Некромантия (статистика забега, RunStats).
var source_skill: StringName

var data: EnemyData
## Хост: скорость, px/с (сглаживается к желаемой; рывок задаёт её сам).
var velocity := Vector2.ZERO
var radius := 6.0
var health := 1.0:
	set(value):
		if value != health:
			health = value
			queue_redraw()  # полоска здоровья
			if data != null and not data.phase_thresholds.is_empty():
				_update_phase()
## Фаза босса (шаг 12): сколько порогов EnemyData.phase_thresholds здоровье уже перешло. Считается у всех
## участников из здоровья (у клиентов оно приходит снимком) — новой синхронизации нет.
var phase := 0
var max_health := 1.0
var dead := false
var enraged := false
## Хост: статусы (StatusSystem): id → StatusSystem.Active.
var statuses := {}
## Биты StatusEffectData.visual_bit активных статусов; у клиентов приходят из снимка врага.
var status_flags := 0

var _world: World
var _speed := 1.0
## Половина высоты фигуры: над ней рисуются полоска здоровья и подпись элиты.
var _size := 6.0
## Как статусы меняют врага (StatusSystem.refresh).
var _status_slow := 0.0
var _stunned := false
var _feared := false
var _vulnerability := 0.0
var _damage_taken_mult := 1.0
var _lifesteal := 0.0
var _explode_damage := 0.0
var _ring_interval := 4.0
var _contact_cooldown := 0.0
var _ring_cooldown := 0.0
var _ring_phase := 0.0
var _shot_cooldown := 0.0
var _summon_cooldown := 0.0
var _life := ALLY_LIFETIME
var _charge_state := ChargeState.NONE
var _charge_left := 0.0
var _charge_cooldown := 0.0
var _charge_dir := Vector2.ZERO
var _heal_cooldown := 0.0
var _blink_cooldown := 0.0
## Кольцо босса: секунд до залпа после телеграфа; < 0 — замаха нет.
var _ring_windup := -1.0
## Аффиксы-поведения элиты (шаг 6): данные и состояние каждого (у элиты аффиксы не повторяются).
var _trail: EliteAffixData
var _nova: EliteAffixData
var _teleport: EliteAffixData
var _summoner: EliteAffixData
var _trail_from := Vector2.ZERO
var _nova_cooldown := 0.0
var _teleport_cooldown := 0.0
## Перенос назначен: секунд до него и куда; элита стоит, пока горит метка.
var _teleport_left := 0.0
var _teleport_to := Vector2.ZERO
var _summoner_cooldown := 0.0
var _summoner_left := 0.0
var _summoner_spots: Array[Vector2] = []
## Тики ИИ: свой сдвиг по кадрам, последний выбранный герой и расталкивание.
var _think_phase := 0
var _target: Player
var _push := Vector2.ZERO
## Есть ли у врага приёмы сверх касания (выстрел, кольцо, призыв, рывок, телепорт, лечение).
var _special := false
## Хост: приёмы босса по фазам (шаг 12; null — у врага нет EnemyData.attacks).
var _brain: BossBrain
## Скорость без прибавки фаз босса.
var _base_speed := 1.0
## Облик (шаг 11.2): лист в атласе, оттенок без статусов и состояние анимации.
var _sheet: SheetLayout
var _rest_tint := Color.WHITE
var _anim_clock := 0.0
var _anim_phase := 0.0
var _walked := 0.0
var _last_pos := Vector2.ZERO
## С последнего сдвига: сколько прошло (для скорости) и сколько враг уже стоит (для покоя), с.
var _since_step := 0.0
var _still_time := 1.0
var _attack_time := -1.0
var _next_swing := 0.0
var _shown_frame := -1

@onready var body: Sprite2D = $Body


## Фабрика для хоста и для spawn_function. null — неизвестный id (данные могли прийти по сети).
static func create(spawn: Dictionary) -> Enemy:
	var info := DataRegistry.enemy(spawn.get("id", &""))
	if info == null:
		return null
	var enemy: Enemy = load(SCENE_PATH).instantiate()
	enemy.data_id = info.id
	enemy.position = spawn.get("pos", Vector2.ZERO)
	enemy.health_mult = spawn.get("hp_mult", 1.0)
	enemy.damage_mult = spawn.get("dmg_mult", 1.0)
	enemy.ally = spawn.get("ally", false)
	enemy.owner_peer = spawn.get("owner", 0)
	var life := float(spawn.get("life", 0.0))
	enemy._life = life if life > 0.0 else ALLY_LIFETIME  # призыв навыка задаёт свой срок (шаг 3)
	for id in spawn.get("elite", []):
		if DataRegistry.elite_affix(StringName(str(id))) != null:
			enemy.elite_affixes.append(str(id))
	return enemy


func is_elite() -> bool:
	return not elite_affixes.is_empty()


func _ready() -> void:
	data = DataRegistry.enemy(data_id)
	radius = data.radius
	max_health = data.max_health * health_mult
	_speed = data.speed * (1.0 if ally else DataRegistry.BALANCE.enemy_speed_mult
			* RunConfig.seal_mult(SealData.Stat.ENEMY_SPEED))  # печать прыти (шаг 12.3)
	_ring_interval = data.ring_interval
	var behaviours: Array = Array(elite_affixes)
	behaviours.append_array(data.innate_affixes)  # врождённые повадки вида — те же аффиксы без статуса элиты
	for id: Variant in behaviours:
		var affix := DataRegistry.elite_affix(StringName(str(id)))
		if affix == null:
			continue
		_speed *= affix.speed_mult
		_damage_taken_mult *= affix.damage_taken_mult
		_lifesteal += affix.lifesteal
		_explode_damage += affix.explode_damage
		if affix.trail_damage > 0.0:
			_trail = affix
		if affix.nova_interval > 0.0:
			_nova = affix
			_nova_cooldown = affix.nova_interval * 0.5
		if affix.blink_interval > 0.0:
			_teleport = affix
			_teleport_cooldown = affix.blink_interval * 0.5
		if affix.summon_interval > 0.0:
			_summoner = affix
			_summoner_cooldown = affix.summon_interval * 0.5
	_trail_from = position
	if is_elite():
		max_health *= DataRegistry.BALANCE.elite_health_mult
		radius *= DataRegistry.BALANCE.elite_size_mult
	if data.is_boss:
		radius *= DataRegistry.BALANCE.boss_size_mult
	_base_speed = _speed
	if not data.attacks.is_empty() and multiplayer.is_server():
		_brain = BossBrain.new(self)
	health = max_health
	_setup_look()
	if is_elite():
		_add_name_label()
	_special = data.shot_interval > 0.0 or data.ring_count > 0 or data.summon_count > 0 \
			or data.charge_interval > 0.0 or data.blink_interval > 0.0 \
			or _trail != null or _nova != null or _teleport != null or _summoner != null or _brain != null
	_think_phase = get_instance_id() % THINK_EVERY
	_ring_cooldown = _ring_interval
	_shot_cooldown = data.shot_interval
	_summon_cooldown = data.summon_interval
	_charge_cooldown = data.charge_interval * 0.5
	_heal_cooldown = data.heal_interval
	_blink_cooldown = data.blink_interval
	_world = World.of(self)
	set_physics_process(multiplayer.is_server())


## Облик из атласа врагов: спрайт с точкой привязки над землёй, элита крупнее, заглушка — в цвет данных.
func _setup_look() -> void:
	_sheet = EnemyArt.sheet(data_id)
	body.texture = EnemyArt.texture
	body.region_enabled = true
	body.centered = false
	body.offset = -_sheet.anchor
	# Лист 96 px (шаг 11.4) в мире в 3 раза меньше (SheetLayout.scale); элита и босс — ещё крупнее.
	body.scale = Vector2.ONE * _sheet.scale * radius / data.radius
	# Детальный лист сглаживается при уменьшении (окно 1280×720); тень, аура и полоски — тоже из атласа.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if _sheet.scale < 1.0 else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	_size = _sheet.height * body.scale.y / 2.0
	_rest_tint = Color.WHITE if EnemyArt.has_sheet(data_id) else data.placeholder_color
	if ally:
		_rest_tint *= ALLY_TINT
	_apply_tint()
	_last_pos = global_position
	_anim_phase = float(get_instance_id() % 997) / 997.0 * 2.0  # толпа не дышит в такт (без общего ГСЧ)
	_show_frame(_sheet.frame(&"idle", 0))


## Тень, аура элиты и полоска здоровья — из того же атласа, что и спрайт: пакет отрисовки не рвётся.
func _draw() -> void:
	var atlas := EnemyArt.texture
	if atlas == null:
		return
	var shadow_width := radius * SHADOW_WIDTH
	draw_texture_rect_region(atlas, Rect2(-shadow_width / 2.0, SHADOW_Y - shadow_width * 0.17, shadow_width,
			shadow_width * 0.34), EnemyArt.shadow)
	if is_elite():
		var aura := Vector2(radius * 3.4, radius * 1.4)
		draw_texture_rect_region(atlas, Rect2(Vector2(0, SHADOW_Y) - aura / 2.0, aura), EnemyArt.aura, ELITE_AURA)
	if shows_health_bar():
		var width := clampf(radius * 2.6, 14.0, 44.0)
		var height := 4.0 if data.is_boss else 2.0
		var bar := Rect2(-width / 2.0, -2.0 * _size - 5.0 - height, width, height)
		draw_texture_rect_region(atlas, bar.grow(1.0), EnemyArt.white, HEALTH_BAR_BACK)
		var share := clampf(health / max_health, 0.0, 1.0) if max_health > 0.0 else 0.0
		draw_texture_rect_region(atlas, Rect2(bar.position, Vector2(width * share, height)), EnemyArt.white,
				HEALTH_BAR_BOSS if data.is_boss else HEALTH_BAR_FILL)


## Кадр анимации (шаг 11.2). Зовёт EnemyAnimator у хоста и у клиентов (позиция есть у всех): ходьба идёт по
## пройденному пути, покой — по времени, удар вплотную — когда рядом живой герой (раз в CONTACT_INTERVAL,
## как настоящий удар хоста), выстрел — play_attack из ProjectileFactory.
func animate(now: float, heroes: Array[Player]) -> void:
	var delta := now - _anim_clock
	_anim_clock = now
	var step := global_position - _last_pos
	_last_pos = global_position
	if _attack_time >= 0.0:
		_attack_time += delta
		if _attack_time >= _sheet.duration(&"attack"):
			_attack_time = -1.0
	elif absf(step.x) > 0.05 and body.flip_h != (step.x < 0.0):
		body.flip_h = step.x < 0.0
	if not ally and _attack_time < 0.0 and now >= _next_swing:
		for hero in heroes:
			var reach := radius + Player.RADIUS + MELEE_REACH
			if hero.alive and global_position.distance_squared_to(hero.global_position) <= reach * reach:
				play_attack(hero.global_position - global_position)
				_next_swing = now + CONTACT_INTERVAL
				break
	# Скорость — по пути за время с прошлого сдвига, а не за этот вызов: между физическими шагами сдвига нет.
	var moved := step.length()
	_since_step += delta
	_still_time += delta
	if moved > 0.001:
		if moved > _since_step * WALK_MIN_SPEED:
			_walked += moved
			_still_time = 0.0
		_since_step = 0.0
	if _attack_time >= 0.0:
		_show_frame(_sheet.frame(&"attack", int(_attack_time * _sheet.fps(&"attack"))))
	elif _still_time < MOVE_GRACE:
		_show_frame(_sheet.frame(&"walk", int(_walked / (_sheet.stride * body.scale.x))))
	else:
		_show_frame(_sheet.frame_at(&"idle", now + _anim_phase))


## Анимация удара в сторону direction; начатый удар не прерывается.
func play_attack(direction: Vector2) -> void:
	if dead or _sheet == null or _attack_time >= 0.0 or _sheet.count(&"attack") == 0:
		return
	_attack_time = 0.0
	if absf(direction.x) > 0.05:
		body.flip_h = direction.x < 0.0


func is_attacking() -> bool:
	return _attack_time >= 0.0


func sheet() -> SheetLayout:
	return _sheet


## Оттенок без статусов и вспышек (союзник, ярость) — им же окрашен труп.
func rest_tint() -> Color:
	return _rest_tint


func _show_frame(index: int) -> void:
	if index != _shown_frame:
		_shown_frame = index
		body.region_rect = _sheet.region(index)


func _apply_tint() -> void:
	body.modulate = DataRegistry.status_tint(status_flags) * _rest_tint


## Узел врага исчез (смерть у хоста, удаление спавнером у клиентов) — падение доигрывает EnemyCorpses,
## брызги и встряску элиты — Juice (шаг 11.9), звук смерти — CombatSound (шаг 11.27). При выходе в меню сцена
## мира уже в очереди на удаление, и трупы не нужны. Клиент не отличит смерть от очистки уровня — её следы сотрёт новый уровень.
func _exit_tree() -> void:
	if _world != null and _sheet != null and not _world.is_queued_for_deletion() and _world.corpses != null:
		_world.corpses.add(self)
		_world.juice.enemy_gone(self, dead or not multiplayer.is_server())
		_world.sfx.enemy_gone(self, dead or not multiplayer.is_server())  # хруст, рык элиты, взрыв босса (шаг 11.27)


## Полоска здоровья: у раненого врага, а у элит, мини-босса статуи и боссов — всегда.
func shows_health_bar() -> bool:
	if ally or dead or data == null:
		return false
	return data.is_boss or is_elite() or data.loot_rarity >= 0 or health < max_health


func is_slowed() -> bool:
	return _status_slow > 0.0


func is_stunned() -> bool:
	return _stunned


func is_feared() -> bool:
	return _feared


## Хост (StatusSystem.refresh): как статусы меняют врага прямо сейчас.
func set_status_effects(slow: float, stunned: bool, feared: bool, vulnerability: float, flags: int) -> void:
	_status_slow = slow
	_stunned = stunned
	_feared = feared
	_vulnerability = vulnerability
	if stunned and _charge_state != ChargeState.NONE:
		_charge_state = ChargeState.NONE  # оглушение сбивает рывок
		_charge_cooldown = data.charge_interval
		body.self_modulate = Color.WHITE
	set_status_flags(flags)


## Оттенок по статусам: у хоста — из StatusSystem, у клиентов — из флагов снимка (game/net).
func set_status_flags(flags: int) -> void:
	if flags == status_flags:
		return
	status_flags = flags
	_apply_tint()


## Сопротивление удару с тегами tags: сумма по стихиям врага, не выше BalanceConfig.max_resistance.
func resistance(tags: int) -> float:
	if tags == 0 or data.resistances.is_empty():
		return 0.0
	var total := 0.0
	for id: Variant in data.resistances:
		if tags & DataRegistry.tag_bit(StringName(str(id))):
			total += float(data.resistances[id])
	return clampf(total, -1.0, DataRegistry.BALANCE.max_resistance)


## Точка над фигурой: цифры урона, надписи реакций.
func label_position() -> Vector2:
	return global_position + Vector2(0, -2.0 * _size)


func _physics_process(delta: float) -> void:
	var started := PerfProbe.begin()
	_think(delta)
	PerfProbe.add(&"enemies", started)


func _think(delta: float) -> void:
	if ally:
		_ally_process(delta)
		return
	if _stunned:
		velocity = Vector2.ZERO  # оглушён или заморожен: стоит, не бьёт и не колдует
		return
	var director := _world.director
	var fresh := (Engine.get_physics_frames() + _think_phase) % THINK_EVERY == 0
	if fresh or _target == null or not is_instance_valid(_target) or not _target.alive:
		_target = director.nearest_player(global_position)
	var target := _target
	if _charge_state != ChargeState.NONE:
		_tick_charge(target, delta)
		return
	if _teleport_left > 0.0:
		_tick_teleport(delta)
		return
	_tick_summon_marks(delta)
	var desired := Vector2.ZERO
	if target != null and _feared:
		desired = target.global_position.direction_to(global_position)  # страх: бежит от героя, не бьёт
	elif target != null:
		var to_target := target.global_position - global_position
		var dist := to_target.length()
		if data.keep_distance > 0.0 and dist < data.keep_distance:
			desired = Vector2.ZERO  # стрелок держит дистанцию
		else:
			if dist > DIRECT_CHASE_DISTANCE:
				desired = director.flow_direction(global_position)
			if desired == Vector2.ZERO and dist > 0.01:
				desired = to_target / dist
		_try_contact(target, dist, delta)
		if dead:
			return  # самоподрыв
		if _brain != null and _brain.tick(target, delta):
			if not _brain.moving():
				velocity = Vector2.ZERO
			return  # босс стоит (замах, удар, смена фазы) или двигался сам (рывок)
		if _special:
			_try_shot(target, dist, delta)
			_try_ring_attack(delta)
			_try_summon(delta)
			_try_charge(target, dist, delta)
			_try_blink(target, dist, delta)
			_tick_affixes(target, dist, delta)
	_try_heal(delta)
	_steer(desired, delta, fresh)


## fresh — тик ИИ: расталкивание пересчитывается; в остальные тики берётся прошлое.
func _steer(desired: Vector2, delta: float, fresh: bool = true) -> void:
	if ally:
		_push = Vector2.ZERO
	elif fresh:
		var started := PerfProbe.begin()
		_push = _world.director.separation(self) * SEPARATION_WEIGHT
		PerfProbe.add(&"enemies_separation", started)
	var steer := (desired + _push).limit_length(1.2)
	velocity = velocity.lerp(steer * _speed * (1.0 - _status_slow), minf(ACCELERATION * delta, 1.0))
	_move(delta)


## Шаг со скольжением вдоль стен по логической сетке (EnemyDirector.slide). true — упёрся в стену.
func _move(delta: float) -> bool:
	if velocity == Vector2.ZERO:
		return false
	var started := PerfProbe.begin()
	var director := _world.director
	global_position = director.slide(global_position, velocity * delta, radius)
	PerfProbe.add(&"enemies_move", started)
	return director.blocked_last


## Хост: урон без тегов и статусов (Шипы, союзники, проверки). crit — удачный удар (для цифр урона);
## skill — источник для статистики забега (HitInfo.skill).
func take_damage(amount: float, source_peer_id: int, crit: bool = false, skill: StringName = &"") -> void:
	var hit := HitInfo.make(amount, source_peer_id, 0, crit)
	hit.skill = skill
	take_hit(hit)


## Хост: удар героя (шаг 2). Порядок: Губитель великанов → сопротивление стихии → уязвимость (порча) →
## аффиксы элиты → Вампиризм и Казнь → смерть или статусы удара. Действительный урон (не больше
## оставшегося здоровья) и убийство уходят в статистику забега (RunStats).
func take_hit(hit: HitInfo) -> void:
	if dead or ally or not multiplayer.is_server():
		return
	var attacker := _world.find_player(hit.source_peer)
	var amount := hit.amount
	if attacker != null and (data.is_boss or is_elite() or data.loot_rarity >= 0):
		amount *= 1.0 + attacker.stat(Player.STAT_GIANT_SLAYER)  # Губитель великанов
	amount *= (1.0 - resistance(hit.tags)) * (1.0 + _vulnerability)
	var dealt := amount * _damage_taken_mult
	if attacker != null and not hit.is_dot:
		attacker.on_hit_dealt(minf(dealt, maxf(health, 0.0)), hit.leech)  # Вампиризм — без урона «сверх смерти»
	var before := maxf(health, 0.0)
	health -= dealt
	if attacker != null and not data.is_boss and health > 0.0 \
			and health <= max_health * attacker.capped(Player.STAT_EXECUTE):
		health = 0.0  # Казнь: добить раненого
	_world.run_stats.record_hit(hit, minf(dealt, before), health <= 0.0, self)
	Events.damage_dealt.emit(label_position(), dealt, hit.crit)
	if not hit.is_dot:
		flash_hit()
	if data.enrage_below > 0.0 and not enraged and health > 0.0 and health < max_health * data.enrage_below:
		_enrage()
	if health <= 0.0:
		_die(hit.source_peer)
		if hit.kill_blast_radius > 0.0 and not hit.is_dot:
			_kill_blast(hit)
	elif not hit.statuses.is_empty() and not hit.is_dot:
		_world.statuses.apply_from_hit(self, hit)


## Модификатор «трупный взрыв» (шаг 3): убитый взрывается и ранит соседей. Взрыв — снаряд героя без
## статусов и без своего взрыва при убийстве, поэтому цепной реакции нет.
func _kill_blast(hit: HitInfo) -> void:
	var node := _world.spawn_projectile({
		"type": &"blast", "pos": global_position, "radius": hit.kill_blast_radius, "fuse": KILL_BLAST_FUSE,
		"damage": hit.amount * hit.kill_blast_share, "hostile": false, "owner": hit.source_peer,
		"color": KILL_BLAST_COLOR,
	})
	var blast := node as Projectile
	if blast != null:
		blast.tags = hit.tags
		blast.skill = hit.skill


## Вспышка и отдача от удара (отдача — шаг 11.9, только картинка: спрайт сдвигается от героя и возвращается).
## У клиентов вспышку и отдачу показывает WorldNet, когда здоровье из снимка уменьшилось.
func flash_hit() -> void:
	body.self_modulate = Color(3.0, 3.0, 3.0)
	body.position = recoil_offset()
	var tween := create_tween().set_parallel()
	tween.tween_property(body, ^"self_modulate", Color.WHITE, 0.1)
	tween.tween_property(body, ^"position", Vector2.ZERO, DataRegistry.VISUAL.recoil_time)


## Сдвиг спрайта при отдаче: от ближайшего героя на VisualConfig.recoil px.
func recoil_offset() -> Vector2:
	var best := Vector2.ZERO
	var best_distance := INF
	for player in _world.get_players():
		var distance := player.global_position.distance_squared_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = player.global_position
	if best_distance == INF or best == global_position:
		return Vector2.ZERO
	return best.direction_to(global_position) * DataRegistry.VISUAL.recoil


func _die(killer_peer_id: int) -> void:
	dead = true
	if not ally:
		var pos := global_position
		var killer := _world.find_player(killer_peer_id)
		if killer != null:
			killer.kills += 1
		if data.xp > 0:
			var xp := _world.waves.xp_reward(data.xp * (DataRegistry.BALANCE.elite_xp_mult if is_elite() else 1))
			_world.upgrades.drop_xp(pos, xp)
			_world.upgrades.maybe_drop_magnet(pos, is_elite())
		if data.loot_rarity >= 0:
			for i in maxi(data.loot_items, 1):  # мимик роняет добычу сундука вдвое (шаг 8)
				_world.loot.drop_item(pos, data.loot_rarity)
		else:
			var table := _world.loot.table
			var chance := table.elite_drop_chance if is_elite() else table.enemy_drop_chance
			_world.loot.maybe_drop(pos, chance * _world.waves.reward_mult())  # алтарь проклятий (шаг 8)
		_world.economy.drop_enemy_rewards(self)
		if _explode_damage > 0.0:
			_world.spawn_projectile({
				"type": &"blast", "pos": pos, "radius": EXPLOSION_RADIUS, "fuse": EXPLOSION_FUSE,
				"damage": _explode_damage * damage_mult, "hostile": true, "color": SHARD_COLOR,
			})
		_split(pos)
		Events.enemy_died.emit(self, killer_peer_id)
	queue_free()


func _enrage() -> void:
	enraged = true
	_speed *= ENRAGE_SPEED_MULT
	_ring_interval *= ENRAGE_RING_MULT
	_rest_tint *= ENRAGE_TINT
	_apply_tint()


## Фазы босса (шаг 12): только вперёд — лечение не возвращает прошлую фазу. Последняя фаза — облик ярости.
## У хоста новая фаза ускоряет босса и перезапускает его приёмы (BossBrain.on_phase).
func _update_phase() -> void:
	if max_health <= 0.0:
		return
	var share := health / max_health
	var reached := 0
	for threshold in data.phase_thresholds:
		if share < threshold:
			reached += 1
	if reached <= phase:
		return
	phase = reached
	if phase == data.phase_thresholds.size():
		_rest_tint *= ENRAGE_TINT
		_apply_tint()
	if multiplayer.is_server() and is_inside_tree():
		_speed = _base_speed * pow(data.phase_speed_mult, phase)
		_flash_fx(global_position, TELL_COLOR, radius * 3.0)
		if _brain != null:
			_brain.on_phase(phase)


## Хост: шаг рывка босса (BossCharge) по direction; касание ранит, как обычно. true — упёрся в стену.
func dash_step(direction: Vector2, speed: float, delta: float) -> bool:
	velocity = direction * speed * (1.0 - _status_slow)
	var hit_wall := _move(delta)
	var hero := _world.director.nearest_player(global_position)
	if hero != null:
		_try_contact(hero, global_position.distance_to(hero.global_position), 0.0)
	return hit_wall


## Хост: приёмы босса (для проверок и отладки); null — не босс с приёмами.
func brain() -> BossBrain:
	return _brain


func _try_contact(target: Player, dist: float, delta: float) -> void:
	_contact_cooldown -= delta
	if data.suicide_damage > 0.0 and dist <= radius + Player.RADIUS + 4.0:
		_detonate()
		return
	if _contact_cooldown <= 0.0 and dist <= radius + Player.RADIUS + 2.0:
		var dealt := data.contact_damage * damage_mult
		target.take_damage(dealt, self)
		if _lifesteal > 0.0:
			health = minf(max_health, health + dealt * _lifesteal)
		_contact_cooldown = CONTACT_INTERVAL


func _try_shot(target: Player, dist: float, delta: float) -> void:
	if data.shot_interval <= 0.0:
		return
	_shot_cooldown -= delta
	if _shot_cooldown > 0.0 or dist > data.shot_range:
		return
	_shot_cooldown = data.shot_interval
	var damage := data.shot_damage * damage_mult * _ranged_mult()
	if data.shot_lob:  # мортира: взрыв там, где герой стоял в момент выстрела; from — кто бросил (анимация)
		_world.spawn_projectile({
			"type": &"blast", "pos": target.global_position, "radius": data.shot_blast, "fuse": data.shot_fuse,
			"damage": damage, "hostile": true, "color": data.placeholder_color, "from": global_position,
		})
		return
	var aim := global_position.direction_to(target.global_position)
	var count := maxi(data.shot_count, 1)
	var spread := deg_to_rad(data.shot_spread_deg)
	for i in count:
		var offset := 0.0 if count == 1 else spread * (float(i) / (count - 1) - 0.5)
		_world.spawn_projectile({
			"type": &"shard", "pos": global_position, "dir": aim.rotated(offset),
			"speed": data.shot_speed, "range": data.shot_range * 1.3,
			"damage": damage, "hostile": true, "color": data.placeholder_color,
		})


## Кольцо снарядов (боссы): уклоняться нужно движением, без автоатаки это не отбить.
## Шаг 6: за RING_WINDUP с до залпа вокруг босса загорается круг-предупреждение.
func _try_ring_attack(delta: float) -> void:
	if data.ring_count <= 0:
		return
	if _ring_windup >= 0.0:
		_ring_windup -= delta
		if _ring_windup < 0.0:
			_fire_ring()
		return
	_ring_cooldown -= delta
	if _ring_cooldown > 0.0:
		return
	_ring_cooldown = _ring_interval
	_ring_windup = RING_WINDUP
	_warn(global_position, radius + RING_TELL_MARGIN, RING_WINDUP, TELL_COLOR)


func _fire_ring() -> void:
	_ring_phase += PI / data.ring_count  # каждое следующее кольцо повёрнуто на полшага
	for i in data.ring_count:
		_world.spawn_projectile({
			"type": &"shard", "pos": global_position,
			"dir": Vector2.RIGHT.rotated(_ring_phase + TAU * i / data.ring_count),
			"speed": data.ring_speed, "range": data.ring_range,
			"damage": data.ring_damage * damage_mult * _ranged_mult(), "hostile": true, "color": SHARD_COLOR,
		})


## Дальние атаки обычных врагов слабее (BalanceConfig.ranged_damage_mult); у боссов — без поправки.
func _ranged_mult() -> float:
	return 1.0 if data.is_boss else DataRegistry.BALANCE.ranged_damage_mult


func _try_summon(delta: float) -> void:
	if data.summon_count <= 0:
		return
	_summon_cooldown -= delta
	if _summon_cooldown > 0.0:
		return
	_summon_cooldown = data.summon_interval
	if _world.director.hostile_count() >= _world.waves.table.max_alive:
		return
	for i in data.summon_count:
		var offset := Vector2.RIGHT.rotated(TAU * i / data.summon_count) * (radius + 14.0)
		if not _world.is_blocked(global_position + offset):
			_world.spawn_enemy({
				"id": data.summon_id, "pos": global_position + offset,
				"hp_mult": health_mult, "dmg_mult": damage_mult,
			})


## Рывок: замах на месте (фигура вспыхивает), затем бросок по прямой к тому месту, где был герой.
## Шаг 6: направление выбирается в начале замаха, а полоса на земле показывает путь рывка — от него
## можно уйти в сторону.
func _try_charge(target: Player, dist: float, delta: float) -> void:
	if data.charge_interval <= 0.0:
		return
	_charge_cooldown -= delta
	if _charge_cooldown > 0.0 or dist > data.charge_range or dist < CHARGE_MIN_DISTANCE:
		return
	_charge_state = ChargeState.WINDUP
	_charge_left = data.charge_windup
	_charge_dir = global_position.direction_to(target.global_position)
	body.self_modulate = CHARGE_TELL
	_world.spawn_projectile({
		"type": &"warn", "pos": global_position, "dir": _charge_dir, "line": true,
		"range": data.charge_speed * data.charge_time, "radius": radius + 2.0, "fuse": data.charge_windup,
		"color": TELL_COLOR,
	})


func _tick_charge(target: Player, delta: float) -> void:
	_charge_left -= delta
	if _charge_state == ChargeState.WINDUP:
		velocity = Vector2.ZERO
		if _charge_left <= 0.0:
			_charge_state = ChargeState.DASH
			_charge_left = data.charge_time
			body.self_modulate = Color.WHITE
		return
	velocity = _charge_dir * data.charge_speed * (1.0 - _status_slow)
	var hit_wall := _move(delta)
	if target != null:
		_try_contact(target, global_position.distance_to(target.global_position), delta)
	if _charge_left <= 0.0 or hit_wall:
		_charge_state = ChargeState.NONE
		_charge_cooldown = data.charge_interval


## Телепорт: вспышка — и враг уже на blink_range ближе к герою; сразу готов стрелять.
func _try_blink(target: Player, dist: float, delta: float) -> void:
	if data.blink_interval <= 0.0:
		return
	_blink_cooldown -= delta
	if _blink_cooldown > 0.0 or dist <= maxf(data.keep_distance, data.blink_range * 0.6):
		return
	var step := minf(data.blink_range, dist - maxf(data.keep_distance, 24.0))
	var to := global_position + global_position.direction_to(target.global_position) * step
	if _world.is_blocked(to):
		return  # за стеной не появляется — подождёт следующего раза
	_blink_cooldown = data.blink_interval
	_flash_fx(global_position, BLINK_COLOR)
	global_position = to
	_flash_fx(to, BLINK_COLOR)
	_shot_cooldown = minf(_shot_cooldown, 0.3)


## Целитель: раненые враги вокруг получают долю здоровья.
func _try_heal(delta: float) -> void:
	if data.heal_interval <= 0.0:
		return
	_heal_cooldown -= delta
	if _heal_cooldown > 0.0:
		return
	_heal_cooldown = data.heal_interval
	var healed := false
	for other in _world.director.enemies_in_radius(global_position, data.heal_radius):
		if other != self and not other.dead and other.health < other.max_health:
			other.health = minf(other.max_health, other.health + other.max_health * data.heal_share)
			healed = true
	if healed:
		_flash_fx(global_position, HEAL_COLOR, data.heal_radius)


## Самоподрыв: взрыв почти сразу; герой, который не отбежал, получает урон. Наград за такую смерть нет.
func _detonate() -> void:
	dead = true
	_world.spawn_projectile({
		"type": &"blast", "pos": global_position, "radius": data.suicide_radius, "fuse": SUICIDE_FUSE,
		"damage": data.suicide_damage * damage_mult, "hostile": true, "color": data.placeholder_color,
	})
	queue_free()


## Деление: на месте убитого — несколько врагов split_id той же силы.
func _split(pos: Vector2) -> void:
	for i in data.split_count:
		var offset := Vector2.RIGHT.rotated(TAU * i / data.split_count) * (radius + 4.0)
		var at := pos + offset if not _world.is_blocked(pos + offset) else pos
		_world.spawn_enemy({"id": data.split_id, "pos": at, "hp_mult": health_mult, "dmg_mult": damage_mult})


func _flash_fx(pos: Vector2, color: Color, size: float = 14.0) -> void:
	_world.spawn_projectile({"type": &"pulse", "pos": pos, "radius": size, "color": color})


## Телеграф-круг (Projectile «warn»): удар придёт сюда через time секунд.
func _warn(pos: Vector2, size: float, time: float, color: Color) -> void:
	_world.spawn_projectile({"type": &"warn", "pos": pos, "radius": size, "fuse": time, "color": color})


# --- Аффиксы-поведения элиты (шаг 6) ---

func _tick_affixes(target: Player, dist: float, delta: float) -> void:
	if _trail != null:
		_tick_trail()
	if _nova != null:
		_try_nova(dist, delta)
	if _teleport != null:
		_try_teleport(target, dist, delta)
	if _summoner != null:
		_try_summon_minions(delta)


## Огненный: пятно огня через каждые trail_step px пути — герой, наступивший в него, горит.
func _tick_trail() -> void:
	if global_position.distance_to(_trail_from) < _trail.trail_step:
		return
	_trail_from = global_position
	_world.spawn_projectile({
		"type": &"zone", "pos": global_position, "radius": _trail.trail_radius, "duration": _trail.trail_time,
		"tick": 0.5, "damage": _trail.trail_damage * damage_mult, "hostile": true, "color": _trail.color,
	})


## Ледяной: вокруг элиты растёт круг взрыва (он и есть телеграф), затем урон и холод тем, кто не вышел.
func _try_nova(dist: float, delta: float) -> void:
	_nova_cooldown -= delta
	if _nova_cooldown > 0.0 or dist > _nova.nova_radius * 2.0:
		return
	_nova_cooldown = _nova.nova_interval
	_world.spawn_projectile({
		"type": &"blast", "pos": global_position, "radius": _nova.nova_radius, "fuse": _nova.nova_windup,
		"damage": _nova.nova_damage * damage_mult, "hostile": true, "color": _nova.color, "chill": true,
	})


## Телепортирующийся: метка рядом с героем, элита замирает; через blink_windup с — она уже там.
func _try_teleport(target: Player, dist: float, delta: float) -> void:
	_teleport_cooldown -= delta
	if _teleport_cooldown > 0.0 or dist < _teleport.blink_min_range:
		return
	var away := target.global_position.direction_to(global_position)
	for side in [1.0, -1.0]:
		var to := target.global_position + away.rotated(randf_range(0.0, 0.9) * side) * _teleport.blink_distance
		if not _world.is_blocked(to):
			_teleport_to = to
			_teleport_left = _teleport.blink_windup
			_teleport_cooldown = _teleport.blink_interval
			_warn(to, radius + 6.0, _teleport.blink_windup, _teleport.color)
			return
	_teleport_cooldown = 1.0  # места рядом с героем нет — попробует позже


func _tick_teleport(delta: float) -> void:
	velocity = Vector2.ZERO
	_teleport_left -= delta
	if _teleport_left > 0.0:
		return
	_flash_fx(global_position, _teleport.color)
	global_position = _teleport_to
	_trail_from = _teleport_to  # перенос не оставляет огненной дорожки через всю карту
	_flash_fx(_teleport_to, _teleport.color)


## Призыватель: метки вокруг элиты, через SUMMON_WINDUP с из них встают подручные (тот же вид, слабее).
func _try_summon_minions(delta: float) -> void:
	_summoner_cooldown -= delta
	if _summoner_cooldown > 0.0 or not _summoner_spots.is_empty():
		return
	_summoner_cooldown = _summoner.summon_interval
	if _world.director.hostile_count() >= _world.waves.table.max_alive:
		return
	for i in _summoner.summon_count:
		var spot := global_position + Vector2.RIGHT.rotated(TAU * i / _summoner.summon_count + randf()) * (radius + 18.0)
		if not _world.is_blocked(spot):
			_summoner_spots.append(spot)
			_warn(spot, SUMMON_MARK_RADIUS, SUMMON_WINDUP, _summoner.color)
	_summoner_left = SUMMON_WINDUP


func _tick_summon_marks(delta: float) -> void:
	if _summoner_spots.is_empty():
		return
	_summoner_left -= delta
	if _summoner_left > 0.0:
		return
	for spot in _summoner_spots:
		_world.spawn_enemy({
			"id": data.id, "pos": spot, "hp_mult": health_mult * _summoner.summon_health, "dmg_mult": damage_mult,
		})
	_summoner_spots.clear()


func _ally_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_die(owner_peer)
		return
	var master := _world.find_player(owner_peer)
	var target := _world.director.nearest_enemy(global_position, ALLY_SIGHT)
	var desired := Vector2.ZERO
	if master != null and global_position.distance_to(master.global_position) > ALLY_LEASH:
		desired = global_position.direction_to(master.global_position)
	elif target != null:
		desired = global_position.direction_to(target.global_position)
		_contact_cooldown -= delta
		if _contact_cooldown <= 0.0 and global_position.distance_to(target.global_position) <= radius + target.radius + 2.0:
			target.take_damage(data.contact_damage * ALLY_DAMAGE_MULT * damage_mult, owner_peer, false, source_skill)
			_contact_cooldown = CONTACT_INTERVAL
	_steer(desired, delta)


## Имя и аффиксы над элитой (DESIGN 3). Текст строится из ключей и на клиентах тоже.
func _add_name_label() -> void:
	var names := PackedStringArray()
	for id in elite_affixes:
		names.append(tr(DataRegistry.elite_affix(id).name_key))
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = "%s\n%s" % [tr(data.name_key), ", ".join(names)]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.size = Vector2(120, 24)
	label.position = Vector2(-60, -_size * 2.0 - 32.0)  # над полоской здоровья
	LightMap.lift_label(label)
	add_child(label)
