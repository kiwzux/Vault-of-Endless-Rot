class_name Player
extends CharacterBody2D
## Персонаж игрока. Имя узла = peer id владельца: ввод обрабатывает владелец,
## урон, смерть, опыт, улучшения, экипировка и стрельба оружия — хост (DESIGN 5.1).
##
## Синхронизация для game/net (ФТ-14): position — владелец → все;
## health, max_health, mana, max_mana, alive, level, xp, move_speed, buffs, gold, potions, kills,
## chests_opened, run_stats — хост → все;
## equipment, item_stats, items_collected, upgrade_levels, runes, evolution_stages, rerolls, banished,
## banishes_left — хост → владелец (руны, уровни и ступени эволюции — HUD сборки, карты левел-апа и резонансы, шаг 4).
## Предметы копятся (17.10.2026): сумки нет, каждый подобранный предмет навсегда прибавляет свои характеристики
## (item_stats); в equipment — лучший найденный предмет каждого слота (кукла и легендарная руна).

const GROUP := &"players"
const RADIUS := 7.0
## Пояс зелий в духе Diablo (CR-14): зелья пьются клавишей Q.
const BELT_SIZE := 4
## Пассивки героев (HeroData.passive). Их числа переедут в данные класса вместе с новыми классами (шаг 3);
## остальной баланс героя — BalanceConfig, пределы характеристик — StatDef.cap.
const PASSIVE_LEADERSHIP := &"leadership"
const PASSIVE_NECROMANCY := &"necromancy"
const PASSIVE_MANA_SHIELD := &"mana_shield"
## Лидерство: союзники рядом с Рыцарем наносят больше урона (DESIGN 1).
const LEADERSHIP_RADIUS := 120.0
const LEADERSHIP_BONUS := 0.1
## Мана-щит: эта доля урона списывается с маны, пока она есть.
const MANA_SHIELD_SHARE := 0.5
## Характеристики, которые копят пассивки, предметы, баффы и реликвии.
const STAT_MIGHT := &"might"
const STAT_HASTE := &"haste"
const STAT_SWIFTNESS := &"swiftness"
const STAT_MAX_HEALTH := &"max_health"
const STAT_MAGNET := &"magnet"
const STAT_ARMOR := &"armor"
const STAT_REGEN := &"regen"
const STAT_MAX_MANA := &"max_mana"
## Шанс удачного удара (двойной урон), 0..1.
const STAT_CRIT := &"crit"
## Зона поражения: радиус ударов, аур, взрывов и орбит, доля.
const STAT_AREA := &"area"
## Дополнительные снаряды, прыжки молнии, метеоры и сферы.
const STAT_AMOUNT := &"amount"
const STAT_XP_GAIN := &"xp_gain"
const STAT_GOLD_GAIN := &"gold_gain"
## Вампиризм: доля нанесённого урона возвращается здоровьем.
const STAT_LIFESTEAL := &"lifesteal"
## Уклонение: шанс не получить удар вовсе (не больше MAX_DODGE).
const STAT_DODGE := &"dodge"
## Шипы: урон врагу, ударившему героя вплотную.
const STAT_THORNS := &"thorns"
## Стойкость: доля урона, которая не проходит (не больше MAX_RESILIENCE), до брони.
const STAT_RESILIENCE := &"resilience"
## Проклятие (Vampire Survivors): врагов в волнах больше на эту долю (опыт и золото — bonus_stats).
const STAT_CURSE := &"curse"
## Казнь: враг (не босс), у которого после удара осталось меньше этой доли здоровья, погибает сразу.
const STAT_EXECUTE := &"execute"
## Второе дыхание: столько раз за забег герой встаёт после смертельного удара.
const STAT_REVIVAL := &"revival"
## Сокрушение: прибавка к множителю удачного удара (×2 → ×2 + значение).
const STAT_CRIT_DAMAGE := &"crit_damage"
## Губитель великанов: доля урона сверх обычного по элитам, мини-боссам и боссам.
const STAT_GIANT_SLAYER := &"giant_slayer"
## Оберег: заряд поглощает удар целиком; доля, на которую быстрее заряжается (от WARD_INTERVAL).
const STAT_WARD := &"ward"
## Ярость: доля урона сверх обычного, пока здоровья меньше BERSERK_THRESHOLD.
const STAT_BERSERK := &"berserk"
## Таланты классов из хаба (CR-04): сила Лидерства (и на самого Рыцаря), шанс и число скелетов
## Некромантии, доля урона в Мана-щит.
const STAT_LEADERSHIP := &"leadership"
const STAT_NECROMANCY := &"necromancy"
const STAT_MANA_SHIELD := &"mana_shield"
const MAX_MANA_SHIELD := 0.9
## «Последний вздох» (LastBreathSystem): призрак павшего героя движется медленнее живого.
const GHOST_SPEED_MULT := 0.5
const REVIVE_RING := Color(0.55, 1.0, 0.65)
## Особые «характеристики» запасных карт: не копятся, а срабатывают сразу.
const STAT_HEAL := &"heal"
const STAT_GOLD := &"gold"

@export var hero: HeroData

var health: float
var max_health: float
var mana := 0.0
var max_mana := 0.0
var alive := true:
	set(value):
		if alive and not value and is_node_ready() and _layout != null and _layout.count(ANIM_DEATH) > 0:
			_death_time = 0.0  # шаг 11.19: сначала падение, призрак — когда оно доиграло
			_attack_time = -1.0
			_hurt_time = -1.0
		elif value:
			_death_time = -1.0
		alive = value
		if is_node_ready():
			_update_look()
var level := 1
var xp := 0
var move_speed: float
## Хост: id улучшения → уровень.
var upgrade_levels := {}
## Хост: руны забега на навыках (шаги 3–4): id навыка → [id руны] в порядке вставки.
var runes := {}
## Хост: ступени эволюции навыков (UpgradePool, UpgradeRules.evolution_stages): id навыка → ступень (нет — 0).
var evolution_stages := {}
## Временные усиления: id → {"time": секунд осталось, "stats": {stat: value}}.
var buffs := {}
## Постоянные бонусы забега (Грааль): id → {stat: value}.
var bonuses := {}
## Экипировка: ItemBaseData.Slot → лучший найденный предмет слота (словарь ItemRoller) — кукла и легендарная руна.
var equipment := {}
## Сумма характеристик всех подобранных предметов (они копятся) и сколько предметов подобрано.
var item_stats := {}
var items_collected := 0
## Золото забега (CR-14), зелья в поясе, убитые враги, сколько раз перебрасывались карты.
var gold := 0
var potions := 0
var kills := 0
var rerolls := 0
## Сколько повышений уровня ждёт выбора карты (хост → все): в кооперативе выбор откладывается до клавиши R.
var pending_choices := 0
## Изгнанные карты (до конца забега не выпадают) и сколько ещё можно изгнать.
var banished: Array[StringName] = []
var banishes_left := 0
## Сколько платных сундуков открыл герой: от этого растёт цена следующего.
var chests_opened := 0
## Второе дыхание: сколько раз уже вставал. Оберег: заряд готов поглотить удар.
var revivals_used := 0
var ward_ready := false
## «Последний вздох»: 0..1 — сколько союзник уже простоял рядом с павшим героем (хост → все, кольцо над призраком).
var revive_progress := 0.0:
	set(value):
		if value != revive_progress:
			revive_progress = value
			queue_redraw()
## Таланты класса из хаба (CR-04): id таланта → ранг. Хост ограничивает ранги данными (TalentData).
@export var talents := {}
## Хост: навыки, ещё не открытые в профиле игрока заданиями Убежища (шаг 10), — в его левел-апе их нет.
var locked_skills: Array[StringName] = []
## Хост → все: сколько раз героя сковал холод (Ледяная элита, шаг 6). Синхронизируется счётчик, а не таймер:
## хост шлёт его только в момент удара, а замедление на CHILL_TIME с каждый участник отсчитывает сам.
var chills := 0:
	set(value):
		if value > chills:
			_chill_left = CHILL_TIME
		chills = value
var _chill_left := 0.0
## Хост: дробная часть опыта от «Обучаемости» — копится до целого кристалла.
var xp_carry := 0.0
## Статистика забега (RunStats.summary_of): хост → все, обновляется раз в RunStats.PUBLISH_INTERVAL с
## и в конце забега — по ней экран конца забега у каждого участника.
var run_stats := {}
## Хост: случайность удачи и оружия; сид от сида забега — бой воспроизводим по коду забега.
var rng := RandomNumberGenerator.new()
## Только для проверок и отладки: урон не проходит.
var invulnerable := false

var _skills: Array[SkillRuntime] = []
var _stats := {}
## Характеристики «по тегу» (StatDef): базовая → [[бит тега, значение], …]; собираются в _recalculate_stats.
var _scoped := {}
var _world: World
var _gold_carry := 0.0
var _ward_timer := 0.0

## Анимации листа героя (HeroData.sprite_sheet, раскладка — SheetLayout, шаг 11.1).
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_ATTACK := &"attack"
## Удар на ходу: строки листа по фазам ходьбы — ноги шагают, пока руки бьют.
const ANIM_ATTACK_WALK := &"attack_walk"
## Шаг 11.19: каст — навык, который ставится у цели (удар с неба, зона, ловушка); вздрагивание от удара; смерть.
const ANIM_CAST := &"cast"
const ANIM_HURT := &"hurt"
const ANIM_DEATH := &"death"
## Вздрагивание не чаще раза в столько секунд: в толпе врагов герой иначе дёргался бы без конца.
const HURT_COOLDOWN := 0.8
## Пауза после удара перед следующим: навыков до шести, без паузы герой не выходил бы из удара.
const ATTACK_REST := 0.12
## Герой «идёт», пока сдвигался не раньше этого, с (шаг 11.22). Позиция меняется в физическом шаге (60 в секунду),
## у клиентов — со снимками сети, а кадров отрисовки больше: без запаса между сдвигами показывался кадр покоя,
## и в забеге (FPS без предела) ходьба почти замирала.
const MOVE_GRACE := 0.1
## Отскок спрайта назад при ударе по герою, px.
const HURT_RECOIL := 2.0
## Холод (Ледяная элита, шаг 6): столько секунд герой идёт медленнее на CHILL_SLOW и отливает синим.
const CHILL_TIME := 2.0
const CHILL_SLOW := 0.4
const CHILL_TINT := Color(0.6, 0.85, 1.2)

var _layout: SheetLayout
var _anim_time := 0.0
## Пройденный путь, px мира: кадр ходьбы — путь / шаг листа, ноги не скользят (шаг 11.3).
var _walked := 0.0
## Секунд с последнего сдвига героя.
var _still_time := 1.0
## Секунд с начала удара; < 0 — герой не бьёт. _attack_anim — удар или каст (шаг 11.19).
var _attack_time := -1.0
var _attack_anim := ANIM_ATTACK
## Секунд с начала вздрагивания и смерти; < 0 — не идёт. Смерть доигрывается, потом герой — призрак.
var _hurt_time := -1.0
var _since_hurt := HURT_COOLDOWN
var _death_time := -1.0
## Секунд с конца прошлого удара.
var _since_attack := 1.0
var _last_position := Vector2.ZERO
## Куда герой смотрит (шаг 11.11): угол на экране (0 — вправо, 90 — вниз) и блок листа из 8 направлений.
var _facing := 0.0
var _dir := 0

@onready var body: Sprite2D = $Body
@onready var camera: Camera2D = $Camera2D


## ФТ-10: опыт до следующего уровня (BalanceConfig: xp_first, дальше +xp_step за уровень).
static func xp_to_next(p_level: int) -> int:
	return DataRegistry.BALANCE.xp_to_next(p_level)


func _enter_tree() -> void:
	add_to_group(GROUP)
	var peer_id := String(name).to_int()
	set_multiplayer_authority(peer_id if peer_id > 0 else 1)


func _ready() -> void:
	if hero == null:
		hero = RunConfig.get_hero()
	max_health = hero.max_health
	health = max_health
	max_mana = hero.max_mana
	mana = max_mana
	move_speed = hero.move_speed
	potions = DataRegistry.ECONOMY.start_potions
	banishes_left = DataRegistry.UPGRADE_RULES.banishes
	rng.seed = hash([RunConfig.run_seed, "luck", peer_id()])
	body.texture = hero.sprite_sheet
	_layout = SheetLayout.of(hero.sprite_sheet)
	if _layout != null:
		_layout.apply_to(body)
	_last_position = position
	camera.enabled = is_multiplayer_authority()
	_world = World.of(self)
	LightSources.add(self, DataRegistry.VISUAL.hero_light, DataRegistry.VISUAL.hero_light_radius, LightSources.Rank.HERO)
	if multiplayer.is_server():
		if not hero.base_stats.is_empty():
			bonuses[&"class"] = hero.base_stats.duplicate()  # черта класса (шаг 3)
		_apply_talents()
		_recalculate_stats()
	_update_look()


## ФТ-08: движение в реальном времени у владельца, автоатака всех навыков — на хосте.
## Пока открыто окно интерфейса (пауза, левел-ап, инвентарь, торговец), герой стоит.
## Павший герой — призрак («Последний вздох»): медленно идёт к союзникам, чтобы те его подняли.
func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var direction := Vector2.ZERO
		if not _input_blocked():
			direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		velocity = direction * move_speed * (1.0 if alive else GHOST_SPEED_MULT) * (1.0 - CHILL_SLOW if is_chilled() else 1.0)
		move_and_slide()
	if _chill_left > 0.0:
		_chill_left -= delta
		body.modulate = CHILL_TINT if _chill_left > 0.0 else Color.WHITE
	if alive and multiplayer.is_server() and _world != null:
		var started := PerfProbe.begin()
		for skill in _skills:
			skill.tick(delta, self, _world)
		PerfProbe.add(&"skills", started)
		_tick_resources(delta)


## Вид героя считается по смещению за кадр, а не по velocity: так анимация одинакова у владельца,
## хоста и клиентов, которым приходит только позиция. Удар запускает play_attack.
func _process(delta: float) -> void:
	if _layout == null:
		return
	var step := position - _last_position
	_last_position = position
	var stepped := step.length() > 0.01
	_still_time = 0.0 if stepped else _still_time + delta
	var moving := alive and _still_time < MOVE_GRACE
	_anim_time += delta
	_since_attack += delta
	_since_hurt += delta
	if stepped:
		_walked += step.length()
	if _death_time >= 0.0:
		_death_time += delta
		if _death_time >= _layout.duration(ANIM_DEATH):
			_death_time = -1.0
			_update_look()  # упал — дальше призрак
	if _hurt_time >= 0.0:
		_hurt_time += delta
		if _hurt_time >= _layout.duration(ANIM_HURT) or moving:
			_hurt_time = -1.0
	if _attack_time >= 0.0:
		_attack_time += delta
		if _attack_time >= _layout.duration(_attack_anim):
			_attack_time = -1.0
			_since_attack = 0.0
	elif stepped:
		_face(step, false)
	body.frame = _current_frame(moving)


## Повернуть героя по направлению v (движение или удар): один из 8 блоков листа, влево — отражение.
## Удар (force) поворачивает сразу, движение — с запасом в TURN_HYSTERESIS.
func _face(v: Vector2, force: bool) -> void:
	if v.length_squared() < 0.0001:
		return
	_facing = snappedf(rad_to_deg(v.angle()), 45.0) if force else SheetLayout.turn(_facing, v)
	var facing := _layout.facing(_facing, body.flip_h)
	_dir = facing[0]
	body.flip_h = facing[1]


func _current_frame(moving: bool) -> int:
	if _death_time >= 0.0:
		return _layout.frame(ANIM_DEATH, mini(int(_death_time * _layout.fps(ANIM_DEATH)), _layout.count(ANIM_DEATH) - 1), 0, _dir)
	var phase := int(_walked / _layout.world_stride())
	if _attack_time >= 0.0:
		var i := int(_attack_time * _layout.fps(_attack_anim))
		if moving and _layout.count(ANIM_ATTACK_WALK) > 0:  # на ходу и каст — удар поверх шага: ноги не замирают
			var walk_frame := posmod(phase, _layout.count(ANIM_WALK))
			var row := walk_frame * _layout.rows_of(ANIM_ATTACK_WALK) / _layout.count(ANIM_WALK)
			return _layout.frame(ANIM_ATTACK_WALK, int(_attack_time * _layout.fps(ANIM_ATTACK)), row, _dir)
		return _layout.frame(_attack_anim, i, 0, _dir)
	if moving:
		return _layout.frame(ANIM_WALK, phase, 0, _dir)
	if _hurt_time >= 0.0:
		return _layout.frame(ANIM_HURT, int(_hurt_time * _layout.fps(ANIM_HURT)), 0, _dir)
	return _layout.frame_at(ANIM_IDLE, _anim_time, _dir)


## Анимация удара навыком в сторону direction. Вызывает ProjectileFactory, когда появился снаряд или след
## этого героя — у хоста и у клиентов одинаково, поэтому отдельной синхронизации нет. Начатый удар
## не прерывается, следующий — не раньше чем через ATTACK_REST после конца прошлого.
## cast (шаг 11.19) — навык ставится у цели (удар с неба, зона, ловушка): заклинание вместо удара, если оно есть в листе.
func play_attack(direction: Vector2, cast: bool = false) -> void:
	if not alive or _layout == null or _layout.count(ANIM_ATTACK) == 0:
		return
	if _attack_time >= 0.0 or _since_attack < ATTACK_REST:
		return
	_attack_anim = ANIM_CAST if cast and _layout.count(ANIM_CAST) > 0 else ANIM_ATTACK
	_attack_time = 0.0
	_hurt_time = -1.0
	_face(direction, true)


func is_attacking() -> bool:
	return _attack_time >= 0.0


## Свет героя (LightMap): павший — призрак — светит слабее.
func light_scale() -> float:
	return 1.0 if alive else DataRegistry.VISUAL.ghost_light_share


func _unhandled_input(event: InputEvent) -> void:
	if is_multiplayer_authority() and event.is_action_pressed(&"drink_potion") and not _input_blocked():
		get_viewport().set_input_as_handled()
		_world.economy.submit_drink()


func _input_blocked() -> bool:
	return _world != null and _world.input_blocked()


func peer_id() -> int:
	return get_multiplayer_authority()


func set_camera_limits(bounds: Rect2i) -> void:
	camera.limit_left = bounds.position.x
	camera.limit_top = bounds.position.y
	camera.limit_right = bounds.end.x
	camera.limit_bottom = bounds.end.y


# --- Улучшения (хост) ---

func get_upgrade_level(id: StringName) -> int:
	return upgrade_levels.get(id, 0)


## levels — сколько уровней даёт карта (редкость, UpgradePool.Rarity); не выше max_level.
## Эволюция заменяет базовый навык, берёт его уровень, руны (те, что ей подходят) и ступени эволюции —
## превращение само ступень (UpgradeRules.evolution_transform_stage).
## Новый навык меняет резонансы (Synergies), поэтому характеристики пересчитываются после любой карты.
func apply_upgrade(upgrade: UpgradeData, levels: int = 1) -> void:
	var passive := upgrade as PassiveData
	if passive != null and passive.stat == STAT_HEAL:
		heal(max_health * passive.per_level * levels)
		return
	if passive != null and passive.stat == STAT_GOLD:
		gold += roundi(passive.per_level * levels * DataRegistry.ECONOMY.gold_mult(GameState.level_index))
		return
	var skill_data := upgrade as SkillData
	var level := get_upgrade_level(upgrade.id)
	var new_level := level + levels
	if skill_data != null and skill_data.is_evolution and level == 0:
		var base := DataRegistry.evolution_base(skill_data.id)
		new_level = maxi(get_upgrade_level(base.id), 1) if base != null else 1
		var carried: Array = runes.get(base.id, []) if base != null else []
		var stage := evolution_stage(base.id) if base != null else 0
		_remove_skill(base)
		for rune_id: StringName in carried:
			add_rune(skill_data.id, rune_id)
		evolution_stages[skill_data.id] = maxi(stage + 1, DataRegistry.UPGRADE_RULES.evolution_transform_stage)
	if upgrade.max_level > 0:
		new_level = mini(new_level, upgrade.max_level)
	upgrade_levels[upgrade.id] = new_level
	if skill_data != null:
		_set_skill_level(skill_data, new_level)
	_recalculate_stats()


func _set_skill_level(data: SkillData, new_level: int) -> void:
	for skill in _skills:
		if skill.data == data:
			skill.level = new_level
			return
	_skills.append(SkillRuntime.new(data, new_level))


## Навыки героя на хосте (для проверок и стенда).
func skills() -> Array[SkillRuntime]:
	return _skills


## Модификаторы сверх встроенных, которые действуют на навык data: черта класса, руны забега на этом
## навыке и легендарные руны надетых предметов (шаг 7). Подходят ли они навыку, решает SkillStats.fits.
func skill_modifiers(data: SkillData) -> Array:
	var result: Array = hero.class_modifiers.duplicate()
	for id: StringName in runes.get(data.id, []):
		var rune := DataRegistry.skill_modifier(id)
		if rune != null:
			result.append(rune)
	for item: Dictionary in equipment.values():
		var unique := ItemRoller.legendary(item)
		if unique != null and unique.modifier != null:
			result.append(unique.modifier)
	return result


## Хост: вставить руну rune_id в навык skill_id (карта руны в левел-апе, шаг 4; эволюция переносит руны).
## false — нет такой руны или навыка, руна не подходит навыку (теги, действие), уже вставлена или гнёзда
## заняты (UpgradePool.can_socket, ФТ-16). Руна с тегом (Руна огня) меняет резонансы — характеристики
## пересчитываются; числа навыка SkillStats соберёт при следующем срабатывании.
func add_rune(skill_id: StringName, rune_id: StringName) -> bool:
	var rune := DataRegistry.skill_modifier(rune_id)
	var skill := DataRegistry.upgrade(skill_id) as SkillData
	if not UpgradePool.can_socket(rune, skill, runes):
		return false
	var list: Array = runes.get(skill_id, []).duplicate()
	list.append(rune_id)
	runes[skill_id] = list
	_recalculate_stats()
	return true


func evolution_stage(skill_id: StringName) -> int:
	return int(evolution_stages.get(skill_id, 0))


## Хост: карта ступени эволюции навыка skill_id (UpgradePool.evolution_card). false — навыка нет, он не дорос
## до ступени, ступени кончились или эта ступень — превращение в облик (его даёт карта облика, apply_upgrade;
## без превращения — только если облик закрыт в профиле), ФТ-16.
func add_evolution_stage(skill_id: StringName) -> bool:
	var skill := DataRegistry.upgrade(skill_id) as SkillData
	if skill == null:
		return false
	var card := UpgradePool.evolution_card(skill, get_upgrade_level(skill_id), evolution_stage(skill_id), upgrade_levels)
	if card == &"":
		return false
	if card != UpgradePool.evolution_card_id(skill_id) and not card in locked_skills:
		return false
	evolution_stages[skill_id] = evolution_stage(skill_id) + 1
	return true


## Эволюция заменяет базовый навык: он уходит из слотов, из пула карт и забирает свои руны и ступени.
func _remove_skill(base: SkillData) -> void:
	if base == null:
		return
	upgrade_levels.erase(base.id)
	runes.erase(base.id)
	evolution_stages.erase(base.id)
	for i in range(_skills.size() - 1, -1, -1):
		if _skills[i].data == base:
			_skills.remove_at(i)


func stat(id: StringName) -> float:
	return _stats.get(id, 0.0)


## Характеристика для удара с тегами tags (маска DataRegistry.tag_mask): общая + «по тегу» («might:fire»).
func stat_for(id: StringName, tags: int) -> float:
	var value := stat(id)
	if tags != 0 and _scoped.has(id):
		for entry: Array in _scoped[id]:
			if tags & int(entry[0]):
				value += float(entry[1])
	return value


## Действующее значение с пределом из StatDef (Уклонение не больше 50 % и т. п.).
func capped(id: StringName) -> float:
	var def := DataRegistry.stat_def(id)
	return def.capped(stat(id)) if def != null else stat(id)


## Множитель урона для удара с тегами tags: Мощь (общая и по тегам), Лидерство, Ярость.
func damage_mult(tags: int = 0) -> float:
	var berserk := stat(STAT_BERSERK) if health < max_health * DataRegistry.BALANCE.berserk_threshold else 0.0
	return 1.0 + stat_for(STAT_MIGHT, tags) + _leadership_bonus() + berserk


## Множитель удачного удара: ×2 (BalanceConfig) и Сокрушение сверху.
func crit_mult(tags: int = 0) -> float:
	return DataRegistry.BALANCE.crit_mult + stat_for(STAT_CRIT_DAMAGE, tags)


func cooldown_mult() -> float:
	return maxf(DataRegistry.BALANCE.min_cooldown_mult, 1.0 - stat(STAT_HASTE))


func pickup_radius() -> float:
	return DataRegistry.BALANCE.base_pickup_radius * (1.0 + stat(STAT_MAGNET))


func area_mult() -> float:
	return 1.0 + stat(STAT_AREA)


func extra_amount() -> int:
	return int(stat(STAT_AMOUNT))


## Хост: удачный ли удар (Удача, HoMM3) — двойной урон. bonus — прибавка навыка (модификаторы).
func roll_crit(tags: int = 0, bonus: float = 0.0) -> bool:
	var chance := stat_for(STAT_CRIT, tags) + bonus
	return chance > 0.0 and rng.randf() < chance


## Хост: удар навыка героя (шаги 2–3). base — урон навыка; Мощь, Ярость, Лидерство и удача — здесь,
## сопротивления и уязвимость врага — в Enemy.take_hit. crit_bonus — удача от модификаторов навыка.
func make_hit(base: float, tags: int, statuses: Array = [], crit_bonus: float = 0.0) -> HitInfo:
	var crit := roll_crit(tags, crit_bonus)
	var amount := base * damage_mult(tags) * (crit_mult(tags) if crit else 1.0)
	return HitInfo.make(amount, peer_id(), tags, crit, statuses)


## Лидерство действует на союзников Рыцаря (DESIGN 1); талант «Знамя полководца» усиливает ауру
## и распространяет её прибавку на самого Рыцаря.
func _leadership_bonus() -> float:
	if _world == null:
		return 0.0
	var best := stat(STAT_LEADERSHIP) if hero.passive == PASSIVE_LEADERSHIP else 0.0
	for other in _world.get_players():
		if other != self and other.alive and other.hero.passive == PASSIVE_LEADERSHIP \
				and global_position.distance_to(other.global_position) <= LEADERSHIP_RADIUS:
			best = maxf(best, LEADERSHIP_BONUS + other.stat(STAT_LEADERSHIP))
	return best


## Хост: таланты класса из хаба — постоянная прибавка к характеристикам на весь забег.
## Ранги приходят от владельца, поэтому ограничиваются данными; чужие таланты не действуют.
func _apply_talents() -> void:
	var stats := {}
	for id in talents:
		var talent := DataRegistry.talent(StringName(str(id)))
		if talent == null or not talent.fits(hero):
			continue
		var value := talent.per_rank * clampi(int(talents[id]), 0, talent.max_rank)
		match talent.stat:
			TalentData.START_GOLD:
				gold += roundi(value)
			TalentData.WEAPON_MASTERY:
				pass  # стартовое оружие берёт UpgradeSystem
			_:
				stats[talent.stat] = stats.get(talent.stat, 0.0) + value
	if not stats.is_empty():
		bonuses[&"talents"] = stats
		_recalculate_stats()


## Сумма талантов героя с этой характеристикой (с учётом предела рангов).
func talent_value(talent_stat: StringName) -> float:
	var total := 0.0
	for id in talents:
		var talent := DataRegistry.talent(StringName(str(id)))
		if talent != null and talent.fits(hero) and talent.stat == talent_stat:
			total += talent.per_rank * clampi(int(talents[id]), 0, talent.max_rank)
	return total


## Сводка характеристик из всех источников: пассивки, резонансы навыков (шаг 4), экипировка, реликвии
## и таланты, баффы. Чистая функция: на клиенте лист героя считает её сам из синхронизированных источников.
func collect_stats() -> Dictionary:
	var result := {}
	for id: StringName in upgrade_levels:
		var passive := DataRegistry.upgrade(id) as PassiveData
		if passive != null:
			_sum_into(result, passive.stat, passive.per_level * upgrade_levels[id])
			for extra in passive.bonus_stats:
				_sum_into(result, StringName(str(extra)), float(passive.bonus_stats[extra]) * upgrade_levels[id])
	_sum_dict_into(result, Synergies.stats(upgrade_levels, runes))
	_sum_dict_into(result, item_stats)  # все подобранные предметы; кукла (equipment) их не дублирует
	for bonus: Dictionary in bonuses.values():
		_sum_dict_into(result, bonus)
	for buff: Dictionary in buffs.values():
		_sum_dict_into(result, buff["stats"])
	return result


## Характеристики для показа: на хосте — действующие, на клиенте — посчитанные заново.
func stats_snapshot() -> Dictionary:
	return _stats if multiplayer.is_server() else collect_stats()


static func _sum_into(target: Dictionary, id: StringName, value: float) -> void:
	target[id] = float(target.get(id, 0.0)) + value


static func _sum_dict_into(target: Dictionary, stats: Dictionary) -> void:
	for id in stats:
		_sum_into(target, StringName(str(id)), float(stats[id]))


func _recalculate_stats() -> void:
	_stats = collect_stats()
	_scoped.clear()
	for id: StringName in _stats:
		var key := String(id)
		var colon := key.find(":")
		if colon < 0:
			continue
		var bit := DataRegistry.tag_bit(StringName(key.substr(colon + 1)))
		if bit != 0:
			var base := StringName(key.left(colon))
			if not _scoped.has(base):
				_scoped[base] = []
			_scoped[base].append([bit, float(_stats[id])])
	var new_max := maxf(hero.max_health + stat(STAT_MAX_HEALTH), 1.0)  # проклятия не опускают максимум ниже 1
	health = clampf(health + new_max - max_health, 1.0, new_max)  # прибавка к максимуму сразу лечит
	max_health = new_max
	max_mana = hero.max_mana + stat(STAT_MAX_MANA)
	mana = minf(mana, max_mana)
	move_speed = hero.move_speed * (1.0 + stat(STAT_SWIFTNESS))


# --- Баффы и реликвии (хост) ---

## Временное усиление (фонтан, CR-06). Повторное — обновляет время.
func add_buff(id: StringName, duration: float, stats: Dictionary) -> void:
	buffs[id] = {"time": duration, "stats": stats}
	_recalculate_stats()


## Постоянный бонус до конца забега (Грааль).
func add_bonus(id: StringName, stats: Dictionary) -> void:
	bonuses[id] = stats
	_recalculate_stats()


func _tick_resources(delta: float) -> void:
	if stat(STAT_WARD) > 0.0 and not ward_ready:
		_ward_timer -= delta
		if _ward_timer <= 0.0:
			ward_ready = true
	if stat(STAT_REGEN) > 0.0:
		heal(stat(STAT_REGEN) * delta)
	elif stat(STAT_REGEN) < 0.0 and alive:  # проклятие «Гниение» (шаг 7): здоровье тает, но не убивает
		health = maxf(health + stat(STAT_REGEN) * delta, minf(health, 1.0))
	if max_mana > 0.0:
		mana = minf(max_mana, mana + hero.mana_regen * delta)
	if buffs.is_empty():
		return
	var expired := false
	for id: StringName in buffs.keys():
		buffs[id]["time"] -= delta
		if buffs[id]["time"] <= 0.0:
			buffs.erase(id)
			expired = true
	if expired:
		_recalculate_stats()


# --- Экипировка (хост) ---

## Сумки нет — предмет можно подобрать всегда (лишь бы он был цел).
func can_receive(item: Dictionary) -> bool:
	return ItemRoller.is_valid(item)


## Подобрать предмет: его характеристики навсегда прибавляются (item_stats), на кукле остаётся лучший предмет слота
## (не ниже редкостью — ITEM_RANK: легендарный с руной не вытесняется). Кольцо — на свободный палец или вместо
## слабейшего из двух (doll_slot_for). false — предмет испорчен.
func receive_item(item: Dictionary) -> bool:
	if not ItemRoller.is_valid(item):
		return false
	var stats := item_stats.duplicate()
	_sum_dict_into(stats, item["stats"])
	item_stats = stats  # новый словарь — синхронизатор замечает изменение
	items_collected += 1
	var slot := doll_slot_for(item)
	if not equipment.has(slot) or ItemRoller.rank(item) >= ItemRoller.rank(equipment[slot]):
		equipment[slot] = item
	_recalculate_stats()
	Events.inventory_changed.emit(peer_id())
	return true


## Ячейка куклы для предмета: слот его базы, а кольцу — свободный палец (сначала RING), если оба заняты — палец
## со слабейшим кольцом (при равенстве — второй: первое кольцо остаётся).
func doll_slot_for(item: Dictionary) -> int:
	var slot := ItemRoller.slot_of(item)
	if slot != ItemBaseData.Slot.RING:
		return slot
	for finger in [ItemBaseData.Slot.RING, ItemBaseData.Slot.RING_2]:
		if not equipment.has(finger):
			return finger
	var first := ItemRoller.rank(equipment[ItemBaseData.Slot.RING])
	var second := ItemRoller.rank(equipment[ItemBaseData.Slot.RING_2])
	return ItemBaseData.Slot.RING if first < second else ItemBaseData.Slot.RING_2


# --- Золото и зелья (хост, CR-14) ---

## Подобранное золото с бонусом «Алчности»; дробная часть копится. Возвращает, сколько прибавилось.
func earn_gold(amount: float) -> int:
	_gold_carry += amount * (1.0 + stat(STAT_GOLD_GAIN))
	var whole := floori(_gold_carry)
	_gold_carry -= whole
	gold += whole
	return whole


## false — золота не хватает, ничего не списано.
func spend_gold(price: int) -> bool:
	if price < 0 or gold < price:
		return false
	gold -= price
	return true


func drink_potion() -> bool:
	if not alive or potions <= 0 or health >= max_health:
		return false
	potions -= 1
	heal(max_health * DataRegistry.BALANCE.potion_heal)
	return true


# --- Здоровье (хост) ---

## attacker — враг, ударивший вплотную (ему отвечают «Шипы»); null — снаряд или взрыв.
## Порядок: уклонение → оберег (поглощает удар целиком) → мана-щит → стойкость (доля) → броня (число),
## но не меньше BalanceConfig.min_damage_taken. Пределы Уклонения и Стойкости — StatDef.cap.
## Смертельный удар снимает заряд Второго дыхания, если он есть.
## by_level — урон растёт с уровнем героя (BalanceConfig.damage_taken_mult); false — урон среды (доля здоровья).
func take_damage(amount: float, attacker: Enemy = null, by_level: bool = true) -> void:
	if not alive or invulnerable or not multiplayer.is_server():
		return
	var balance := DataRegistry.BALANCE
	if by_level:
		amount *= balance.damage_taken_mult(level)
	if stat(STAT_DODGE) > 0.0 and rng.randf() < capped(STAT_DODGE):
		return
	if attacker != null and stat(STAT_THORNS) > 0.0:
		attacker.take_damage(stat(STAT_THORNS) * damage_mult(), peer_id(), false, RunStats.SOURCE_THORNS)
	if ward_ready:
		ward_ready = false
		_ward_timer = ward_interval()
		Events.ward_blocked.emit(peer_id())
		return
	if hero.passive == PASSIVE_MANA_SHIELD and mana > 0.0:
		var share := minf(MANA_SHIELD_SHARE + stat(STAT_MANA_SHIELD), MAX_MANA_SHIELD)
		var absorbed := minf(amount * share, mana)
		mana -= absorbed
		amount -= absorbed
	amount *= 1.0 - capped(STAT_RESILIENCE)
	var lost := minf(maxf(amount - stat(STAT_ARMOR), balance.min_damage_taken), max_health * balance.max_hit_share)
	lost = minf(lost, maxf(health, 0.0))
	health -= lost
	if _world != null:
		_world.run_stats.record_taken(peer_id(), lost)
	flash_hit()
	if health > 0.0:
		return
	if revivals_left() > 0:
		revivals_used += 1
		health = max_health * balance.revival_health
		Events.second_wind.emit(peer_id())
		return
	health = 0.0
	alive = false
	Events.player_died.emit(peer_id())


## Хост: холод Ледяной элиты — замедление на CHILL_TIME с (у владельца — через синхронизацию chills).
func chill() -> void:
	if alive and not invulnerable and multiplayer.is_server():
		chills += 1


func is_chilled() -> bool:
	return _chill_left > 0.0


## Второе дыхание: сколько раз ещё герой встанет в этом забеге.
func revivals_left() -> int:
	return maxi(int(stat(STAT_REVIVAL)) - revivals_used, 0)


## Секунд до нового заряда Оберега.
func ward_interval() -> float:
	return DataRegistry.BALANCE.ward_interval * (1.0 - capped(STAT_WARD))


## Лечение героя; печать иссушения (шаг 12.3) его урезает.
func heal(amount: float) -> void:
	if alive:
		health = minf(health + amount * RunConfig.seal_mult(SealData.Stat.HEAL), max_health)


## Хост: навык героя нанёс урон (Вампиризм героя + Вампиризм навыка extra).
func on_hit_dealt(amount: float, extra: float = 0.0) -> void:
	var share := stat(STAT_LIFESTEAL) + extra
	if share > 0.0:
		heal(amount * share)


## share — доля здоровья: новый уровень — полное, «Последний вздох» — половина (LastBreathSystem).
func revive(share: float = 1.0) -> void:
	alive = true
	health = max_health * share
	mana = max_mana
	revive_progress = 0.0


## Перенос на точку спавна нового уровня. Позицию ведёт владелец, поэтому для удалённого игрока
## game/net передаёт этот вызов RPC его владельцу.
func teleport(pos: Vector2) -> void:
	position = pos
	velocity = Vector2.ZERO
	camera.reset_smoothing()


## Вспышка и отскок назад от удара. У клиентов её вызывает WorldNet, когда здоровье из синхронизации уменьшилось.
## Свой герой (у владельца) ещё трясёт камеру и останавливает кадр (Juice, шаг 11.9).
func flash_hit() -> void:
	# Шаг 11.19: стоящий герой вздрагивает (кадры листа); на ходу и в ударе — только вспышка и отскок, иначе ноги
	# скользили бы по земле, пока идёт вздрагивание.
	if alive and _attack_time < 0.0 and _since_hurt >= HURT_COOLDOWN and _layout != null and _layout.count(ANIM_HURT) > 0:
		_hurt_time = 0.0
		_since_hurt = 0.0
	body.self_modulate = Color(1.0, 0.35, 0.3)
	var tween := create_tween().set_parallel()
	tween.tween_property(body, ^"self_modulate", Color.WHITE, 0.2)
	tween.tween_property(body, ^"position:x", 0.0, 0.15).from(HURT_RECOIL if body.flip_h else -HURT_RECOIL)
	if is_multiplayer_authority() and _world != null:
		_world.juice.hero_hurt()
		_world.sfx.play(&"hero_hurt")  # шаг 11.27: «у себя», без затухания


func _update_look() -> void:
	modulate = Color.WHITE if alive or _death_time >= 0.0 else Color(0.6, 0.7, 0.9, 0.4)  # падает — ещё не призрак
	queue_redraw()


## Кольцо над призраком: союзник рядом поднимает героя («Последний вздох»).
func _draw() -> void:
	if alive or revive_progress <= 0.0:
		return
	var center := Vector2(0, -8)
	draw_arc(center, 13.0, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 3.0)
	draw_arc(center, 13.0, -PI / 2.0, -PI / 2.0 + TAU * revive_progress, 24, REVIVE_RING, 2.0)
