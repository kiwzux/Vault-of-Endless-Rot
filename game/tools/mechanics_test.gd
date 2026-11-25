extends Node
## Проверка игрового ядра без участия человека: данные, карты левел-апа, лут и сквозной забег
## на тестовой арене — автоатака (ТК-08), волны и ровно 1 босс (ТК-09), 3 уникальные карты (ТК-10),
## ключ → портал → следующий уровень (ТК-07), пассивки героев, эволюции, объекты карты, элиты, тиры,
## круг из 3 уровней → финальный босс → порталы «Бесконечная гниль» / «Завершить забег», поражение.
## Золото, торговцы и пояс зелий (CR-14), новое оружие и переброс карт (CR-15), пауза по Esc,
## метки HUD на босса, Ключ и портал, полоски здоровья врагов.
## Запуск: godot --headless --path game res://tools/mechanics_test.tscn --fixed-fps 60 --quit-after 200000

const RANDOM_ROLLS := 2000
const LOOT_ROLLS := 300
const BALANCE_LOG := "user://test_balance_log.jsonl"
## Навыки шага 3 (новые действия) и шага 4 (ещё 10 навыков и эволюции навыков шага 3).
const STEP3_SKILLS: Array[StringName] = [&"silver_bolts", &"holy_water", &"bear_trap", &"fire_beam", &"flame_dash",
	&"oil_flask", &"blood_harvest", &"ghoul_pack", &"crimson_nova", &"shield_charge"]
const STEP4_SKILLS: Array[StringName] = [&"bone_legion", &"ice_beam", &"curse_chain", &"silver_net", &"fire_wall",
	&"blood_lance", &"heaven_smite", &"rot_totem", &"shadow_step", &"fire_orbs", &"iron_maw", &"blood_moon_scythe",
	&"blood_tide", &"dragon_breath", &"ash_walk", &"ghoul_horde", &"hallowed_ground", &"greek_fire",
	&"unstoppable_charge", &"silver_verdict"]

var _failures := 0
var _offers: Array = []
var _auto_pick := true
var _waves_started: Array[int] = []
var _bosses_spawned := 0
var _run_result := -1  # -1 — забег идёт, 0 — поражение, 1 — победа
var _run_choices := 0
var _items_picked: Array[Dictionary] = []
var _dropped_rarities: Array[int] = []
var _blasts := 0
var _coins := 0
var _crits := 0
var _world: World
## Снаряды врагов, появившиеся на уровне: [вид, позиция] — для проверок особых врагов.
var _hostile_shots: Array = []
var _challenges: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	BalanceLog.path = BALANCE_LOG  # журнал боёв тестового забега — не в настоящий журнал игрока
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BALANCE_LOG))
	_check_data()
	_check_combat_data()
	_check_upgrade_pool()
	_check_rune_pool()
	_check_loot_roller()
	_check_projectile_stream()
	Events.level_up_offered.connect(_on_level_up_offered)
	Events.wave_started.connect(func(index: int) -> void: _waves_started.append(index))
	Events.boss_spawned.connect(func(_boss: Node) -> void: _bosses_spawned += 1)
	Events.run_ended.connect(func(victory: bool) -> void: _run_result = 1 if victory else 0)
	Events.run_choice_offered.connect(func() -> void: _run_choices += 1)
	Events.item_picked.connect(func(_peer: int, item: Dictionary) -> void: _items_picked.append(item))
	Events.damage_dealt.connect(func(_pos: Vector2, _amount: float, crit: bool) -> void:
		if crit:
			_crits += 1)
	Events.challenge_finished.connect(func(kind: StringName, success: bool) -> void: _challenges.append([kind, success]))
	_check_meta_profile()
	await _check_run()
	await _check_defeat()
	print("Провалено проверок: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Данные ---

func _check_data() -> void:
	for list in [DataRegistry.ENEMIES, DataRegistry.UPGRADES, DataRegistry.ELITE_AFFIXES,
			DataRegistry.ITEM_BASES, DataRegistry.AFFIXES, DataRegistry.UNIQUE_ITEMS,
			DataRegistry.MERCHANTS, DataRegistry.GOODS, DataRegistry.TALENTS]:
		var ids := {}
		for item in list:
			_check(not ids.has(item.id), "id %s уникален" % item.id)
			ids[item.id] = true
	var in_waves := {}
	for biome: BiomeData in DataRegistry.BIOMES:
		var table := biome.waves
		_check(table.max_alive == 300, "биом %s: до 300 врагов одновременно (плотность ×2)" % biome.id)
		for wave in table.waves:
			for enemy in wave.enemies:
				in_waves[enemy.id] = true
	for id: StringName in [&"skeleton_crossbowman", &"death_rider", &"bloated_corpse", &"dark_priest", &"phantom_mage",
			&"efreet", &"pyromancer", &"succubus", &"rot_blob", &"plague_thrower",
			&"ghoul_wolf", &"rot_treant", &"drowned", &"water_wraith", &"burning_cleric", &"fallen_templar", &"void_eye",
			&"abyss_spawn"]:
		_check(in_waves.has(id), "особый враг %s есть в волнах" % id)
	# Враги по эскизам (tilesetver/enemys, 18.10.2026): все в волнах своих биомов, у каждого лист в атласе.
	var sketch_waves := {
		0: [&"bandit", &"rogue_archer", &"renegade_guard", &"rabid_wolf", &"plague_rat", &"cultist", &"swamp_slime",
				&"wild_boar", &"scarecrow", &"village_witch"],
		1: [&"skeleton_archer", &"vampire_bat", &"necro_acolyte", &"bone_spider", &"banshee", &"crypt_golem"],
		2: [&"fire_spirit", &"lava_slime", &"abyss_eye", &"demon_caster", &"cursed_soul", &"demon_brute",
				&"infernal_guard", &"devourer"],
	}
	for stage: int in sketch_waves:
		var own := {}
		for wave in DataRegistry.wave_table_for(stage).waves:
			for enemy in wave.enemies:
				own[enemy.id] = true
		var missing_ids: Array = sketch_waves[stage].filter(func(id: StringName) -> bool: return not own.has(id))
		_check(missing_ids.is_empty(), "этап %d: враги эскизов в его волнах (нет: %s)" % [stage + 1, missing_ids])
	var no_art: Array = []
	var bad_affix: Array = []
	for enemy: EnemyData in DataRegistry.ENEMIES:
		if not EnemyArt.has_sheet(enemy.id):
			no_art.append(enemy.id)
		for id in enemy.innate_affixes:
			if DataRegistry.elite_affix(id) == null:
				bad_affix.append("%s:%s" % [enemy.id, id])
		if enemy.split_count > 0 and DataRegistry.enemy(enemy.split_id) == null:
			bad_affix.append("%s→%s" % [enemy.id, enemy.split_id])
	_check(no_art.is_empty() and bad_affix.is_empty(),
			"у каждого врага лист в атласе (нет: %s), врождённые повадки и деление — из данных (ошибки: %s)" % [no_art, bad_affix])
	for hero: HeroData in DataRegistry.HEROES:
		var own := DataRegistry.talents_for(hero).filter(func(t: TalentData) -> bool: return not t.is_global())
		_check(own.size() == 5, "у героя %s 5 талантов класса" % hero.id)
	for talent: TalentData in DataRegistry.TALENTS:
		_check(talent.is_global() or DataRegistry.hero(talent.hero) != null, "талант %s принадлежит существующему герою" % talent.id)
	for merchant: MerchantData in DataRegistry.MERCHANTS:
		var goods_known := merchant.goods.all(func(g: GoodsData) -> bool: return DataRegistry.goods(g.id) == g)
		_check(goods_known and (merchant.item_count > 0 or not merchant.goods.is_empty()), "товар торговца %s в реестре" % merchant.id)
	var economy := DataRegistry.ECONOMY
	_check(economy.item_prices.size() == ItemRoller.Rarity.size() and economy.gamble_weights.size() == ItemRoller.Rarity.size(),
			"цены и веса свёртка заданы для каждой редкости")
	for hero: HeroData in DataRegistry.HEROES:
		_check(DataRegistry.upgrade(hero.starting_weapon) is SkillData, "стартовое оружие героя %s есть" % hero.id)
	_check(DataRegistry.HEROES[2].max_mana > 0.0, "у Чародейки есть мана для Мана-щита")

	_check(RunPlan.stages().size() == Palette.biomes().size(), "биомов в данных столько же, сколько в палитре (cond CVAE)")
	for i in DataRegistry.BIOMES.size():
		var biome: BiomeData = DataRegistry.BIOMES[i]
		var stage := biome.id
		_check(Palette.biomes()[i] == String(stage), "этап %d — биом палитры %s (условие CVAE)" % [i, stage])
		_check(biome.final_lair == (i == DataRegistry.BIOMES.size() - 1) and biome.objects != null,
				"биом %s: логово — только последний этап, правила слоя объектов заданы" % stage)
		var table := biome.waves
		_check(table != null and table.boss != null and table.boss.is_boss, "у биома %s есть босс" % stage)
		for wave in table.waves:
			_check(wave.start_time < wave.end_time and wave.interval > 0.0 and wave.batch > 0
					and not wave.enemies.is_empty() and wave.enemies.size() == wave.weights.size(),
					"волна %s %.0f–%.0f корректна" % [stage, wave.start_time, wave.end_time])
	_check(DataRegistry.wave_table_for(2).boss.id == &"archdemon", "босс Пылающего собора — Архидемон")
	_check(DataRegistry.wave_table_for(3).boss.id == &"pit_lord", "финальный босс — Владыка Бездны")
	var stage_health := range(4).map(func(i: int) -> float: return DataRegistry.wave_table_for(i).boss.max_health)
	_check(range(3).all(func(i: int) -> bool: return stage_health[i] < stage_health[i + 1]),
			"боссы круга крепче от этапа к этапу, финальный — сильнейший: %s" % [stage_health])
	_check(RunPlan.final_biome_index() == 3 and RunPlan.biome_key(3) == "BIOME_ABYSS", "логово — Бездна")

	for enemy: EnemyData in DataRegistry.ENEMIES:
		if enemy.upgrade != null:
			_check(DataRegistry.enemy(enemy.upgrade.id) != null and enemy.upgrade.upgrade == null,
					"тир %s → %s есть в реестре (CR-09)" % [enemy.id, enemy.upgrade.id])
		if enemy.summon_count > 0:
			_check(DataRegistry.enemy(enemy.summon_id) != null, "подручные босса %s есть" % enemy.id)
	for upgrade in DataRegistry.UPGRADES:
		if upgrade is SkillData and upgrade.evolution != null:
			_check(upgrade.evolution.is_evolution and upgrade.evolution.max_level == upgrade.max_level,
					"эволюция %s → %s задана" % [upgrade.id, upgrade.evolution.id])

	_check(RunPlan.stage(2) == 2 and not RunPlan.is_final(2) and RunPlan.is_final(3), "3 уровня, затем логово")
	_check(RunPlan.stage(4) == 0 and RunPlan.cycle(4) == 1 and RunPlan.is_final(7), "бесконечный режим — новый круг")
	_check(Player.xp_to_next(1) > 0 and Player.xp_to_next(10) > Player.xp_to_next(9), "кривая опыта растёт")
	var to_twenty := 0
	for level in range(1, 20):
		to_twenty += Player.xp_to_next(level)
	_check(to_twenty < 1805, "прокачка быстрее прежней: до 20-го уровня %d опыта (было 1805)" % to_twenty)


## Шаг 2: каталог данных собирается из папок; у каждой характеристики есть StatDef; теги, статусы
## и реакции ссылаются на существующие данные; характеристика «по тегу» и проверка предметов из сети.
func _check_combat_data() -> void:
	_check(DataRegistry.HEROES.size() == 6 and DataRegistry.HEROES[0].id == &"knight"
			and DataRegistry.HEROES[1].id == &"necromancer" and DataRegistry.HEROES[2].id == &"sorceress"
			and DataRegistry.HEROES[5].id == &"blood_priest",
			"каталог: 6 классов в порядке показа (HeroData.order)")
	_check(DataRegistry.TALENTS.size() == 33 and DataRegistry.TALENTS[0].id == &"inheritance"
			and DataRegistry.TALENTS[2].id == &"soul_mending" and DataRegistry.TALENTS[3].id == &"knight_vigor"
			and DataRegistry.TALENTS[17].id == &"sorc_shield",
			"каталог: таланты в порядке показа (TalentData.order)")
	_check(DataRegistry.UPGRADES.size() == 91 and DataRegistry.ENEMIES.size() == 72 and DataRegistry.AFFIXES.size() == 29
			and DataRegistry.BIOMES.size() == RunPlan.stages().size(),
			"каталог собрал все данные из папок: карт %d, врагов %d" % [DataRegistry.UPGRADES.size(), DataRegistry.ENEMIES.size()])
	var crypt := load("res://data/waves/flooded_crypt.tres") as WaveTable
	_check(crypt != null and crypt.boss != null and crypt.boss.id == &"lich_king" and crypt.boss.is_boss
			and EnemyArt.has_sheet(&"lich_king") and EnemyArt.sheet(&"lich_king").count(&"attack") == 16
			and EnemyArt.sheet(&"lich_king").count(&"walk") == 16,
			"босс Затопленного склепа — Король-лич (лист в атласе врагов, 16 кадров ходьбы и удара)")
	_check(DataRegistry.upgrade(&"fireball") is SkillData and DataRegistry.upgrade(&"upgrade_rules") == null,
			"каталог берёт только ресурсы своего класса")

	var missing: Array = []
	var not_on_items: Array = []
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		var passive := upgrade as PassiveData
		if passive == null or passive.stat in [Player.STAT_HEAL, Player.STAT_GOLD]:
			continue
		for stat: StringName in [passive.stat] + passive.bonus_stats.keys().map(func(k: Variant) -> StringName: return StringName(str(k))):
			if DataRegistry.stat_def(stat) == null:
				missing.append(stat)
	for talent: TalentData in DataRegistry.TALENTS:
		if talent.stat not in [TalentData.START_GOLD, TalentData.WEAPON_MASTERY] and DataRegistry.stat_def(talent.stat) == null:
			missing.append(talent.stat)
	var item_stats: Array = []
	for base: ItemBaseData in DataRegistry.ITEM_BASES:
		item_stats.append(base.implicit_stat)
	for affix: AffixData in DataRegistry.AFFIXES:
		item_stats.append(affix.stat)
	for unique: UniqueItemData in DataRegistry.UNIQUE_ITEMS:
		item_stats.append_array(unique.stats.keys())
	for stat: Variant in item_stats:
		var def := DataRegistry.stat_def(StringName(str(stat)))
		if def == null:
			missing.append(stat)
		elif not def.on_items:
			not_on_items.append(stat)
	_check(missing.is_empty(), "у каждой характеристики пассивок, талантов и предметов есть StatDef %s" % [missing])
	_check(not_on_items.is_empty(), "характеристики предметов помечены on_items %s" % [not_on_items])
	_check(DataRegistry.stat_def(&"dodge").capped(0.9) == 0.5 and DataRegistry.stat_def(&"execute").cap > 0.0,
			"пределы характеристик — в StatDef")

	var bits := {}
	for tag: TagDef in DataRegistry.TAGS:
		var bit := DataRegistry.tag_bit(tag.id)
		_check(bit != 0 and not bits.has(bit), "тег %s: свой бит маски" % tag.id)
		bits[bit] = true
	var bad_refs: Array = []
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		var weapon := upgrade as SkillData
		if weapon == null:
			continue
		if weapon.tags.is_empty() or DataRegistry.tag_mask(weapon.tags) == 0:
			bad_refs.append(weapon.id)
		for app: StatusApplication in weapon.on_hit:
			if DataRegistry.status(app.status) == null:
				bad_refs.append("%s→%s" % [weapon.id, app.status])
	for reaction: StatusReaction in DataRegistry.STATUS_REACTIONS:
		for id: StringName in [reaction.requires, reaction.trigger]:
			if DataRegistry.status(id) == null:
				bad_refs.append(reaction.id)
		if reaction.apply_status != &"" and DataRegistry.status(reaction.apply_status) == null:
			bad_refs.append(reaction.id)
	_check(bad_refs.is_empty(), "у оружия есть теги, статусы и реакции ссылаются на существующие данные %s" % [bad_refs])
	_check(DataRegistry.STATUSES.size() >= 10 and DataRegistry.STATUS_REACTIONS.size() >= 3,
			"статусов %d, реакций %d" % [DataRegistry.STATUSES.size(), DataRegistry.STATUS_REACTIONS.size()])
	_check(DataRegistry.upgrade(&"frost_ring").on_hit[0].status == &"chill"
			and DataRegistry.upgrade(&"acid_rain").on_hit.any(func(a: StatusApplication) -> bool: return a.status == &"slow"),
			"замедление оружия перенесено в статусы (холод, замедление)")

	_check(DataRegistry.stat_def(&"might:fire") == DataRegistry.stat_def(&"might") and DataRegistry.stat_def(&"might:nope") == null,
			"характеристика «по тегу» берёт описание базовой; неизвестный тег отклоняется")
	_check(ItemRoller.stat_line(&"might:fire", 0.1).contains(tr("TAG_FIRE")), "строка характеристики по тегу: %s" % ItemRoller.stat_line(&"might:fire", 0.1))
	_check(ItemRoller.is_valid({"base": &"helm", "rarity": 1, "stats": {&"might:fire": 0.1}})
			and not ItemRoller.is_valid({"base": &"helm", "rarity": 1, "stats": {&"execute": 0.1}}),
			"предмет из сети: характеристика по тегу допустима, характеристика не с предметов — нет")
	var tint := DataRegistry.status_tint(1 << DataRegistry.status(&"burn").visual_bit)
	_check(tint == DataRegistry.status(&"burn").color and DataRegistry.status_tint(0) == Color.WHITE,
			"оттенок статуса по флагам снимка")


## ТК-10: при любом состоянии героя — ровно 3 уникальные допустимые карты; эволюции — по условию.
func _check_upgrade_pool() -> void:
	_check(UpgradePool.filler_count() >= UpgradePool.CARD_COUNT, "запасных карт хватает на гарантию ФТ-10")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rules := DataRegistry.UPGRADE_RULES
	var bad := 0
	var stage_cards := 0
	for i in RANDOM_ROLLS:
		var levels := {}
		var stages := {}
		for upgrade: UpgradeData in DataRegistry.UPGRADES:
			var evolution: bool = upgrade is SkillData and upgrade.is_evolution
			if upgrade.kind != UpgradeData.Kind.FILLER and not evolution and rng.randf() < 0.5:
				levels[upgrade.id] = rng.randi_range(1, upgrade.max_level)
				if upgrade is SkillData:  # у навыка с обликом ступень II — уже превращение, базового навыка там нет
					@warning_ignore("integer_division")
					var reached: int = levels[upgrade.id] / rules.evolution_step
					var top := rules.evolution_transform_stage - 1 if upgrade.evolution != null else rules.evolution_stages
					stages[upgrade.id] = rng.randi_range(0, mini(reached, top))
		var cards := UpgradePool.roll(levels, rng, {}, [], UpgradePool.CARD_COUNT, 0, stages)
		var unique := {}
		var evolutions := 0
		for id in cards:
			unique[id] = true
			var evolving := UpgradePool.parse_evolution_card(id)
			if evolving != &"":
				evolutions += 1
				stage_cards += 1
				var skill := DataRegistry.upgrade(evolving) as SkillData
				var stage: int = stages.get(evolving, 0)
				if skill == null or levels.get(evolving, 0) < rules.evolution_step * (stage + 1) \
						or UpgradePool.is_transform(skill, stage + 1):
					bad += 1
				continue
			var upgrade := DataRegistry.upgrade(id)
			if upgrade == null or upgrade.is_maxed(levels.get(id, 0)):
				bad += 1
			elif upgrade is SkillData and upgrade.is_evolution:
				evolutions += 1
				var base := DataRegistry.evolution_base(id)
				var stage: int = stages.get(base.id, 0)
				if levels.get(base.id, 0) < rules.evolution_step * (stage + 1) or not UpgradePool.is_transform(base, stage + 1):
					bad += 1
		if cards.size() != 3 or unique.size() != 3 or evolutions > rules.evolution_cards_per_offer:
			bad += 1
	_check(bad == 0 and stage_cards > 0,
			"%d случайных состояний: всегда 3 уникальные допустимые карты, ступеней эволюции не больше %d (ошибок %d)"
			% [RANDOM_ROLLS, rules.evolution_cards_per_offer, bad])

	var maxed := {}
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		if upgrade.kind != UpgradeData.Kind.FILLER and not (upgrade is SkillData and upgrade.is_evolution):
			maxed[upgrade.id] = upgrade.max_level
	var maxed_cards := UpgradePool.roll(maxed, rng)
	_check(maxed_cards.size() == 3 and maxed_cards.filter(func(id: StringName) -> bool:
			return UpgradePool.parse_evolution_card(id) != &"").size() == rules.evolution_cards_per_offer,
			"всё прокачано — в предложении ступень эволюции и запасные карты: %s" % [maxed_cards])

	# Ступени эволюции (каждые 5 уровней навыка, 4 ступени, ступень II — превращение в облик), без пассивки
	# и не дожидаясь, пока всё вкачано.
	var sword: SkillData = DataRegistry.upgrade(&"sword_arc")
	var step := rules.evolution_step
	var stage_one := 0
	var transform := 0
	var stage_three := 0
	var leaked := 0
	for i in 50:
		stage_one += int(&"evo:sword_arc" in UpgradePool.roll({&"sword_arc": step, &"bone_arrow": 1}, rng))
		transform += int(&"whirling_blades" in UpgradePool.roll({&"sword_arc": 2 * step}, rng, {}, [], 3, 0, {&"sword_arc": 1}))
		stage_three += int(&"evo:whirling_blades" in UpgradePool.roll({&"whirling_blades": 3 * step}, rng, {}, [], 3, 0,
				{&"whirling_blades": 2}))
		var early := UpgradePool.roll({&"sword_arc": step - 1, &"might": 1}, rng)
		var skipped := UpgradePool.roll({&"sword_arc": 2 * step}, rng)  # ступень I не взята — превращения ещё нет
		var waiting := UpgradePool.roll({&"whirling_blades": 3 * step - 1}, rng, {}, [], 3, 0, {&"whirling_blades": 2})
		var done := UpgradePool.roll({&"whirling_blades": sword.max_level}, rng, {}, [], 3, 0, {&"whirling_blades": 4})
		var after := UpgradePool.roll({&"whirling_blades": 2 * step}, rng, {}, [], 3, 0, {&"whirling_blades": 2})
		if early.any(func(id: StringName) -> bool: return UpgradePool.parse_evolution_card(id) != &"") \
				or &"whirling_blades" in skipped or not &"evo:sword_arc" in skipped \
				or waiting.any(func(id: StringName) -> bool: return UpgradePool.parse_evolution_card(id) != &"") \
				or done.any(func(id: StringName) -> bool: return UpgradePool.parse_evolution_card(id) != &"") \
				or &"sword_arc" in after:
			leaked += 1
	_check(stage_one == 50 and transform == 50 and stage_three == 50,
			"ступени эволюции в каждом предложении: I на %d ур., II — превращение в «Вихрь клинков», III на %d ур."
			% [step, 3 * step])
	_check(leaked == 0, "до %d ур. ступени нет, превращение — только после ступени I, после IV ступеней нет; меч после эволюции не выпадает" % step)
	_check(UpgradePool.parse_evolution_card(&"evo:sword_arc") == &"sword_arc" and UpgradePool.parse_evolution_card(&"evo:") == &""
			and UpgradePool.parse_evolution_card(&"might") == &"" and UpgradePool.stage_name(2) == "II",
			"карта ступени: id «evo:<навык>», мусорный id отклоняется")
	_check(sword.max_level == 20 and DataRegistry.upgrade(&"might").max_level == 25, "у навыков до 20 уровней, у пассивок до 25")
	var not_twenty := DataRegistry.UPGRADES.filter(func(u: UpgradeData) -> bool: return u is SkillData and u.max_level != 20)
	_check(not_twenty.is_empty(), "все навыки до 20 уровня %s" % [not_twenty.map(func(u: UpgradeData) -> StringName: return u.id)])

	# Пассивки слотов не занимают: все слоты оружия заняты — новое оружие не предлагается, пассивки — да.
	var full := {}
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		var evolution: bool = upgrade is SkillData and upgrade.is_evolution
		if upgrade.kind == UpgradeData.Kind.WEAPON and not evolution and full.size() < DataRegistry.UPGRADE_RULES.max_weapons:
			full[upgrade.id] = 1
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		if upgrade.kind == UpgradeData.Kind.PASSIVE:
			full[upgrade.id] = 1
	var new_weapon := false
	var passive_offered := false
	for i in 200:
		for id in UpgradePool.roll(full, rng):
			var upgrade := DataRegistry.upgrade(id)
			new_weapon = new_weapon or (upgrade.kind == UpgradeData.Kind.WEAPON and not full.has(id))
			passive_offered = passive_offered or upgrade.kind == UpgradeData.Kind.PASSIVE
	_check(not new_weapon and passive_offered, "слоты оружия заняты — новое оружие не выпадает, пассивки выпадают")

	# Редкость карт: обычные — большинство, легендарные — редко; лишних уровней сверх 25 не даёт.
	var counts := [0, 0, 0, 0]
	var lucky_rare := 0
	var might := DataRegistry.upgrade(&"might")
	for i in 4000:
		counts[UpgradePool.roll_rarity(might, 0, 0.0, rng)] += 1
		if UpgradePool.roll_rarity(might, 0, 0.5, rng) > UpgradePool.Rarity.COMMON:
			lucky_rare += 1
	var rare_total: int = counts[1] + counts[2] + counts[3]
	_check(counts[0] > 3200 and counts[3] > 0 and counts[1] > counts[2] and counts[2] > counts[3],
			"редкость карт: обычные %d, редкие %d, эпические %d, легендарные %d" % counts)
	_check(lucky_rare > rare_total, "«Удача» повышает шанс редких карт")
	var overflow := 0
	for i in 500:
		var rarity := UpgradePool.roll_rarity(might, might.max_level - 1, 1.0, rng)
		if UpgradePool.levels_for(rarity) > 1:
			overflow += 1
	_check(overflow == 0, "редкая карта не поднимает выше 25-го уровня")

	# Разнообразие (CR-17): в новом предложении и оружие, и пассивка; недавние карты выпадают реже;
	# изгнанные — никогда; эволюцию и дар изгнать нельзя.
	var fresh := {&"sword_arc": 1}
	var mixed := 0
	for i in 300:
		var kinds := {}
		for id in UpgradePool.roll(fresh, rng):
			kinds[DataRegistry.upgrade(id).kind] = true
		if kinds.has(UpgradeData.Kind.WEAPON) and kinds.has(UpgradeData.Kind.PASSIVE):
			mixed += 1
	_check(mixed == 300, "в каждом предложении есть и оружие, и пассивка")
	var repeats_plain := 0
	var repeats_weighted := 0
	for i in 600:
		var first := UpgradePool.roll(fresh, rng)
		var recent := {}
		for id in first:
			recent[id] = DataRegistry.UPGRADE_RULES.repeat_weights[0]
		for id in UpgradePool.roll(fresh, rng):
			repeats_plain += int(id in first)
		for id in UpgradePool.roll(fresh, rng, recent):
			repeats_weighted += int(id in first)
	_check(repeats_weighted * 2 < repeats_plain,
			"антиповтор: карты прошлого предложения выпадают реже (%d против %d)" % [repeats_weighted, repeats_plain])
	var banished: Array = [&"might", &"haste", &"bone_arrow", &"luck", &"throwing_daggers"]
	var leaked_banished := 0
	for i in 300:
		for id in UpgradePool.roll(fresh, rng, {}, banished):
			leaked_banished += int(id in banished)
	_check(leaked_banished == 0, "изгнанные карты не выпадают")
	_check(UpgradePool.can_banish(&"might", false) and UpgradePool.can_banish(&"bone_arrow", false)
			and not UpgradePool.can_banish(&"whirling_blades", true) and not UpgradePool.can_banish(&"potion", false)
			and not UpgradePool.can_banish(&"evo:sword_arc", true),
			"изгнать можно оружие и пассивку, но не эволюцию и дар")
	var weapons := 0
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		if upgrade is SkillData and not upgrade.is_evolution:
			weapons += 1
	_check(weapons >= 17, "оружия на выбор: %d" % weapons)


## Шаг 4: карты рун (id, гнёзда, гарантия ФТ-10 с рунами, изгнание руны), резонансы тегов, сродство класса.
## Чистые функции пула — без мира.
func _check_rune_pool() -> void:
	var rules := DataRegistry.UPGRADE_RULES
	var card := UpgradePool.rune_card_id(&"rune_split", &"silver_bolts")
	var parsed := UpgradePool.parse_rune_card(card)
	_check(parsed.size() == 2 and parsed[0] == &"rune_split" and parsed[1] == &"silver_bolts"
			and UpgradePool.parse_rune_card(&"rune:x").is_empty() and UpgradePool.parse_rune_card(&"might").is_empty()
			and UpgradePool.banish_key(card) == &"rune:rune_split" and UpgradePool.banish_key(&"might") == &"might"
			and UpgradePool.can_banish(card, false),
			"карта руны: id «rune:<руна>:<навык>», мусорный id отклоняется, изгоняется руна целиком")

	var bolts: SkillData = DataRegistry.upgrade(&"silver_bolts")
	var sword: SkillData = DataRegistry.upgrade(&"sword_arc")
	var might := DataRegistry.skill_modifier(&"rune_might")
	_check(UpgradePool.can_socket(might, bolts, {}) and not UpgradePool.can_socket(DataRegistry.skill_modifier(&"rune_pierce"), sword, {}),
			"руна подходит навыку по тегам и действию")
	_check(not UpgradePool.can_socket(might, bolts, {&"silver_bolts": [&"rune_might"]}), "одну руну дважды в навык не вставить")
	var full: Array = []
	for rune: SkillModifier in DataRegistry.SKILL_MODIFIERS:
		if full.size() < rules.runes_per_skill and rune.id != &"rune_might" and UpgradePool.can_socket(rune, bolts, {&"silver_bolts": full}):
			full.append(rune.id)
	_check(not UpgradePool.can_socket(might, bolts, {&"silver_bolts": full}), "гнёзда навыка заняты (%d) — руну не вставить" % rules.runes_per_skill)

	# ТК-10 с рунами: при любом состоянии — 3 уникальные допустимые карты, руны — только во взятые навыки.
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var bad := 0
	var rune_cards := 0
	for i in RANDOM_ROLLS:
		var levels := {}
		var owned := {}
		for upgrade: UpgradeData in DataRegistry.UPGRADES:
			var evolution: bool = upgrade is SkillData and upgrade.is_evolution
			if upgrade.kind != UpgradeData.Kind.FILLER and not evolution and rng.randf() < 0.5:
				levels[upgrade.id] = rng.randi_range(1, upgrade.max_level)
		for id: StringName in levels:
			var skill := DataRegistry.upgrade(id) as SkillData
			if skill == null or rng.randf() < 0.5:
				continue
			var want := rng.randi_range(0, rules.runes_per_skill)
			var list: Array = []
			for rune: SkillModifier in DataRegistry.SKILL_MODIFIERS:
				if list.size() < want and UpgradePool.can_socket(rune, skill, {id: list}):
					list.append(rune.id)
			owned[id] = list
		var cards := UpgradePool.roll(levels, rng)
		UpgradePool.add_rune_cards(cards, levels, owned, 0.0, rng, {}, [], 1.0)
		var unique := {}
		for id in cards:
			unique[id] = true
			var socket := UpgradePool.parse_rune_card(id)
			if UpgradePool.parse_evolution_card(id) != &"":
				continue  # ступень эволюции: проверена в _check_upgrade_pool
			if socket.is_empty():
				var upgrade := DataRegistry.upgrade(id)
				bad += int(upgrade == null or upgrade.is_maxed(levels.get(id, 0)))
				continue
			rune_cards += 1
			var target := DataRegistry.upgrade(socket[1]) as SkillData
			if target == null or levels.get(socket[1], 0) <= 0 \
					or not UpgradePool.can_socket(DataRegistry.skill_modifier(socket[0]), target, owned):
				bad += 1
		if cards.size() != 3 or unique.size() != 3:
			bad += 1
	_check(bad == 0 and rune_cards >= RANDOM_ROLLS / 10,
			"%d случайных состояний с рунами: всегда 3 уникальные допустимые карты (карт рун %d, ошибок %d)" % [RANDOM_ROLLS, rune_cards, bad])

	var no_rune := true
	var sword_full := {&"sword_arc": [&"rune_might", &"rune_haste", &"rune_luck"].slice(0, rules.runes_per_skill)}
	for i in 50:
		var cards := UpgradePool.roll({&"sword_arc": 5, &"might": 3}, rng)
		UpgradePool.add_rune_cards(cards, {&"sword_arc": 5, &"might": 3}, sword_full, 0.0, rng, {}, [], 1.0)
		no_rune = no_rune and cards.size() == 3 and not cards.any(func(id: StringName) -> bool: return UpgradePool.is_rune_card(id))
	_check(no_rune, "гнёзда всех навыков заняты — карт рун нет, карт по-прежнему 3")
	var leaked := 0
	var mixed := 0
	for i in 200:
		var cards := UpgradePool.roll({&"silver_bolts": 3, &"might": 1}, rng)
		UpgradePool.add_rune_cards(cards, {&"silver_bolts": 3, &"might": 1}, {}, 0.0, rng, {}, [&"rune:rune_split"], 1.0)
		var kinds := {}
		for id in cards:
			var socket := UpgradePool.parse_rune_card(id)
			leaked += int(not socket.is_empty() and socket[0] == &"rune_split")
			if socket.is_empty():
				kinds[DataRegistry.upgrade(id).kind] = true
		mixed += int(kinds.size() == 2)
	_check(leaked == 0, "изгнанная руна не выпадает ни в один навык")
	_check(mixed == 200, "карта руны встаёт на место повторяющегося типа: оружие и пассивка остаются")

	# Резонансы: навыки считаются по тегам (с тегами рун), порог даёт характеристики «по тегу».
	var counts := Synergies.counts({&"sword_arc": 1, &"bone_arrow": 2, &"might": 3}, {&"bone_arrow": [&"rune_fire"]})
	_check(counts.get(&"physical", 0) == 2 and counts.get(&"fire", 0) == 1 and counts.get(&"melee", 0) == 1,
			"резонанс: навыки считаются по тегам, Руна огня делает навык огненным %s" % counts)
	var stats := Synergies.stats({&"sword_arc": 1, &"bone_arrow": 2}, {})
	_check(is_equal_approx(float(stats.get(&"might:physical", 0.0)), 0.08) and stats.size() == 1,
			"резонанс «Физический» на 2 навыках: +8%% урона физическим ударам %s" % stats)
	var fire := DataRegistry.synergy_for_tag(&"fire")
	_check(DataRegistry.SYNERGIES.size() >= 10 and fire != null and fire.tier_for(1) == 0 and fire.tier_for(3) == 2
			and fire.next_threshold(3) == 4 and Synergies.tooltip(fire, 3) != "",
			"резонансов %d, пороги по числу навыков" % DataRegistry.SYNERGIES.size())
	var bad_synergies: Array = []
	for synergy: SynergyData in DataRegistry.SYNERGIES:
		if DataRegistry.tag(synergy.tag) == null or synergy.tiers.size() != synergy.thresholds.size():
			bad_synergies.append(synergy.id)
		for tier: Dictionary in synergy.tiers:
			for stat: Variant in tier:
				if DataRegistry.stat_def(StringName(str(stat))) == null:
					bad_synergies.append("%s:%s" % [synergy.id, stat])
	_check(bad_synergies.is_empty(), "у резонансов есть тег, пороги и характеристики из StatDef %s" % [bad_synergies])
	var gains := Synergies.gains({&"sword_arc": 1}, {}, &"bone_arrow", DataRegistry.tag_mask(DataRegistry.upgrade(&"bone_arrow").tags))
	_check(gains.any(func(g: Array) -> bool: return g[0].tag == &"physical" and g[1] == 1 and g[2] == 2),
			"карта навыка показывает рост резонанса «Физический» 1 → 2")

	# Сродство класса: навыки с тегами класса выпадают чаще; у каждого класса оно задано.
	var fire_mask := DataRegistry.tag_mask([&"fire"])
	var is_fire := func(id: StringName) -> bool:
		var skill := DataRegistry.upgrade(id) as SkillData
		return skill != null and (DataRegistry.tag_mask(skill.tags) & fire_mask) != 0
	var with_affinity := 0
	var plain := 0
	for i in 600:
		with_affinity += UpgradePool.roll({&"might": 1}, rng, {}, [], UpgradePool.CARD_COUNT, fire_mask).filter(is_fire).size()
		plain += UpgradePool.roll({&"might": 1}, rng).filter(is_fire).size()
	_check(with_affinity > plain * 1.3, "сродство класса: огненные навыки у Пироманта выпадают чаще (%d против %d)" % [with_affinity, plain])
	_check(DataRegistry.HEROES.all(func(h: HeroData) -> bool: return not h.affinity_tags.is_empty()), "у каждого класса задано сродство")


## CR-07: предметы корректны при любой редкости; испорченные данные отклоняются.
func _check_loot_roller() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var table := DataRegistry.LOOT_TABLE
	for rarity in ItemRoller.Rarity.values():
		var bad := 0
		for i in LOOT_ROLLS:
			var depth := rng.randi_range(0, 8)
			var item := ItemRoller.roll(rng, rarity, depth, table)
			var affixes: Array = item["affixes"]
			var base := DataRegistry.item_base(item["base"])
			var per_kind := {}
			for id in affixes:
				var affix := DataRegistry.affix(id)
				per_kind[affix.kind] = int(per_kind.get(affix.kind, 0)) + 1
				if not affix.fits(base, depth) or affix.kind == AffixData.Kind.CURSE:
					bad += 1  # шаг 7: пул по слоту и глубине, проклятие — не аффикс
			if per_kind.values().any(func(n: int) -> bool: return n > ItemRoller.AFFIX_PER_KIND.get(rarity, 0)):
				bad += 1
			if not ItemRoller.is_valid(item) or item["stats"].is_empty() or ItemRoller.display_name(item) == "":
				bad += 1
			elif rarity == ItemRoller.Rarity.LEGENDARY:
				bad += 0 if ItemRoller.legendary(item) != null and ItemRoller.legendary_line(item) != "" else 1
			elif rarity == ItemRoller.Rarity.CURSED:
				var curse := DataRegistry.affix(item["curse"])
				if curse == null or item["stats"][curse.stat] >= 0.0 or affixes.size() < 2 or ItemRoller.curse_line(item) == "":
					bad += 1
			elif affixes.size() < ItemRoller.AFFIX_COUNT[rarity][0] or affixes.size() > ItemRoller.AFFIX_COUNT[rarity][1]:
				bad += 1
			var expected_lines: int = item["stats"].size() - (1 if rarity == ItemRoller.Rarity.CURSED else 0)
			if ItemRoller.stat_lines(item).size() != expected_lines:
				bad += 1
		_check(bad == 0, "%d предметов редкости %s корректны" % [LOOT_ROLLS, ItemRoller.Rarity.keys()[rarity]])
	var below := 0
	var cursed_as_legendary := 0
	for i in 500:
		if ItemRoller.roll_rarity(rng, table, 0, ItemRoller.Rarity.RARE) < ItemRoller.Rarity.RARE:
			below += 1
		if ItemRoller.roll_rarity(rng, table, 0, ItemRoller.Rarity.LEGENDARY) != ItemRoller.Rarity.LEGENDARY:
			cursed_as_legendary += 1
	_check(below == 0, "гарантированный дроп не ниже редкого")
	_check(cursed_as_legendary == 0, "гарантия легендарного не оборачивается проклятым")
	# Шаг 11.15: значки из атласа у всех баз, легендарок и товаров; вариант значка не меняется после пересылки.
	var icon_names: Array = [DataRegistry.VISUAL.potion_icon, DataRegistry.VISUAL.key_icon]
	for base: ItemBaseData in DataRegistry.ITEM_BASES:
		icon_names.append_array(base.icons if not base.icons.is_empty() else PackedStringArray([""]))
	for unique: UniqueItemData in DataRegistry.UNIQUE_ITEMS:
		icon_names.append(unique.icon)
	for goods: GoodsData in DataRegistry.GOODS:
		icon_names.append(goods.icon)
	var missing := icon_names.filter(func(icon: Variant) -> bool: return not ItemIcon.has_icon(StringName(icon)))
	var sample := ItemRoller.roll(rng, ItemRoller.Rarity.RARE, 2, table)
	var copied: Dictionary = bytes_to_var(var_to_bytes(sample))
	var variants := {}
	for i in 60:
		variants[ItemRoller.icon_of(ItemRoller.roll(rng, ItemRoller.Rarity.MAGIC, 0, table))] = true
	_check(missing.is_empty() and ItemRoller.icon_of(copied) == ItemRoller.icon_of(sample) and variants.size() >= 6,
			"значки предметов: все в атласе (нет: %s), после пересылки тот же, %d разных" % [missing, variants.size()])
	var stalwart := DataRegistry.affix(&"stalwart")
	_check(not stalwart.fits(DataRegistry.item_base(&"helm"), 0) and stalwart.fits(DataRegistry.item_base(&"helm"), 2)
			and not stalwart.fits(DataRegistry.item_base(&"boots"), 5), "аффикс из пула по слоту и глубине")
	if TranslationServer.get_locale().begins_with("ru"):
		var named := {"base": &"cuirass", "rarity": 1, "unique": &"", "affixes": [&"blazing", &"of_might"], "curse": &"",
				"stats": {&"armor": 1.0}}
		_check(ItemRoller.display_name(named) == "Пылающая кираса силы", "префикс согласуется с родом базы: «%s»" % ItemRoller.display_name(named))
	var minus := ItemRoller.stat_line(&"max_health", -20.0)
	_check(minus.begins_with("−20"), "штраф проклятия пишется со знаком минус: «%s»" % minus)
	var broken: Array = [
		{}, {"base": &"nope", "rarity": 0, "stats": {}},
		{"base": &"helm", "rarity": 9, "stats": {}},
		{"base": &"helm", "rarity": 1, "stats": {&"teleport": 1.0}},
		{"base": &"helm", "rarity": 1, "stats": {&"might": 1.0e9}},
		{"base": &"helm", "rarity": 4, "curse": &"of_might", "stats": {&"might": 0.1}},
	]
	var accepted := 0
	for item in broken:
		if ItemRoller.is_valid(item):
			accepted += 1
	_check(accepted == 0, "испорченные предметы отклоняются (данные из сети)")


## Шаг 5, часть 2: пачка событий снарядов (ProjectileStream) — клиент получает те же данные для фабрики, кроме
## нужных только хосту; испорченная пачка отбрасывается целиком.
func _check_projectile_stream() -> void:
	var skill: StringName = DataRegistry.UPGRADES[0].id
	var arrow := {"type": &"arrow", "pos": Vector2(12.5, -3.25), "dir": Vector2(0.6, 0.8), "speed": 230.0, "range": 310.0,
		"owner": 1234567890, "skill": skill, "return": true, "damage": 99.0, "crit": true, "pierce": 2}
	var warn := {"type": &"warn", "pos": Vector2(1, 2), "dir": Vector2.ZERO, "radius": 30.0, "fuse": 0.0, "line": true,
		"hostile": true, "color": Color(1.0, 0.45, 0.15), "from": Vector2(5, 6)}
	var chain := {"type": &"lightning", "pos": Vector2(0, 0), "points": PackedVector2Array([Vector2(1, 1), Vector2(9, 4)]),
		"skill": &"нет_такого_навыка", "count": 3, "look": &"bats", "width": 6.0, "duration": 2.0, "phase": 0.5}
	var stream := ProjectileStream.new()
	stream.queue_spawn(7, arrow)
	stream.queue_spawn(8, warn)
	stream.queue_spawn(9, chain)
	stream.queue_removal(5)
	var bytes := stream.take()
	var batch: Variant = ProjectileStream.decode(bytes)
	var ok: bool = batch is Dictionary and batch["shots"].size() == 3 and batch["removed"] == PackedInt32Array([5])
	if ok:
		var a: Dictionary = batch["shots"][0][1]
		var w: Dictionary = batch["shots"][1][1]
		var c: Dictionary = batch["shots"][2][1]
		ok = batch["shots"][0][0] == 7 and a["type"] == &"arrow" and a["pos"] == arrow["pos"] and a["dir"] == arrow["dir"] \
				and a["speed"] == 230.0 and a["owner"] == 1234567890 and a["skill"] == skill and a["return"] == true \
				and not a.has("damage") and not a.has("crit") and not a.has("pierce") and not a.has("hostile") \
				and w["dir"] == Vector2.ZERO and w.has("fuse") and w["line"] and w["hostile"] and w["from"] == Vector2(5, 6) \
				and absf(Color(w["color"]).g - 0.45) < 0.002 and absf(Color(w["color"]).b - 0.15) < 0.002 \
				and c["points"] == chain["points"] \
				and c["skill"] == &"нет_такого_навыка" and c["count"] == 3 and c["look"] == &"bats" and c["phase"] == 0.5
	_check(ok, "снаряды пачкой: выстрел, телеграф и цепь доходят теми же данными без полей хоста (%d байт на 3 выстрела)"
			% bytes.size())
	_check(ProjectileStream.decode(bytes.slice(0, bytes.size() - 3)) == null and ProjectileStream.decode(PackedByteArray()) == null,
			"снаряды пачкой: обрезанная или пустая пачка отбрасывается")


# --- Сквозной забег ---

func _check_run() -> void:
	RunConfig.start_new_run(DataRegistry.HEROES[0], false, 12345)
	_world = load(ScenePaths.WORLD).instantiate()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE  # сам тест работает и на паузе, мир — нет
	add_child(_world)
	# Окно проверок потеряло фокус (переключились на другое окно) — без этого мир встал бы на паузу до конца.
	(_world.get_node("PauseMenu") as PauseMenu).pause_on_focus_out = false
	_world.pickups.child_entered_tree.connect(func(node: Node) -> void:
		if node is Pickup and node.kind == Pickup.Kind.ITEM:
			_dropped_rarities.append(node.item["rarity"]))
	_world.projectiles.child_entered_tree.connect(func(node: Node) -> void:
		if node is Projectile and node.kind == &"blast" and node.hostile:  # метеоры героя не в счёт
			_blasts += 1)
	_world.pickups.child_entered_tree.connect(func(node: Node) -> void:
		if node is Pickup and node.kind == Pickup.Kind.GOLD:
			_coins += 1)
	_world.projectiles.child_entered_tree.connect(func(node: Node) -> void:
		if node is Projectile and node.hostile:
			_hostile_shots.append([node.kind, node.position]))
	await _wait_until(func() -> bool: return _world.find_player(1) != null, 10.0)  # генерация идёт в фоне

	var knight := _world.find_player(1)
	_check(knight != null and knight.get_upgrade_level(&"sword_arc") == 1, "Рыцарь появился с мечом")
	var sorceress := _world.spawn_player(2, DataRegistry.HEROES[2])
	var necromancer := _world.spawn_player(3, DataRegistry.HEROES[1])
	var party: Array[Player] = [knight, sorceress, necromancer]
	for p in party:
		p.invulnerable = true

	_check_map_plan()
	await _check_hero_passives(knight, sorceress, necromancer, party)
	await _check_combat_and_level_up(knight)
	await _check_map_objects(knight)
	_check_inventory(knight)
	await _check_elite(knight)
	await _check_enemy_look(knight)
	await _check_new_weapons(knight, party)
	_check_defensive_passives(knight, necromancer)
	await _check_wave_scaling()
	await _check_gold(knight)
	await _check_merchants(knight)
	await _check_reroll(knight)
	await _check_banish(knight)
	await _check_runes(knight)
	await _check_level_up_layout()
	await _check_deferred_level_up(knight)
	await _check_skill_icons(knight)
	await _check_skill_vfx(knight)
	await _check_soul_magnet(knight)
	await _check_performance_limits(knight)
	await _check_run_stats(knight, party)
	_check_talents_in_run()
	await _check_special_enemies(knight)
	await _check_enemy_tells(knight, party)
	await _check_boss_attacks(knight)
	await _check_interactables(knight)
	await _check_secret_rooms(knight)
	await _check_hazards(knight)
	await _check_lighting(knight)
	_check_decor()
	_check_minimap()
	await _check_juice(knight, sorceress)
	await _check_combat_sound(knight, sorceress)
	await _check_battle_music(knight)
	_check_seals(knight)
	await _check_post_fx()
	await _check_new_passives(knight)
	await _check_statuses(knight)
	await _check_challenges(knight)
	await _check_character_sheet(knight)
	_check_pause_menu()
	await _check_last_breath(knight, sorceress)
	_check_chronicle_recorder()
	_check(_world.get_node("HUD").minimap.has_map(), "миникарта построена по LevelData")

	# Уровень 1 — Замок. ТК-09: по истечении таймера — ровно 1 босс.
	_check(_world.waves.table == DataRegistry.wave_table_for(0), "уровень 1 — волны Проклятого леса")
	_bosses_spawned = 0
	GameState.level_time_left = 0.05
	await _seconds(1.0)
	var bosses := _bosses_alive()
	_check(bosses.size() == 1 and _bosses_spawned == 1, "по таймеру появился ровно 1 босс (ТК-09)")
	_check(not bosses.is_empty() and bosses[0].data.id == &"garrison_commander",
			"босс Проклятого леса — Командор Гарнизона (эскиз; вместо Рыцаря смерти)")
	_check(_has_marker(OffscreenMarkers.BOSS), "HUD: метка на босса")
	_check(not _world.waves.active, "волны остановлены на время босса")
	await _seconds(1.0)
	_check(_bosses_alive().size() == 1, "второй босс не появляется")
	_dropped_rarities.clear()
	_coins = 0
	if not bosses.is_empty():
		bosses[0].take_damage(1.0e9, 1)
	await _frames(2)
	var key := _find_key()
	_check(key != null, "босс оставил Ключ (фиксированный дроп ФТ-09)")
	_check(_dropped_rarities.any(func(r: int) -> bool: return r >= ItemRoller.Rarity.RARE), "босс оставил редкий предмет")
	_check(_coins >= 3, "босс оставил кучу золота (CR-14)")
	_check(_has_marker(OffscreenMarkers.KEY), "HUD: метка на Ключ")
	if key != null:
		knight.teleport(key.global_position)
		await _seconds(0.3)
	_check(_world.flow.phase == LevelFlow.Phase.PORTAL and _world.flow.portal.active, "Ключ зажёг портал")
	_check(_has_marker(Portal.MODE_COLORS[Portal.Mode.NEXT]), "HUD: метка на открытый портал")
	knight.teleport(_world.flow.portal.global_position)
	await _wait_until(func() -> bool: return GameState.level_index == 1 and _world.flow.phase == LevelFlow.Phase.WAVES, 10.0)
	_check(GameState.level_index == 1, "портал перевёл на следующий уровень (ТК-07)")
	_check(not _world.flow.portal.active and _bosses_alive().is_empty() and _find_key() == null,
			"объекты прошлого уровня убраны, новый портал потухший")
	_check(GameState.running and GameState.level_time_left > GameState.LEVEL_DURATION - 1.0, "таймер уровня сброшен")

	# Уровни 2 и 3 — Затопленный склеп и Пылающий собор; на каждом обелиск.
	_check(_world.waves.table == DataRegistry.wave_table_for(1), "уровень 2 — Затопленный склеп")
	_check(is_equal_approx(_world.waves.count_mult, 3.0), "на 2-м уровне врагов в волнах ×3")
	await _visit(knight, Obelisk)
	await _complete_level(knight)
	_check(_world.waves.table == DataRegistry.wave_table_for(2), "уровень 3 — Пылающий собор")
	_check(is_equal_approx(_world.waves.count_mult, 5.0), "на 3-м уровне врагов в волнах ×5")
	await _visit(knight, Obelisk)
	_check(_world.flow.obelisks_visited == 3, "за круг посещено 3 обелиска")
	await _complete_level(knight)

	# Логово финального босса.
	_check(GameState.level_index == 3 and RunPlan.is_final(3), "после 3 уровней — логово финального босса")
	_check(_world.flow.phase == LevelFlow.Phase.FINAL_BOSS, "в логове фаза финального босса")
	var lords := _bosses_alive()
	_check(lords.size() == 1 and lords[0].data.id == &"pit_lord", "Владыка Бездны ждёт сразу, ровно один")
	GameState.level_time_left = 0.05
	await _seconds(0.5)
	_check(_bosses_alive().size() == 1, "таймер в логове не призывает второго босса")
	var site := _find_prop(GrailSite)
	_check(site != null, "3 обелиска — в логове есть место Грааля")
	if site != null:
		var might_before := sorceress.stat(Player.STAT_MIGHT)
		knight.teleport(site.global_position)
		await _seconds(GrailSite.DIG_TIME + 0.5)
		_check(_world.flow.grail_found and sorceress.stat(Player.STAT_MIGHT) > might_before,
				"Грааль выкопан — бонус всему отряду")
	_dropped_rarities.clear()
	if not lords.is_empty():
		lords[0].take_damage(1.0e9, 1)
	await _frames(3)
	_check(_world.flow.phase == LevelFlow.Phase.CHOICE and _run_choices == 1, "после финального босса — выбор пути")
	_check(_dropped_rarities.has(ItemRoller.Rarity.LEGENDARY), "финальный босс оставил легендарный предмет")
	var fights := BalanceLog.read_all(BALANCE_LOG)
	var final_fight: Dictionary = fights.back() if not fights.is_empty() else {}
	_check(fights.size() >= 4 and final_fight.get("boss") == "pit_lord" and final_fight.get("outcome") == "victory"
			and final_fight.get("players") == 3 and int(final_fight.get("boss_hp", 0)) > 0
			and final_fight.get("heroes", []).all(func(h: Dictionary) -> bool: return int(h.get("level", 0)) >= 1),
			"журнал боёв: %d боёв с боссами, финальный — победа над Владыкой Бездны втроём" % fights.size())
	var modes := {}
	for gate in _world.flow.portals:
		if gate.active:
			modes[gate.mode] = gate
	_check(modes.has(Portal.Mode.CONTINUE) and modes.has(Portal.Mode.FINISH), "открыты 2 портала: продолжить и завершить")

	# «Бесконечная гниль»: новый круг, враги улучшенного тира.
	if modes.has(Portal.Mode.CONTINUE):
		knight.teleport(modes[Portal.Mode.CONTINUE].global_position)
	await _wait_until(func() -> bool: return GameState.level_index == 4 and _world.flow.phase == LevelFlow.Phase.WAVES, 10.0)
	_check(GameState.level_index == 4 and RunPlan.stage(4) == 0 and _world.flow.obelisks_visited == 0,
			"портал «Бесконечная гниль» начал второй круг с Проклятого леса")
	await _seconds(4.0)
	var base_tier := 0
	var spawned := 0
	for child in _world.enemies.get_children():
		var e := child as Enemy
		if e != null and not e.ally and not e.data.is_boss:
			spawned += 1
			if e.data.upgrade != null:
				base_tier += 1
	_check(spawned > 0 and base_tier == 0, "на 5-м уровне все враги улучшенного тира (CR-09)")

	for i in 3:
		await _complete_level(knight)
	_check(RunPlan.is_final(GameState.level_index), "второй круг тоже заканчивается логовом")
	for lord in _bosses_alive():
		lord.take_damage(1.0e9, 1)
	await _frames(3)
	for gate in _world.flow.portals:
		if gate.active and gate.mode == Portal.Mode.FINISH:
			knight.teleport(gate.global_position)
	await _seconds(0.3)
	_check(_run_result == 1 and _world.flow.phase == LevelFlow.Phase.VICTORY, "портал «Завершить забег» — победа")
	_check(not GameState.running, "мир остановлен после победы")


func _check_hero_passives(knight: Player, sorceress: Player, necromancer: Player, party: Array[Player]) -> void:
	_check(is_equal_approx(sorceress.damage_mult(), 1.0 + Player.LEADERSHIP_BONUS), "Лидерство: союзник рядом с Рыцарем +10 % урона")
	_check(is_equal_approx(knight.damage_mult(), 1.0), "сам Рыцарь бонус Лидерства не получает")

	sorceress.invulnerable = false
	var health_before := sorceress.health
	var mana_before := sorceress.mana
	sorceress.take_damage(20.0)
	sorceress.invulnerable = true
	_check(is_equal_approx(sorceress.mana, mana_before - 10.0) and is_equal_approx(sorceress.health, health_before - 10.0),
			"Мана-щит: половину урона приняла мана")

	# Некромантия: герои «выключены», чтобы врага убил именно скелет-союзник.
	for p in party:
		p.alive = false
	var skeleton := _world.passives.raise_skeleton(necromancer, necromancer.global_position)
	_check(skeleton != null and skeleton.ally, "Некромантия поднимает скелета-союзника")
	_check(_world.director.nearest_enemy(necromancer.global_position, 50.0) == null, "союзник не цель для оружия")
	var victim := _world.spawn_enemy({"id": &"zombie", "pos": necromancer.global_position + Vector2(40, 0)})
	await _seconds(4.0)
	_check(not is_instance_valid(victim), "скелет-союзник убил врага")
	for i in 10:
		_world.passives.raise_skeleton(necromancer, necromancer.global_position)
	_check(_world.passives.skeletons_of(necromancer.peer_id()) == HeroPassiveSystem.MAX_SKELETONS, "скелетов не больше предела")
	for p in party:
		p.alive = true


func _check_combat_and_level_up(knight: Player) -> void:
	# ТК-08: ближайший враг в радиусе атакуется без ручного запуска.
	var victim := _world.spawn_enemy({"id": &"skeleton", "pos": knight.global_position + Vector2(30, 0)})
	var swung := false
	for i in ceili(1.5 * Engine.physics_ticks_per_second):
		await _frames(1)
		swung = swung or knight.is_attacking()
	_check(not is_instance_valid(victim), "автоатака убила врага рядом (ТК-08)")
	_check(swung, "герой играет анимацию удара, когда бьёт навык (шаг 11.1)")
	# Шаг 11.11: 8 направлений — герой смотрит туда, куда идёт (по смещению, как у клиентов).
	await _wait_until(func() -> bool: return not knight.is_attacking(), 1.0)
	var sheet := knight._layout
	for i in 8:
		knight.position += Vector2(0, -3)
		await _frames(1)
	_check(knight._dir == sheet.dir_index("n"), "идёт вверх — герой спиной к камере (шаг 11.11)")
	for i in 8:
		knight.position += Vector2(-3, 3)
		await _frames(1)
	_check(knight._dir == sheet.dir_index("se") and knight.body.flip_h, "идёт влево-вниз — вид «вправо-вниз» с отражением")
	for i in 8:
		knight.position += Vector2(3, 0)
		await _frames(1)
	_check(knight._dir == sheet.dir_index("e") and not knight.body.flip_h, "идёт вправо — профиль вправо")
	# Шаг 11.19: поставленный у цели навык — каст, удар по стоящему — вздрагивание, смерть доигрывается до призрака.
	await _wait_until(func() -> bool: return not knight.is_attacking() and knight._since_attack >= Player.ATTACK_REST, 1.0)
	knight.play_attack(Vector2.RIGHT, true)
	var cast_ok := knight.is_attacking() and knight._attack_anim == Player.ANIM_CAST
	await _wait_until(func() -> bool: return not knight.is_attacking(), 1.5)
	knight._since_hurt = Player.HURT_COOLDOWN
	knight.flash_hit()
	var hurt_ok := knight._hurt_time >= 0.0 or knight.is_attacking()  # удар навыка в тот же кадр важнее вздрагивания
	knight.alive = false
	var falling := knight._death_time >= 0.0 and knight.modulate == Color.WHITE
	await _seconds(sheet.duration(Player.ANIM_DEATH) + 0.2)
	var ghost := knight._death_time < 0.0 and knight.modulate.a < 1.0
	knight.alive = true
	_check(cast_ok and hurt_ok and falling and ghost and knight.modulate == Color.WHITE,
			"анимации героя: каст, вздрагивание, падение и только потом призрак (шаг 11.19)")
	_check(knight.kills > 0, "убийство засчитано герою (счётчик HUD)")
	await _seconds(0.5)
	_check(knight.xp > 0 or knight.level > 1, "кристалл опыта подобран")
	_check(not _waves_started.is_empty(), "волна началась по таймеру (ФТ-09)")
	await _seconds(2.0)
	_check(_world.director.hostile_count() > 0, "враги волны появились из точек спавна")

	# ТК-10: 3 уникальные карты, хост принимает только карту из предложения.
	_auto_pick = false
	await _frames(2)
	_drain_offers()
	_offers.clear()
	_world.upgrades.grant_xp(knight, 60)
	_check(_offers.size() == 1, "повышение уровня даёт предложение")
	if _offers.size() == 1:
		var cards: Array = _offers[0][1]
		var unique := {}
		for card: Dictionary in cards:
			unique[card["id"]] = true
		_check(cards.size() == 3 and unique.size() == 3, "предложено ровно 3 уникальные карты (ТК-10)")
		_check(get_tree().paused, "одиночная игра на паузе во время выбора")
		_check(not _world.upgrades.apply_choice(1, &"no_such_card"), "карта не из предложения отклонена (ФТ-16)")
		_check(not _world.upgrades.apply_choice(2, cards[0]["id"]), "выбор за чужого игрока отклонён (ФТ-16)")
		# Карта руны (шаг 4) уровней не даёт — здесь проверяются обычные карты.
		var first := cards.find_custom(func(card: Dictionary) -> bool: return not card.has("rune") and not card.has("skill"))
		var chosen := DataRegistry.upgrade(cards[first]["id"])
		var gain := UpgradePool.levels_for(cards[first]["rarity"])
		_check(cards.all(func(card: Dictionary) -> bool:
			return card["level"] - card["from"] == UpgradePool.levels_for(card["rarity"]) or card["evolution"] or card.has("rune")),
			"редкость карты = столько уровней сразу")
		_check(_world.upgrades.apply_choice(1, chosen.id), "карта из предложения принята")
		var instant := chosen is PassiveData and (chosen as PassiveData).stat in [Player.STAT_HEAL, Player.STAT_GOLD]
		_check(instant or knight.get_upgrade_level(chosen.id) == cards[first]["level"], "улучшение применено (+%d ур.)" % gain)
	_drain_offers()

	# Ступени эволюции: на 5-м уровне меча — ступень I (без пассивки), на 10-м — превращение в «Вихрь клинков»
	# (ступень II).
	var sword: SkillData = DataRegistry.upgrade(&"sword_arc")
	var step := DataRegistry.UPGRADE_RULES.evolution_step
	while knight.get_upgrade_level(&"sword_arc") < step:
		knight.apply_upgrade(sword)
	knight.evolution_stages.erase(&"sword_arc")  # ступень I могла взяться картой при разборе предложений выше
	var plain := SkillStats.compute(sword, knight.get_upgrade_level(&"sword_arc"), knight)
	_offers.clear()
	_world.upgrades.grant_xp(knight, Player.xp_to_next(knight.level) - knight.xp, false)  # ровно до уровня, без доли опыта
	var stage_card: Dictionary = {}
	for card: Dictionary in (_offers[0][1] if not _offers.is_empty() else []):
		if card["id"] == &"evo:sword_arc":
			stage_card = card
	_check(not stage_card.is_empty() and stage_card["evolution"] and stage_card["stage"] == 1 and stage_card["skill"] == &"sword_arc",
			"на %d-м уровне меча предложена ступень эволюции I" % step)
	_check(_world.upgrades.apply_choice(1, &"evo:sword_arc") and knight.evolution_stage(&"sword_arc") == 1, "ступень I взята")
	var staged := SkillStats.compute(sword, knight.get_upgrade_level(&"sword_arc"), knight)
	_check(staged.damage > plain.damage and staged.cooldown < plain.cooldown and staged.area_mult > plain.area_mult,
			"ступень эволюции усиливает навык: урон %.1f → %.1f" % [plain.damage, staged.damage])
	_check(not knight.add_evolution_stage(&"sword_arc"), "ступень II до %d-го уровня не взять (ФТ-16)" % (2 * step))
	_drain_offers()
	while knight.get_upgrade_level(&"sword_arc") < 2 * step:
		knight.apply_upgrade(sword)
	_check(not knight.add_evolution_stage(&"sword_arc"), "ступень II меча — превращение: картой ступени её не взять (ФТ-16)")
	var sword_level := knight.get_upgrade_level(&"sword_arc")
	_offers.clear()
	_world.upgrades.grant_xp(knight, Player.xp_to_next(knight.level) - knight.xp, false)  # ровно до уровня, без доли опыта
	var evolution_offered := false
	for card: Dictionary in (_offers[0][1] if not _offers.is_empty() else []):
		evolution_offered = evolution_offered or (card["id"] == &"whirling_blades" and card["evolution"] and card["stage"] == 2)
	_check(evolution_offered, "предложена эволюция «Вихрь клинков» (ступень II)")
	_world.upgrades.apply_choice(1, &"whirling_blades")
	_check(knight.get_upgrade_level(&"whirling_blades") == sword_level and knight.get_upgrade_level(&"sword_arc") == 0
			and knight.evolution_stage(&"whirling_blades") == 2 and not knight.evolution_stages.has(&"sword_arc"),
			"эволюция заменила меч и взяла его уровень (%d) и ступени (II)" % sword_level)
	_drain_offers()
	_auto_pick = true


## Шаг 9: генератор карт отвечает описанием в едином формате (MapPlan): планировка и слой объектов. Слой
## детерминирован (тот же сид — те же объекты), стоит на проходимых клетках, и LevelFlow создал объекты по нему.
func _check_map_plan() -> void:
	var plan := _world.flow.plan
	var level := GameState.current_level
	_check(plan != null and plan.level == level and plan.request.biome == RunPlan.biome(0) and plan.request.depth == 0
			and plan.request.run_seed == RunConfig.run_seed, "описание карты: планировка уровня 1 и запрос (биом, глубина, сид)")
	if plan == null:
		return
	var again := ObjectLayer.plan(level, MapRequest.for_run(0), plan.source)
	_check(JSON.stringify(again.to_dict()) == JSON.stringify(plan.to_dict()), "слой объектов детерминирован: тот же сид — те же объекты")
	var cells := {}
	var on_floor := true
	for o in plan.objects:
		var cell: Vector2i = o["cell"]
		var on_wall: bool = o.get("type", &"") == &"secret_wall" and level.get_tile(cell) == Palette.Tile.WALL
		on_floor = on_floor and (Palette.is_passable(level.get_tile(cell)) or on_wall) and not cells.has(cell)
		cells[cell] = true
	_check(on_floor and plan.count(&"merchant") >= 2 and plan.count(&"chest") >= 1,
			"объекты слоя — на проходимых клетках, по одному на клетку; сундуки и торговцы есть")
	var rules := plan.request.biome.objects
	var shrine_ids := DataRegistry.interactables_for(&"fountain", 0).map(func(p: InteractableData) -> StringName: return p.id)
	var shrines := plan.objects.filter(func(o: Dictionary) -> bool: return o.get("type", &"") in shrine_ids).size()
	_check(rules.extra_chests >= 2 and rules.extra_shrines >= 2 and rules.extra_challenges >= 2 and rules.prisoner_tries >= 2
			and plan.count(&"chest") >= level.find_cells(Palette.Tile.CHEST).size() + rules.extra_chests and shrines >= rules.extra_shrines,
			"на уровне больше объектов: сундуков %d (меток %d), святилищ %d, испытаний сверх статуи %d"
			% [plan.count(&"chest"), level.find_cells(Palette.Tile.CHEST).size(), shrines, rules.extra_challenges])

	# Пасхалка: Золотое ведро — ~10 % забегов на первом уровне, на других уровнях — никогда.
	var has_bucket := func(p: MapPlan) -> bool:
		return p.objects.any(func(o: Dictionary) -> bool: return o.get("type", &"") == &"golden_bucket")
	var first_level := 0
	var deeper := 0
	for i in 300:
		var request := MapRequest.for_run(0)
		request.run_seed = 1000 + i
		first_level += int(has_bucket.call(ObjectLayer.plan(level, request, plan.source)))
		var later := MapRequest.for_run(1)
		later.run_seed = 1000 + i
		later.depth = 1
		deeper += int(has_bucket.call(ObjectLayer.plan(level, later, plan.source)))
	_check(first_level >= 15 and first_level <= 50 and deeper == 0,
			"Золотое ведро: на 1-м уровне в %d из 300 забегов (~10 %%), глубже — %d" % [first_level, deeper])
	var created := _world.props.get_children().filter(func(n: Node) -> bool: return n is MapObject and n.object_id > 0)
	var expected := plan.objects.size() - plan.count(&"merchant")
	_check(created.size() == expected and _world.flow.merchants.size() == plan.count(&"merchant"),
			"LevelFlow создал объекты по слою: %d из %d" % [created.size(), expected])


## Шаг 9: тайник — карман пола за стеной в одну клетку. SecretRooms находит его на карте, слой объектов ставит
## на дверь треснувшую стену, внутрь — клад; три удара по E проламывают стену у хоста и в данных карты.
func _check_secret_rooms(knight: Player) -> void:
	var level := TestLevel.make()
	for y in range(19, 25):
		for x in range(24, 29):
			level.set_tile(Vector2i(x, y), Palette.Tile.WALL)
	for y in range(20, 23):
		for x in range(25, 28):
			level.set_tile(Vector2i(x, y), Palette.Tile.FLOOR)
	var rooms := SecretRooms.find(level)
	_check(rooms.size() == 1 and (rooms[0]["cells"] as Array).size() == 9 and rooms[0]["center"] == Vector2i(26, 21)
			and not (rooms[0]["doors"] as Array).is_empty(), "тайник: карман 3×3 за стеной найден, двери есть")
	var plan := ObjectLayer.plan(level, MapRequest.create(DataRegistry.BIOMES[0], 0, 7))
	var wall_entry: Dictionary = {}
	var hoard_entry: Dictionary = {}
	for o in plan.objects:
		if o.get("type", &"") == &"secret_wall":
			wall_entry = o
		elif o.get("type", &"") in [&"hoard", &"reliquary"]:
			hoard_entry = o
	_check(not wall_entry.is_empty() and wall_entry["cell"] in rooms[0]["doors"] and wall_entry["room"] == Vector2i(26, 21)
			and not hoard_entry.is_empty() and hoard_entry["cell"] == Vector2i(26, 21),
			"слой объектов: треснувшая стена на двери тайника, клад в его середине")

	# Живая стена на текущей карте: стена, к которой с юга (или с любой стороны) подходит достижимый пол.
	var current := GameState.current_level
	var door := LevelData.INVALID_CELL
	var side := Vector2i.ZERO
	for cell in current.find_cells(Palette.Tile.WALL):
		for d: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
			if door == LevelData.INVALID_CELL and current.in_bounds(cell + d) and current.get_tile(cell + d) == Palette.Tile.FLOOR \
					and _world.director.spawn_distance(cell + d) >= 0:
				door = cell
				side = d
	_check(door != LevelData.INVALID_CELL, "на карте есть стена у достижимого пола")
	if door == LevelData.INVALID_CELL:
		return
	var wall: Interactable = _world.spawn_prop({"kind": &"interactable", "type": &"secret_wall",
			"pos": _world.director.cell_center(door), "id": 970, "room": door})
	var opened := [0]
	var count_open := func(_type: StringName, _peer: int, outcome: StringName) -> void:
		if outcome == &"secret":
			opened[0] += 1
	Events.interactable_used.connect(count_open)
	var cell_events := [0]
	var count_cells := func(cell: Vector2i, _tile: int) -> void:
		if cell == door:
			cell_events[0] += 1
	Events.level_cell_changed.connect(count_cells)
	var origin := knight.global_position
	knight.teleport(_world.director.cell_center(door) + Vector2(side) * 56.0)
	await _frames(2)
	_check(wall.in_reach(knight), "к треснувшей стене можно подойти вплотную и ударить")
	var first := _world.apply_interact(1, 970)
	var second := _world.apply_interact(1, 970)
	_check(first and second and wall.hits == 2 and not wall.used and current.get_tile(door) == Palette.Tile.WALL,
			"два удара: стена в трещинах, но стоит")
	_check(_world.apply_interact(1, 970) and wall.used and current.get_tile(door) == Palette.Tile.FLOOR
			and _world.ground.get_cell_atlas_coords(door) == Vector2i(Palette.Tile.FLOOR, 0)
			and _world.director.spawn_distance(door) >= 0 and opened[0] == 1 and cell_events[0] == 1,
			"третий удар: клетка стала полом у хоста, проходима для врагов, событие тайника")
	var chronicle: ChronicleRecorder = _world.get_node("Systems/Chronicle")
	_check(chronicle.summary().secrets >= 1 and not _world.apply_interact(1, 970), "тайник засчитан в «Летопись», повторно не бьётся")
	Events.interactable_used.disconnect(count_open)
	Events.level_cell_changed.disconnect(count_cells)
	_world.set_cell_tile(door, Palette.Tile.WALL)  # вернуть карту как была для следующих проверок
	_check(current.get_tile(door) == Palette.Tile.WALL and _world.director.spawn_distance(door) < 0, "клетку можно вернуть")
	for enemy in _world.enemies.get_children():
		if enemy is Enemy and not enemy.ally:
			enemy.queue_free()  # стража тайника, если встала
	wall.queue_free()
	knight.teleport(origin)
	await _frames(2)


## Шаг 9: опасные клетки биома. У края лавы (Пылающий собор) герой теряет здоровье, враг загорается;
## в шаге от края — ничего. Клетка лавы ставится на время проверки и убирается.
func _check_hazards(knight: Player) -> void:
	var probe := TestLevel.make()  # лава — клетки x 13..18, y 21..23
	var tile := float(Palette.tile_size())
	var edge := Vector2(13.0 * tile - 8.0, 22.5 * tile)
	_check(HazardSystem.at_hazard(probe, edge, 18.0) and not HazardSystem.at_hazard(probe, edge - Vector2(40, 0), 18.0),
			"опасность: у края клетки — да, в шаге от края — нет")
	for biome: BiomeData in DataRegistry.BIOMES:
		_check(biome.hazard_name_key != "" and (biome.hazard_status == &"" or DataRegistry.status(biome.hazard_status) != null),
				"у биома %s описана опасность, статус есть в данных" % biome.id)

	var level := GameState.current_level
	var spot := LevelData.INVALID_CELL
	for cell in level.find_cells(Palette.Tile.FLOOR):
		var right := cell + Vector2i.RIGHT
		if spot == LevelData.INVALID_CELL and level.in_bounds(right) and level.get_tile(right) == Palette.Tile.FLOOR \
				and _world.director.spawn_distance(cell) >= 0:
			spot = cell
	_check(spot != LevelData.INVALID_CELL, "есть место для проверки лавы")
	if spot == LevelData.INVALID_CELL:
		return
	var hazards: HazardSystem = _world.get_node("Systems/Hazards")
	var biome_was: BiomeData = hazards._biome
	var waves_were := _world.waves.active
	_world.waves.active = false
	for enemy in _world.enemies.get_children():
		if enemy is Enemy and not enemy.ally:
			enemy.queue_free()
	hazards._biome = DataRegistry.biome(&"cathedral")
	_world.set_cell_tile(spot + Vector2i.RIGHT, Palette.Tile.HAZARD)
	var origin := knight.global_position
	var at_edge := _world.director.cell_center(spot) + Vector2(tile / 2.0 - 8.0, 0)
	knight.teleport(at_edge)
	knight.invulnerable = false
	knight.health = knight.max_health
	await _frames(2)
	await _wait_until(func() -> bool: return knight.health < knight.max_health - 1.0, 2.0)
	_check(knight.health < knight.max_health - 1.0, "у края лавы герой теряет здоровье (%.0f из %.0f)" % [knight.health, knight.max_health])
	knight.invulnerable = true
	knight.health = knight.max_health
	var target := _world.waves.spawn_enemy(DataRegistry.enemy(&"zombie"), at_edge + Vector2(0, 12))
	if target != null:
		target.max_health = 1.0e6
		target.health = 1.0e6
	await _wait_until(func() -> bool: return is_instance_valid(target) and target.statuses.has(&"burn"), 2.0)
	_check(is_instance_valid(target) and target.statuses.has(&"burn"), "враг у края лавы загорелся")
	if is_instance_valid(target):
		target.queue_free()
	hazards._biome = biome_was
	_world.set_cell_tile(spot + Vector2i.RIGHT, Palette.Tile.FLOOR)
	_world.waves.active = waves_were
	knight.teleport(origin)
	await _frames(2)


## Шаг 11.8: свет. На высоком качестве карта света включена и рисует героев, телеграф удара светит; на низком
## карты нет. У собора огонь на тайлах из раскладки атласа и светящаяся лава; открытый сундук гаснет.
func _check_lighting(knight: Player) -> void:
	var lights := _world.lights
	var quality_was := Settings.effects_quality
	Settings.effects_quality = 2  # без записи в settings.cfg игрока
	Settings.graphics_changed.emit()
	await _frames(2)
	_check(lights.is_on() and lights.visible, "свет: на высоком качестве карта света включена")
	_check(LightSources.collect()[LightSources.Rank.HERO].size() >= 3, "свет: каждый герой — источник света")
	_check(lights.drawn >= 3, "свет: в кадре нарисованы источники (%d)" % lights.drawn)
	var warn := _world.spawn_projectile({"type": &"warn", "pos": knight.global_position + Vector2(30, 0), "radius": 24.0,
			"fuse": 1.0, "color": Color(1, 0.3, 0.2)})
	await _frames(1)
	var attacks: Array = LightSources.collect()[LightSources.Rank.ATTACK]
	_check(attacks.any(func(light: Array) -> bool: return light[2] >= 24.0), "свет: телеграф удара светит на свою область")
	if is_instance_valid(warn):
		warn.queue_free()

	var cathedral := Palette.biomes().find("cathedral")
	var layout: Dictionary = LevelArt.style_for(cathedral)["layout"]
	_check(not layout.get("lights", []).is_empty(), "свет: в раскладке атласа собора есть огонь на тайлах")
	var probe := TestLevel.make()  # лава — клетки x 13..18, y 21..23
	probe.biome = cathedral
	var level_lights := LevelLights.collect(probe)
	var lava := (Vector2(13.5, 21.5)) * float(Palette.tile_size())
	_check(level_lights.positions.has(lava), "свет: клетка лавы светится (%d неподвижных источников)" % level_lights.size())
	var chest := Chest.new()
	var lit := chest.light_scale()
	chest.used = true
	_check(lit > 0.0 and chest.light_scale() == DataRegistry.VISUAL.used_light_share, "свет: открытый сундук гаснет")
	chest.free()

	Settings.effects_quality = 0
	Settings.graphics_changed.emit()
	await _frames(1)
	_check(not lights.visible and not lights.is_processing(), "свет: на низком качестве карты света нет")
	Settings.effects_quality = quality_was
	Settings.graphics_changed.emit()


## Шаг 11.29: предметы обстановки. План из карты — тот же при повторном расчёте (у хоста и клиентов одинаков);
## предметы есть у стен и на полу, все — в атласе, только на обычном полу, достижимом и не у точки появления; узлы
## на уровне; горящие светят неподвижным светом уровня; в Убежище декора биома нет.
func _check_decor() -> void:
	var level := GameState.current_level
	var plan := DecorPlan.of(level)
	var tile := float(Palette.tile_size())
	var spawn := level.find_first(Palette.Tile.PLAYER_SPAWN)
	var reach := LevelValidator.bfs(level, spawn)
	var bad := []
	var lit: Dictionary = {}
	for item: Dictionary in plan:
		var cell := Vector2i((item["pos"] as Vector2) / tile)
		var ok := level.in_bounds(cell) and level.get_tile(cell) == Palette.Tile.FLOOR \
				and reach[level.index_of(cell)] >= DecorPlan.SPAWN_GAP and PropArt.has_prop(item["id"])
		if not ok:
			bad.append([item["id"], cell])
		if lit.is_empty() and not PropArt.light_of(item["id"]).is_empty():
			lit = item
	var biome := LevelLights.biome_of(level)
	var wall_ids := plan.filter(func(it: Dictionary) -> bool: return biome.decor_wall.has(it["id"]))
	# Стену тайника проломили раньше (_check_secret_rooms): план уровня — прежний (из метаданных), а расчёт по
	# нынешней карте сверяется сам с собой.
	_check(plan.size() >= 10 and not wall_ids.is_empty() and plan.size() > wall_ids.size() and bad.is_empty()
			and var_to_str(DecorPlan.build(level)) == var_to_str(DecorPlan.build(level)) and DecorPlan.of(level) == plan
			and _world.decor.count() == plan.size(),
			"обстановка: %d предметов (%d у стен), план из карты повторяется, все на достижимом полу (не так: %s)"
			% [plan.size(), wall_ids.size(), bad])
	if not lit.is_empty():
		var light := PropArt.light_of(lit["id"])
		var at: Vector2 = lit["pos"] + Vector2(float(light[3]) * (-1.0 if lit["flip"] else 1.0), float(light[4]))
		_check(LevelLights.collect(level).positions.has(at), "обстановка: %s светит неподвижным светом уровня" % lit["id"])
	var hub_level := LevelData.create_empty(16, Palette.Tile.FLOOR)
	hub_level.art_style = "castle"
	_check(DecorPlan.build(hub_level).is_empty(), "обстановка: в Убежище (свой атлас) декора биома нет")


## Шаг 11.29: миникарта в высоком разрешении — UPSCALE пикселей на клетку, пол, кромка у стены, пустота прозрачна.
func _check_minimap() -> void:
	var level := GameState.current_level
	var image := Minimap.render(level)
	var spawn := level.find_first(Palette.Tile.PLAYER_SPAWN)
	var at := (Vector2(spawn) + Vector2(0.5, 0.5)) * Minimap.UPSCALE
	var floor_pixel := image.get_pixelv(Vector2i(at))
	var void_cells := level.find_cells(Palette.Tile.VOID)
	var void_pixel := image.get_pixelv((void_cells[0] * Minimap.UPSCALE + Vector2i.ONE * (Minimap.UPSCALE / 2))) \
			if not void_cells.is_empty() else Color(0, 0, 0, 0)
	_check(image.get_width() == level.size * Minimap.UPSCALE and floor_pixel.a > 0.5 and void_pixel.a == 0.0,
			"миникарта: %d px на клетку, пол виден, пустота прозрачна" % Minimap.UPSCALE)


## Шаг 11.9: «сочность». Удар — искры и капли; рана своего героя — тряска камеры и стоп-кадр (одиночная игра),
## чужого — нет; настройки их отключают; убитый враг оставляет брызги и пятно; отдача врага возвращается на место.
func _check_juice(knight: Player, ally: Player) -> void:
	var juice := _world.juice
	var was := [Settings.screen_shake, Settings.hit_stop, Settings.effects_quality]
	Settings.screen_shake = true
	Settings.hit_stop = true
	Settings.effects_quality = 2
	var waves_were := _world.waves.active
	_world.waves.active = false  # чужие удары не мешают считать частицы
	for enemy in _world.enemies.get_children():
		if enemy is Enemy and not enemy.ally:
			enemy.queue_free()
	await _frames(2)
	juice.clear()
	Events.damage_dealt.emit(knight.global_position + Vector2(40, 0), 10.0, true)
	_check(juice.particle_count() == DataRegistry.VISUAL.crit_sparks, "сочность: удачный удар — искры и капли (%d)" % juice.particle_count())
	await _seconds(1.0)
	_check(juice.particle_count() == 0, "сочность: частицы гаснут")

	knight.flash_hit()
	_check(juice.trauma > 0.0 and juice.stops == 1 and Engine.time_scale < 1.0, "сочность: рана своего героя — тряска и стоп-кадр")
	await get_tree().process_frame
	await get_tree().process_frame  # process_frame приходит до _process узлов
	_check(knight.camera.offset != Vector2.ZERO, "сочность: камера своего героя трясётся")
	await _wait_until(func() -> bool: return juice.stops == 0, 1.0)
	_check(is_equal_approx(Engine.time_scale, 1.0), "сочность: стоп-кадр кончился, время идёт")
	await _wait_until(func() -> bool: return juice.trauma == 0.0, 2.0)
	await get_tree().process_frame
	_check(knight.camera.offset == Vector2.ZERO, "сочность: тряска утихла, камера на месте")
	ally.flash_hit()
	_check(juice.trauma == 0.0 and juice.stops == 0, "сочность: рана чужого героя свою камеру не трясёт")
	Settings.screen_shake = false
	Settings.hit_stop = false
	knight.flash_hit()
	_check(juice.trauma == 0.0 and juice.stops == 0, "сочность: тряска и стоп-кадр отключаются в настройках")

	var stains := _world.corpses.stain_count()
	var spot := knight.global_position + Vector2(60, 0)
	var victim := _world.waves.spawn_enemy(DataRegistry.enemy(&"zombie"), spot)
	await _frames(1)
	if victim != null:
		victim.take_damage(1.0e9, 1)
	await _frames(2)
	_check(_world.corpses.stain_count() > stains and juice.particle_count() > 0, "сочность: убитый враг оставляет брызги и пятно")
	var dummy := _world.waves.spawn_enemy(DataRegistry.enemy(&"zombie"), spot)
	_check(dummy != null, "сочность: враг для проверки отдачи появился")
	if dummy != null:
		dummy.ally = true  # навыки героев его не бьют — отдача только от этой вспышки
		dummy.flash_hit()
		var pushed := dummy.body.position
		await _seconds(0.3)
		_check(pushed.length() > 1.0 and dummy.body.position == Vector2.ZERO, "сочность: отдача врага от удара и возврат на место")
		dummy.queue_free()
	_world.waves.active = waves_were
	Settings.screen_shake = was[0]
	Settings.hit_stop = was[1]
	Settings.effects_quality = was[2]


## Шаг 11.27: звуки боя. У каждого события кода есть звук в каталоге; сотня ударов за кадр — один звук попадания
## (перерыв SfxData); удар далеко от своего героя не слышен; рана своего героя — звук «у себя», чужого — нет;
## убитый враг — хруст; удар навыка — звук его стихии, взмах — свист клинка. Без окна звук не играет, счёт идёт.
func _check_combat_sound(knight: Player, ally: Player) -> void:
	var sfx := _world.sfx
	var missing := CombatSound.EVENTS.filter(func(id: StringName) -> bool: return CombatSound.sound(id) == null)
	_check(missing.is_empty(), "звуки боя: у каждого события есть звук в data/audio/sfx (нет: %s)" % [missing])
	var waves_were := _world.waves.active
	_world.waves.active = false  # чужие удары и смерти не мешают считать
	for enemy in _world.enemies.get_children():
		if enemy is Enemy and not enemy.ally:
			enemy.queue_free()
	await _seconds(1.0)  # прошлые звуки отзвучали (предел одновременных)
	sfx.forget_cooldowns()
	var count := func(id: StringName) -> int: return int(sfx.played.get(id, 0))
	var hits: int = count.call(&"hit")
	for i in 100:
		Events.damage_dealt.emit(knight.global_position + Vector2(30, 0), 5.0, false)
	_check(count.call(&"hit") == hits + 1, "звуки боя: сотня ударов за кадр — один звук попадания")
	sfx.forget_cooldowns()
	Events.damage_dealt.emit(knight.global_position + Vector2(5000, 0), 5.0, false)
	_check(count.call(&"hit") == hits + 1, "звуки боя: удар далеко от своего героя не слышен")
	var hurts: int = count.call(&"hero_hurt")
	ally.flash_hit()
	knight.flash_hit()
	_check(count.call(&"hero_hurt") == hurts + 1, "звуки боя: рана своего героя — звук «у себя», чужого — нет")
	var deaths: int = count.call(&"death")
	var victim := _world.waves.spawn_enemy(DataRegistry.enemy(&"zombie"), knight.global_position + Vector2(50, 0))
	await _frames(1)
	sfx.forget_cooldowns()
	if victim != null:
		victim.take_damage(1.0e9, 1)
	await _frames(2)
	_check(count.call(&"death") == deaths + 1, "звуки боя: убитый враг — хруст")
	var fire: int = count.call(&"cast_fire")
	var swings: int = count.call(&"swing")
	sfx.forget_cooldowns()
	sfx.cast(&"fire", &"fireball", knight.global_position)
	sfx.cast(&"physical", &"slash", knight.global_position)
	_check(count.call(&"cast_fire") == fire + 1 and count.call(&"swing") == swings + 1,
			"звуки боя: удар навыка — звук его стихии, взмах — свист клинка")
	_world.waves.active = waves_were


## Шаг 12.3: печати Скверны. Данные и проверка выбора из сети или файла; каждая печать меняет своё (здоровье, урон,
## скорость врагов, пачка волны, элиты, боссы, лечение, цены, опыт); Скверна умножает души и шанс редкого лута.
func _check_seals(knight: Player) -> void:
	var stats := {}
	for seal: SealData in DataRegistry.SEALS:
		stats[seal.stat] = true
	var described := DataRegistry.SEALS.all(func(s: SealData) -> bool:
		return not s.describe().contains("{") and tr(s.name_key) != s.name_key)
	_check(DataRegistry.SEALS.size() == SealData.Stat.size() and stats.size() == SealData.Stat.size() and described,
			"печати: %d печатей на %d действий, у всех название и описание с числом" % [DataRegistry.SEALS.size(), SealData.Stat.size()])
	var raw := {"seal_vigor": 9, &"seal_wrath": 2.0, "no_such_seal": 1, "seal_haste": 0, 7: 1, "seal_horde": "x"}
	var clean := SealData.sanitize(raw)
	_check(clean == {&"seal_vigor": 3, &"seal_wrath": 2} and SealData.sanitize("мусор").is_empty(),
			"печати: из сети и файла — только известные, ранг в пределах данных (%s)" % [clean])

	var was := RunConfig.seals
	var balance := DataRegistry.BALANCE
	var base_health := RunConfig.enemy_health_mult()
	var base_reward := RunConfig.reward_mult()
	var base_price := _world.economy.reroll_cost(knight)
	var all := {}
	for seal: SealData in DataRegistry.SEALS:
		all[seal.id] = seal.max_rank
	RunConfig.seals = SealData.sanitize(all)
	var heat := RunConfig.heat()
	var vigor := DataRegistry.seal(&"seal_vigor")
	var expected_heat := 0
	for seal: SealData in DataRegistry.SEALS:
		expected_heat += seal.points * seal.max_rank
	_check(heat == expected_heat and is_equal_approx(RunConfig.enemy_health_mult(), base_health * vigor.mult(vigor.max_rank))
			and is_equal_approx(RunConfig.reward_mult(), base_reward * (1.0 + balance.heat_souls_per_point * heat))
			and is_equal_approx(RunConfig.magic_find_mult(), 1.0 + balance.heat_magic_find_per_point * heat),
			"печати: все наложены — Скверна %d, здоровье врагов ×%.2f, души ×%.1f" % [heat, RunConfig.enemy_health_mult(),
			RunConfig.reward_mult()])
	var usury := DataRegistry.seal(&"seal_usury")
	_check(_world.economy.reroll_cost(knight) == roundi(base_price * usury.mult(usury.max_rank)),
			"печать ростовщика: переброс %d → %d золота" % [base_price, _world.economy.reroll_cost(knight)])
	var drought := DataRegistry.seal(&"seal_drought")
	var invulnerable := knight.invulnerable
	knight.invulnerable = false
	knight.health = knight.max_health * 0.5
	var before := knight.health
	knight.heal(20.0)
	_check(is_equal_approx(knight.health - before, 20.0 * drought.mult(drought.max_rank)),
			"печать иссушения: лечение 20 → %.1f" % (knight.health - before))
	knight.health = knight.max_health
	knight.invulnerable = invulnerable
	# Скорость и здоровье врага задаются при появлении: читаются сразу, пока навыки героев его не тронули.
	var haste := DataRegistry.seal(&"seal_haste")
	var tyrant := DataRegistry.seal(&"seal_tyrant")
	var spot := knight.global_position + _free_offset(knight, 60.0)
	var fast := _world.spawn_enemy({"id": &"zombie", "pos": spot, "hp_mult": 100.0})
	var lord := _world.waves.spawn_enemy(DataRegistry.enemy(&"pit_lord"), spot)
	var fast_speed: float = fast._base_speed if fast != null else 0.0
	var lord_mult: float = lord.health_mult if lord != null else 0.0
	RunConfig.seals = {}
	var slow := _world.spawn_enemy({"id": &"zombie", "pos": spot, "hp_mult": 100.0})
	var plain_lord := _world.waves.spawn_enemy(DataRegistry.enemy(&"pit_lord"), spot)
	var slow_speed: float = slow._base_speed if slow != null else 0.0
	var plain_mult: float = plain_lord.health_mult if plain_lord != null else 0.0
	for enemy: Variant in [fast, lord, slow, plain_lord]:
		if is_instance_valid(enemy):
			enemy.queue_free()
	RunConfig.seals = was
	_check(slow_speed > 0.0 and is_equal_approx(fast_speed, slow_speed * haste.mult(haste.max_rank)),
			"печать прыти: враг быстрее (%.1f против %.1f)" % [fast_speed, slow_speed])
	_check(plain_mult > 0.0 and is_equal_approx(lord_mult, plain_mult * tyrant.mult(tyrant.max_rank) * vigor.mult(vigor.max_rank)),
			"печать тирана и живучести: босс крепче ×%.2f" % (lord_mult / plain_mult if plain_mult > 0.0 else 0.0))


## Шаг 11.28: боевые слои музыки. У каждого биома свой боевой трек, не равный эмбиенту; толпа врагов у своего
## героя поднимает напряжённость — играет боевой трек; бой утих и прошло battle_hold — снова эмбиент.
## Всё — за один кадр (Sound.step_battle с нужным временем), чтобы фоновый отсчёт автозагрузки не вмешивался.
func _check_battle_music(knight: Player) -> void:
	var lonely := DataRegistry.BIOMES.filter(func(b: BiomeData) -> bool:
		return b.battle_music == null or b.battle_music == b.music).map(func(b: BiomeData) -> StringName: return b.id)
	_check(lonely.is_empty(), "боевые слои: у каждого биома свой боевой трек (нет: %s)" % [lonely])
	var waves_were := _world.waves.active
	_world.waves.active = false
	for enemy in _world.enemies.get_children():
		if enemy is Enemy and not enemy.ally:
			enemy.queue_free()
	await _frames(2)
	var config := load("res://data/audio/audio.tres") as AudioConfig
	Sound.step_battle(0.0, config.battle_hold + 30.0)  # с чистого листа: тихо и давно
	var quiet := Sound.battle_target(_world)
	var calm_track := Sound.music_for(_world)
	var crowd: Array = []
	for i in 16:
		crowd.append(_world.waves.spawn_enemy(DataRegistry.enemy(&"zombie"),
				knight.global_position + Vector2(40.0 + i * 3.0, 0).rotated(i * 0.4)))
	var loud := Sound.battle_target(_world)
	Sound.step_battle(loud, 3.0)
	var battle_track := Sound.music_for(_world)
	var biome := Sound.current_biome()
	Sound.step_battle(0.0, config.battle_hold * 0.5)
	var held := Sound.in_battle()
	Sound.step_battle(0.0, config.battle_hold + 10.0)
	var after := Sound.music_for(_world)
	for enemy: Variant in crowd:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_check(quiet < config.battle_on and loud >= config.battle_on and biome != null and calm_track == biome.music
			and battle_track == biome.battle_music and held and after == biome.music and not Sound.in_battle(),
			"боевые слои: толпа у героя (%.2f) — боевой трек, утихло — держится %.0f с, потом эмбиент" % [loud, config.battle_hold])
	_world.waves.active = waves_were


## Шаг 11.10: пост-эффекты. Рана своего героя — красные края; удар на малом здоровье — ещё аберрация; пульс гаснет;
## выключенные в настройках пост-эффекты не рисуются.
func _check_post_fx() -> void:
	var post := _world.post
	var was := Settings.post_effects
	Settings.post_effects = true
	Settings.graphics_changed.emit()
	post.reset()
	post.hero_hurt(0.9)
	_check(post.hurt > 0.0 and post.aberration == 0.0, "пост-эффекты: рана — красные края, на полном здоровье без аберрации")
	post.hero_hurt(0.1)
	_check(post.aberration > 0.0, "пост-эффекты: удар на малом здоровье — аберрация")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(post._shift.visible, "пост-эффекты: аберрация рисуется, пока идёт пульс")
	await _seconds(1.0)
	_check(post.hurt == 0.0 and post.aberration == 0.0 and not post._shift.visible, "пост-эффекты: пульс гаснет")
	Settings.post_effects = false
	Settings.graphics_changed.emit()
	_check(not post.visible and not post.is_processing(), "пост-эффекты отключаются в настройках")
	Settings.post_effects = was
	Settings.graphics_changed.emit()


func _check_map_objects(knight: Player) -> void:
	_items_picked.clear()
	_dropped_rarities.clear()
	# Платный сундук: касание не открывает, нужен E и золото; цена растёт в 1.5 раза.
	var chest := await _visit(knight, Chest) as Chest
	_check(chest != null and not chest.used, "касание сундук не открывает — он платный")
	var economy := _world.economy
	_check(economy.chest_price(knight) == 100, "первый сундук стоит 100 золота")
	knight.gold = 99
	_check(chest != null and not _world.apply_interact(1, chest.object_id) and not chest.used and knight.gold == 99,
			"без 100 золота сундук не открыть (ФТ-16)")
	_check(not _world.apply_interact(4, chest.object_id), "открыть за несуществующего игрока нельзя (ФТ-16)")
	knight.gold = 1000
	_check(chest != null and _world.apply_interact(1, chest.object_id) and chest.used and knight.gold == 900
			and not _dropped_rarities.is_empty(), "сундук открыт за 100 золота, выпал предмет (CR-06)")
	_check(economy.chest_price(knight) == 150 and DataRegistry.ECONOMY.chest_price(2) == 225,
			"каждый следующий сундук дороже в 1.5 раза: 150, 225")
	_check(not _world.apply_interact(1, chest.object_id) and knight.gold == 900, "открытый сундук второй раз не открыть")
	# Шаг 11.20: объекты карты — спрайты из атласа, состояние меняет облик; метки уровня не видны.
	var portal: Portal = _world.props.get_children().filter(func(n: Node) -> bool: return n is Portal)[0]
	var art_ids := ["chest", "chest_open", "statue", "statue_empty", "trial_altar", "cursed_totem", "fountain", "obelisk",
			"portal", "portal_next", "shrine", "curse_altar", "barrel", "urn", "coffin", "hoard", "reliquary", "lore_book",
			"lore_corpse", "lore_inscription", "prisoner", "prisoner_open", "xp_1", "xp_2", "xp_3", "gold_1", "gold_2",
			"gold_3"] + DataRegistry.MERCHANTS.map(func(m: MerchantData) -> String: return "merchant_" + String(m.id))
	var no_art := art_ids.filter(func(id: String) -> bool: return not PropArt.has_prop(StringName(id)))
	_check(no_art.is_empty() and chest._art != null and chest._art.prop_id == &"chest_open" and portal._art != null
			and portal._art.prop_id == (&"portal_next" if portal.active else &"portal") and not _world.markers.visible,
			"объекты карты — спрайты атласа, открытый сундук открыт, меток не видно (нет: %s)" % [no_art])
	var far_chest := _world.spawn_prop({"kind": &"chest", "pos": knight.global_position + Vector2(400, 0), "id": 901}) as Chest
	_check(not _world.apply_interact(1, 901) and not far_chest.used, "издалека сундук не открыть")
	far_chest.queue_free()
	knight.gold = 0
	for child in _world.pickups.get_children():
		if child is Pickup and child.kind == Pickup.Kind.ITEM:
			knight.teleport(child.global_position)
			await _seconds(0.2)
			break
	_check(not _items_picked.is_empty() and not knight.equipment.is_empty() and knight.items_collected > 0,
			"предмет подобран: его характеристики копятся, на кукле — лучший предмет слота (CR-07)")

	var might_before := knight.stat(Player.STAT_MIGHT)
	if not _world.props.get_children().any(func(n: Node) -> bool: return n is Fountain):
		# шаг 8: на метке фонтана могло встать святилище — фонтан для проверки ставим сами
		_world.spawn_prop({"kind": &"fountain", "pos": knight.global_position + Vector2(60, 0), "id": 900})
	await _visit(knight, Fountain)
	_check(knight.buffs.has(Fountain.BUFF_ID) and knight.stat(Player.STAT_MIGHT) > might_before, "фонтан дал бафф")

	await _visit(knight, Obelisk)
	_check(_world.flow.obelisks_visited == 1, "обелиск засчитан")

	_dropped_rarities.clear()
	var statue := _find_prop(Statue) as Statue
	if statue == null:  # на метке статуи могло встать другое испытание — ставим статую сами
		statue = _world.spawn_prop({"kind": &"statue", "pos": knight.global_position + Vector2(0, 60), "id": 902}) as Statue
	knight.teleport(statue.global_position)
	await _seconds(0.3)
	_check(not statue.used, "статуя не просыпается от касания — нужно E")
	_check(_world.apply_interact(1, statue.object_id) and statue.used, "E — статуя пробуждена")
	var golem: Enemy = null
	for child in _world.enemies.get_children():
		if child is Enemy and child.data.id == Statue.GUARDIAN_ID:
			golem = child
	_check(golem != null, "статуя пробудилась мини-боссом")
	if golem != null:
		golem.take_damage(1.0e9, 1)
	await _frames(2)
	_check(_dropped_rarities.any(func(r: int) -> bool: return r >= ItemRoller.Rarity.RARE), "мини-босс статуи оставил редкий предмет")


## 17.10.2026: предметы копятся — каждый подобранный навсегда прибавляет свои характеристики, сумки нет; на кукле
## лучший предмет слота (легендарный не вытесняется обычным); характеристики предметов — небольшие (stack_power).
func _check_inventory(knight: Player) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var saved_doll := knight.equipment.duplicate()  # тестовая легендарка не должна остаться на кукле (её руна)
	_check(not knight.receive_item({"base": &"nope", "rarity": 0, "stats": {}}), "испорченный предмет не принят")
	var first := ItemRoller.roll(rng, ItemRoller.Rarity.MAGIC, 0, DataRegistry.LOOT_TABLE)
	var stat: StringName = first["stats"].keys()[0]
	var before_stat := knight.stat(stat)
	var before_items := knight.items_collected
	_check(knight.can_receive(first) and knight.receive_item(first)
			and is_equal_approx(knight.stat(stat), before_stat + float(first["stats"][stat]))
			and knight.items_collected == before_items + 1,
			"предмет подобран: %s прибавилось насовсем (%s)" % [stat, ItemRoller.stat_line(stat, first["stats"][stat])])
	var twin := first.duplicate(true)
	knight.receive_item(twin)
	_check(is_equal_approx(knight.stat(stat), before_stat + 2.0 * float(first["stats"][stat])),
			"второй такой же предмет — характеристики сложились")
	var slot := ItemRoller.slot_of(first)
	var rotblade := DataRegistry.unique_item(&"rotblade")
	var legend := {"base": rotblade.base.id, "rarity": ItemRoller.Rarity.LEGENDARY, "unique": rotblade.id,
			"affixes": [], "curse": &"", "stats": {}}
	var legend_slot := ItemRoller.slot_of(legend)
	knight.receive_item(legend)
	var plain := ItemRoller.roll(rng, ItemRoller.Rarity.NORMAL, 0, DataRegistry.LOOT_TABLE)
	while ItemRoller.slot_of(plain) != legend_slot:
		plain = ItemRoller.roll(rng, ItemRoller.Rarity.NORMAL, 0, DataRegistry.LOOT_TABLE)
	knight.receive_item(plain)
	_check(knight.equipment[legend_slot] == legend, "на кукле лучший предмет слота: обычный легендарный не вытесняет")
	_check(knight.equipment.has(slot), "на кукле — найденный предмет слота")
	# Характеристики предметов небольшие: доля stack_power от прежних (легендарка — тоже).
	var table := DataRegistry.LOOT_TABLE
	var legendary := ItemRoller.roll(rng, ItemRoller.Rarity.LEGENDARY, 0, table)
	var unique := ItemRoller.legendary(legendary)
	var scaled := true
	for key in unique.stats:
		scaled = scaled and absf(float(legendary["stats"][key]) - float(unique.stats[key]) * table.stack_power) < 0.06
	_check(table.stack_power < 0.5 and scaled, "предметы дают небольшой плюс: ×%.2f от прежних характеристик" % table.stack_power)
	# Кольца (18.10.2026): два пальца — первое кольцо на свободный, второе на другой, третье вместо слабейшего.
	knight.equipment.erase(ItemBaseData.Slot.RING)
	knight.equipment.erase(ItemBaseData.Slot.RING_2)
	var rings: Array[Dictionary] = []
	for rarity in [ItemRoller.Rarity.NORMAL, ItemRoller.Rarity.MAGIC, ItemRoller.Rarity.RARE]:
		var ring := ItemRoller.roll(rng, rarity, 0, table)
		while ItemRoller.slot_of(ring) != ItemBaseData.Slot.RING:
			ring = ItemRoller.roll(rng, rarity, 0, table)
		rings.append(ring)
		knight.receive_item(ring)
	_check(knight.equipment.get(ItemBaseData.Slot.RING) == rings[2] and knight.equipment.get(ItemBaseData.Slot.RING_2) == rings[1],
			"кольца: два пальца, новое кольцо вытесняет слабейшее")
	var ring_base := DataRegistry.item_base(&"ring")
	var untranslated: Array = []
	for affix: AffixData in DataRegistry.AFFIXES:
		if affix.kind == AffixData.Kind.PREFIX and tr(affix.display_key(ring_base)) == affix.display_key(ring_base):
			untranslated.append(affix.display_key(ring_base))
	_check(ring_base != null and ring_base.gender == &"n" and untranslated.is_empty(),
			"«Пылающее кольцо»: у префиксов есть форма среднего рода (нет: %s)" % [untranslated])
	knight.equipment = saved_doll
	knight._recalculate_stats()
	await _check_legendary_and_cursed(knight)


## Шаг 7: руна легендарки меняет навыки героя, проклятие «Гниение» не убивает, фильтр лута и звук дропа.
func _check_legendary_and_cursed(knight: Player) -> void:
	var slot := ItemBaseData.Slot.WEAPON
	var worn: Variant = knight.equipment.get(slot)
	var rotblade := DataRegistry.unique_item(&"rotblade")
	knight.equipment[slot] = {"base": rotblade.base.id, "rarity": ItemRoller.Rarity.LEGENDARY, "unique": rotblade.id,
			"affixes": [], "curse": &"", "stats": rotblade.stats.duplicate()}
	knight._recalculate_stats()
	var sword := DataRegistry.upgrade(knight.hero.starting_weapon) as SkillData
	_check(rotblade.modifier in knight.skill_modifiers(sword), "легендарка: её руна действует на навыки героя")
	var stats := SkillStats.compute(sword, maxi(knight.get_upgrade_level(sword.id), 1), knight, knight.skill_modifiers(sword))
	_check(stats.statuses.any(func(s: StatusApplication) -> bool: return s.status == &"poison"),
			"Клинок Гнили: удары навыка отравляют")
	if worn == null:
		knight.equipment.erase(slot)
	else:
		knight.equipment[slot] = worn
	knight._recalculate_stats()

	knight.add_bonus(&"test_rot", {&"regen": -100000.0})
	await _frames(10)
	_check(knight.alive and knight.health >= 1.0 and knight.health <= 1.01, "проклятие «Гниение»: здоровье тает, но не убивает")
	knight.bonuses.erase(&"test_rot")
	knight._recalculate_stats()
	knight.heal(knight.max_health)

	var filter_before := Settings.loot_filter
	Settings.loot_filter = 0
	var plain := _world.spawn_pickup({"kind": Pickup.Kind.ITEM, "pos": knight.global_position + Vector2(200, 200),
			"item": ItemRoller.roll(RandomNumberGenerator.new(), ItemRoller.Rarity.NORMAL, 0, DataRegistry.LOOT_TABLE)})
	_check(plain._label.visible, "фильтр «всё»: у обычного предмета видна подпись")
	Settings.loot_filter = ItemRoller.Rarity.MAGIC
	plain._apply_loot_filter()
	_check(not plain._label.visible, "фильтр лута прячет подпись обычного предмета (подобрать его можно)")
	Settings.loot_filter = filter_before
	plain.queue_free()
	var chime := LootSound.stream_for(ItemRoller.Rarity.LEGENDARY)
	_check(chime.data.size() > 1000 and LootSound.stream_for(ItemRoller.Rarity.CURSED) != chime,
			"звук дропа синтезирован по редкости")


func _check_elite(knight: Player) -> void:
	_blasts = 0
	var elite := _world.spawn_enemy({
		"id": &"skeleton", "pos": knight.global_position + Vector2(40, 0), "elite": ["explosive", "stone_skin"],
	})
	_check(elite.is_elite() and is_equal_approx(elite.max_health, elite.data.max_health * DataRegistry.BALANCE.elite_health_mult),
			"элита крепче обычного врага")
	_check(elite.get_children().any(func(n: Node) -> bool: return n is Label), "над элитой подпись с аффиксами")
	_check(elite.shows_health_bar(), "у элиты полоска здоровья видна всегда")
	elite.take_damage(1.0e9, 1)
	await _frames(2)
	_check(_blasts == 1, "взрывная элита после смерти оставила взрыв")
	# Врождённые повадки (враги по эскизам): поведение аффикса без статуса элиты.
	var bandit := _world.spawn_enemy({"id": &"bandit", "pos": knight.global_position + Vector2(-60, 0)})
	var golem := _world.spawn_enemy({"id": &"crypt_golem", "pos": knight.global_position + Vector2(-60, 40)})
	_check(bandit != null and not bandit.is_elite() and bandit._teleport != null
			and is_equal_approx(bandit.max_health, bandit.data.max_health * bandit.health_mult)
			and not bandit.get_children().any(func(n: Node) -> bool: return n is Label)
			and golem != null and is_equal_approx(golem._damage_taken_mult, 0.5),
			"врождённые повадки: бандит телепортируется, у голема каменная кожа — оба не элиты")
	for enemy in [bandit, golem]:
		if enemy != null:
			enemy.queue_free()


## Шаг 11.2: облик врага из атласа, удар рядом с героем, падение убитого доигрывается, союзник окрашен.
func _check_enemy_look(knight: Player) -> void:
	var zombie := _world.spawn_enemy({"id": &"zombie", "pos": knight.global_position + Vector2(10, 0), "hp_mult": 200.0})
	_check(zombie.body.region_enabled and zombie.body.texture == EnemyArt.texture, "враг нарисован листом из атласа врагов")
	var was_invulnerable := knight.invulnerable
	knight.invulnerable = true
	var swung := false
	for i in ceili(1.0 * Engine.physics_ticks_per_second):
		await _frames(1)
		swung = swung or (is_instance_valid(zombie) and zombie.is_attacking())
	knight.invulnerable = was_invulnerable
	_check(swung, "враг рядом с героем играет удар (шаг 11.2)")
	var before := _world.corpses.count()
	if is_instance_valid(zombie):
		zombie.take_damage(1.0e9, 1)
	await _frames(2)
	_check(_world.corpses.count() > before, "убитый враг доигрывает падение у всех (труп)")
	var ally := _world.spawn_enemy({"id": &"ghoul", "pos": knight.global_position + Vector2(-30, 0), "ally": true,
			"owner": knight.peer_id(), "life": 0.1})
	_check(ally.body.modulate.g > ally.body.modulate.r, "призванный союзник окрашен в призрачно-зелёный")


## CR-15: новое оружие — черепа на орбите, метеоры, кольцо холода; «Удача» — удачные удары.
## Герои «выключены», волны стоят: урон по цели наносит только проверяемое оружие.
func _check_new_weapons(knight: Player, party: Array[Player]) -> void:
	for p in party:
		p.alive = false
	_world.waves.active = false
	for child in _world.enemies.get_children():
		child.queue_free()
	await _frames(2)
	var plain := _world.spawn_enemy({"id": &"skeleton", "pos": knight.global_position + Vector2(-120, 0)})
	_check(not plain.shows_health_bar(), "у целого врага полоски здоровья нет")
	plain.take_damage(1.0, 1)
	_check(plain.shows_health_bar(), "у раненого врага видна полоска здоровья")
	plain.queue_free()
	await _frames(2)  # сетка врагов перестраивается в начале кадра физики, а тест тикает оружие раньше

	var show_numbers := Settings.show_damage_numbers
	Settings.show_damage_numbers = true
	var numbers := _world.get_node("DamageNumbers") as DamageNumbers
	knight.add_bonus(&"test_luck", {Player.STAT_CRIT: 1.0})
	for id: StringName in [&"orbiting_skulls", &"meteor", &"frost_ring", &"fireball", &"lightning_bolt",
			&"death_ripple", &"fire_nova", &"throwing_daggers", &"bone_spear", &"blood_whip", &"bat_swarm",
			&"acid_rain", &"reaper_sickle"]:
		var weapon: SkillData = DataRegistry.upgrade(id)
		var offset := 40.0  # сферы на орбите задевают только того, кто стоит на её кольце
		if weapon.action is OrbitAction:
			offset = weapon.range_at(1) * knight.area_mult()
		var target := _world.spawn_enemy({"id": &"stone_golem", "pos": knight.global_position + _free_offset(knight, offset), "hp_mult": 100.0})
		var runtime := SkillRuntime.new(weapon, 1)
		_crits = 0
		var slowed := false
		for i in 90:
			await get_tree().physics_frame
			runtime.tick(1.0 / Engine.physics_ticks_per_second, knight, _world)
			slowed = slowed or target.is_slowed()
		_check(target.health < target.max_health and _crits > 0, "оружие %s ранит врага, удача — двойной урон" % id)
		if id == &"frost_ring" or id == &"acid_rain":
			_check(slowed, "оружие %s замедляет врага" % id)
		target.queue_free()
		await _frames(2)
	_check(numbers.shown_total > 0, "над врагами всплывают цифры урона")
	knight.add_bonus(&"test_luck", {})
	await _check_new_skills(knight)
	var sickle := _world.spawn_projectile({
		"type": &"sickle", "pos": knight.global_position, "dir": Vector2.RIGHT, "speed": 230.0, "range": 100.0,
		"return": true, "pierce": 99, "owner": 1,
	}) as Projectile
	await _seconds(0.35)
	_check(is_instance_valid(sickle) and sickle.direction.x < 0.0, "серп долетел до края и возвращается")
	knight.add_bonus(&"test_luck", {})
	Settings.show_damage_numbers = show_numbers
	for child in _world.projectiles.get_children():
		child.queue_free()
	await _frames(2)
	for p in party:
		p.alive = true
	_world.waves.active = true


## Шаг 11.21: облик навыков — у каждого навыка есть эффект атласа для его действия и стихии; снаряд и след навыка
## несут id навыка вместо цвета и рисуются кадрами атласа, снаряд врага — кодом; попадание даёт искры стихии.
func _check_skill_vfx(knight: Player) -> void:
	_check(SkillVfx.available(), "атлас эффектов навыков загружен")
	var family := {&"cone": "slash", &"aura": "nova", &"chain": "chain", &"strike": "sigil", &"zone": "zone",
		&"beam": "beam", &"dash": "dash", &"trap": "trap"}
	var missing: Array = []
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		var skill := upgrade as SkillData
		if skill == null or skill.action == null or skill.action.kind() == &"summon":
			continue
		var look := SkillVfx.look_of(skill.id)
		var kind := skill.action.kind()
		var clip: SkillVfx.Clip = null
		if kind == &"projectile":
			var shape := skill.fx_kind if skill.fx_kind != &"" else (skill.action as ProjectileAction).default_look
			clip = SkillVfx.pick("proj_" + String(shape), look.element)
		elif kind == &"orbit":
			clip = SkillVfx.clip(StringName("orb_" + (String(skill.fx_kind) if skill.fx_kind != &"" else "skull")))
		elif family.has(kind):
			clip = SkillVfx.pick(family[kind], look.element)
		if clip == null:
			missing.append(skill.id)
	_check(missing.is_empty(), "у каждого навыка есть облик в атласе эффектов %s" % [missing])
	var fire := DataRegistry.upgrade(&"fireball") as SkillData
	_check(SkillVfx.look_of(&"fireball").element == &"fire" and SkillVfx.look_of(&"inferno").evolved,
			"стихия облика — по тегам навыка, эволюция — с золотым блеском")
	var ball := _world.spawn_projectile({
		"type": &"fireball", "pos": knight.global_position + Vector2(0, -200), "dir": Vector2.UP, "speed": 10.0,
		"range": 50.0, "owner": 1, "skill": &"fireball",
	}) as Projectile
	var shard := _world.spawn_projectile({
		"type": &"shard", "pos": knight.global_position + Vector2(0, -200), "dir": Vector2.UP, "speed": 10.0,
		"range": 50.0, "hostile": true, "color": Color.RED,
	}) as Projectile
	_check(ball._look != null and ball.material == SkillVfx.material and ball.color == fire.fx_color
			and shard._look == null and shard.material == null,
			"снаряд навыка — кадры атласа и цвет навыка без цвета в данных, снаряд врага — код")
	var nova := _world.spawn_projectile({"type": &"nova", "pos": knight.global_position, "radius": 40.0, "owner": 1,
		"skill": &"plague_aura"}) as CombatFx
	_check(nova != null and nova._look != null and nova._look.element == &"poison", "аура — волна nova стихией навыка")
	var before := _world.skill_fx.count()
	ball._impact(ball.global_position)
	_check(_world.skill_fx.count() == before + 1, "попадание снаряда — искры стихии в слое эффектов")
	for node: Node in [ball, shard, nova]:
		if is_instance_valid(node):
			node.queue_free()
	await _frames(2)


## Шаг 3: модульные навыки — действия, руны (теги, действия, числа, приёмы снарядов), 10 новых навыков
## на новых действиях, черта класса. Герои «выключены», волны стоят (см. _check_new_weapons).
func _check_new_skills(knight: Player) -> void:
	var kinds := {}
	var base_skills := 0
	var no_action: Array = []
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		var skill := upgrade as SkillData
		if skill == null:
			continue
		if skill.action == null:
			no_action.append(skill.id)
			continue
		kinds[skill.action.kind()] = true
		if not skill.is_evolution:
			base_skills += 1
	_check(no_action.is_empty() and kinds.size() == 11, "у каждого навыка есть действие, видов действий %d %s" % [kinds.size(), no_action])
	_check(base_skills >= 37 and DataRegistry.SKILL_MODIFIERS.size() >= 40,
			"навыков %d (без эволюций), рун %d" % [base_skills, DataRegistry.SKILL_MODIFIERS.size()])
	var no_evolution: Array = []
	for id: StringName in STEP3_SKILLS:
		var skill: SkillData = DataRegistry.upgrade(id)
		if skill.evolution == null or not skill.evolution.is_evolution:
			no_evolution.append(id)
	_check(no_evolution.is_empty(), "у 10 навыков шага 3 есть облик эволюции %s" % [no_evolution])

	var sword: SkillData = DataRegistry.upgrade(&"sword_arc")
	var arrow: SkillData = DataRegistry.upgrade(&"bone_arrow")
	var pierce := DataRegistry.skill_modifier(&"rune_pierce")
	var inferno := DataRegistry.skill_modifier(&"rune_inferno")
	_check(not SkillStats.fits(pierce, DataRegistry.tag_mask(sword.tags), sword.action.kind())
			and SkillStats.fits(pierce, DataRegistry.tag_mask(arrow.tags), arrow.action.kind())
			and SkillStats.fits(inferno, DataRegistry.tag_mask([&"fire"]), &"projectile")
			and not SkillStats.fits(inferno, DataRegistry.tag_mask(sword.tags), &"cone"),
			"руны подходят навыкам по действию и тегам")
	_check(not knight.add_rune(&"sword_arc", &"rune_pierce") and not knight.add_rune(&"sword_arc", &"no_such_rune"),
			"неподходящую или несуществующую руну не вставить")

	var bolts: SkillData = DataRegistry.upgrade(&"silver_bolts")
	var plain := SkillStats.compute(bolts, 1, knight)
	_check(plain.ricochet == 2 and plain.modifiers.size() == 1, "у серебряных болтов встроенная руна рикошета")
	_check(knight.add_rune(&"silver_bolts", &"rune_might") and knight.add_rune(&"silver_bolts", &"rune_volley"), "руны вставлены")
	var boosted := SkillStats.compute(bolts, 1, knight, knight.skill_modifiers(bolts))
	_check(is_equal_approx(boosted.damage, plain.damage * 1.2) and boosted.amount == plain.amount + 1,
			"руны силы и залпа: урон ×1.2, +1 снаряд (%.1f → %.1f, %d → %d)" % [plain.damage, boosted.damage, plain.amount, boosted.amount])
	knight.runes.clear()

	var flags := {}
	for id: StringName in STEP3_SKILLS:
		var skill: SkillData = DataRegistry.upgrade(id)
		var dir := _free_offset(knight, 40.0).normalized()
		var target := _world.spawn_enemy({"id": &"stone_golem", "pos": knight.global_position + dir * 40.0, "hp_mult": 100.0})
		var behind: Enemy = null
		if id == &"silver_bolts":
			behind = _world.spawn_enemy({"id": &"stone_golem", "pos": knight.global_position + dir * 100.0, "hp_mult": 100.0})
		await _frames(2)
		var runtime := SkillRuntime.new(skill, 1)
		for i in 150:
			await get_tree().physics_frame
			runtime.tick(1.0 / Engine.physics_ticks_per_second, knight, _world)
			if is_instance_valid(target):
				flags["%s:oil" % id] = flags.get("%s:oil" % id, false) or _world.statuses.stacks_of(target, &"oil") > 0
				flags["%s:burn" % id] = flags.get("%s:burn" % id, false) or _world.statuses.stacks_of(target, &"burn") > 0
				flags["%s:stun" % id] = flags.get("%s:stun" % id, false) or target.is_stunned()
		_check(is_instance_valid(target) and target.health < target.max_health, "навык %s (%s) ранит врага" % [id, skill.action.kind()])
		if behind != null:
			_check(behind.health < behind.max_health, "серебряный болт отскочил ко второму врагу (рикошет)")
			behind.queue_free()
		if id == &"ghoul_pack":
			var ghouls := _world.enemies.get_children().filter(func(n: Node) -> bool:
				return n is Enemy and n.ally and n.owner_peer == knight.peer_id() and n.data_id == &"ghoul")
			_check(not ghouls.is_empty(), "упыри призваны союзниками героя (%d)" % ghouls.size())
		for child in _world.enemies.get_children():
			if child is Enemy and child.ally:
				child.queue_free()
		target.queue_free()
		for child in _world.projectiles.get_children():
			child.queue_free()
		await _frames(2)
	_check(flags.get("oil_flask:oil", false), "горючая смесь обливает маслом")
	_check(flags.get("bear_trap:stun", false), "капкан оглушает")
	_check(flags.get("flame_dash:burn", false), "огненный рывок поджигает")

	# Шаг 4: 10 новых навыков (1 ур.) и 10 эволюций (10 ур.) — каждый ранит врага; сам бой — до первого удара.
	for id: StringName in STEP4_SKILLS:
		var skill: SkillData = DataRegistry.upgrade(id)
		var level := 10 if skill.is_evolution else 1
		var offset := 40.0
		if skill.action is OrbitAction:
			offset = skill.range_at(level) * knight.area_mult()
		var target := _world.spawn_enemy({"id": &"stone_golem", "pos": knight.global_position + _free_offset(knight, offset), "hp_mult": 100.0})
		await _frames(2)
		var runtime := SkillRuntime.new(skill, level)
		var hurt := false
		for i in 150:
			await get_tree().physics_frame
			runtime.tick(1.0 / Engine.physics_ticks_per_second, knight, _world)
			if is_instance_valid(target) and target.health < target.max_health:
				hurt = true
				break
		_check(hurt, "навык %s (%s, %d ур.) ранит врага" % [id, skill.action.kind(), level])
		if id == &"bone_legion":
			_check(_world.enemies.get_children().any(func(n: Node) -> bool:
				return n is Enemy and n.ally and n.data_id == &"bone_soldier"), "костяной легион призвал солдат")
		for child in _world.enemies.get_children():
			if child is Enemy and child.ally:
				child.queue_free()
		target.queue_free()
		for child in _world.projectiles.get_children():
			child.queue_free()
		await _frames(2)

	# Раскол: каждый попавший кинжал раскалывается на 3 осколка.
	var daggers := [0]
	var count_daggers := func(node: Node) -> void:
		if node is Projectile and node.kind == &"dagger":
			daggers[0] += 1
	_world.projectiles.child_entered_tree.connect(count_daggers)
	_check(knight.add_rune(&"throwing_daggers", &"rune_split"), "руна раскола вставлена в метательные кинжалы")
	var golem := _world.spawn_enemy({"id": &"stone_golem", "pos": knight.global_position + _free_offset(knight, 40.0), "hp_mult": 100.0})
	await _frames(2)
	var daggers_rt := SkillRuntime.new(DataRegistry.upgrade(&"throwing_daggers"), 1)
	for i in 30:
		await get_tree().physics_frame
		daggers_rt.tick(1.0 / Engine.physics_ticks_per_second, knight, _world)
	_world.projectiles.child_entered_tree.disconnect(count_daggers)
	_check(daggers[0] >= 2 + 3, "раскол: за один залп кинжалов %d (2 + осколки)" % daggers[0])
	knight.runes.clear()
	golem.queue_free()

	# Трупный взрыв: Кровавая вспышка добивает слабого врага — тот взрывается.
	var weak := _world.spawn_enemy({"id": &"zombie", "pos": knight.global_position + _free_offset(knight, 30.0), "hp_mult": 0.01})
	await _frames(2)
	var nova := SkillRuntime.new(DataRegistry.upgrade(&"crimson_nova"), 1)
	var blast := false
	for i in 30:
		await get_tree().physics_frame
		nova.tick(1.0 / Engine.physics_ticks_per_second, knight, _world)
		for child in _world.projectiles.get_children():
			blast = blast or (child is Projectile and child.kind == &"blast" and child.color == Enemy.KILL_BLAST_COLOR)
	_check(not is_instance_valid(weak) or weak.dead, "кровавая вспышка добила слабого врага")
	_check(blast, "убитый кровавой вспышкой взорвался (трупный взрыв)")
	for child in _world.projectiles.get_children():
		child.queue_free()

	# Черта класса: Пиромант — +10 % области, огненные навыки поджигают и бьют сильнее.
	var pyro := _world.spawn_player(4, DataRegistry.hero(&"pyromancer"))
	pyro.invulnerable = true
	pyro.alive = false  # его навыки в этой проверке не стреляют
	await _frames(1)
	var beam: SkillData = DataRegistry.upgrade(&"fire_beam")
	var pyro_beam := SkillStats.compute(beam, 1, pyro, pyro.skill_modifiers(beam))
	var pyro_sword := SkillStats.compute(sword, 1, pyro, pyro.skill_modifiers(sword))
	_check(pyro.get_upgrade_level(&"fire_beam") >= 1 and is_equal_approx(pyro.stat(Player.STAT_AREA), 0.1),
			"Пиромант начинает с луча пламени, черта класса: +10 % области")
	_check(pyro_beam.statuses.size() == beam.on_hit.size() + 1 and is_equal_approx(pyro_beam.damage, beam.damage_at(1) * 1.1)
			and pyro_sword.statuses.size() == sword.on_hit.size(),
			"Пиромания действует только на огненные навыки")
	pyro.queue_free()
	await _frames(2)


## CR-15: Шипы, Уклонение, Стойкость, Вампиризм; пассивки видны на панели справа.
## Некромант без улучшений: его урон считается без чужих бонусов.
func _check_defensive_passives(knight: Player, necromancer: Player) -> void:
	necromancer.invulnerable = false
	var biter := _world.spawn_enemy({"id": &"zombie", "pos": necromancer.global_position + Vector2(200, 0)})
	necromancer.add_bonus(&"test", {Player.STAT_THORNS: 5.0})
	necromancer.take_damage(4.0, biter)
	_check(biter.health < biter.max_health, "Шипы ранят врага, ударившего вплотную")
	biter.queue_free()

	necromancer.add_bonus(&"test", {Player.STAT_RESILIENCE: 0.5})
	necromancer.health = necromancer.max_health
	necromancer.take_damage(20.0)
	_check(is_equal_approx(necromancer.max_health - necromancer.health, 10.0), "Стойкость 50%: из 20 урона прошло 10")

	necromancer.add_bonus(&"test", {Player.STAT_DODGE: 1.0})
	var dodged := 0
	for i in 200:
		necromancer.health = necromancer.max_health
		necromancer.take_damage(1.0)
		if is_equal_approx(necromancer.health, necromancer.max_health):
			dodged += 1
	_check(dodged > 60 and dodged < 140, "Уклонение не больше 50%% (увернулся %d из 200)" % dodged)
	necromancer.add_bonus(&"test", {})
	necromancer.health = necromancer.max_health
	necromancer.invulnerable = true

	knight.add_bonus(&"test", {Player.STAT_LIFESTEAL: 0.5})
	knight.health = knight.max_health * 0.5
	var before := knight.health
	# Обычный враг: на мини-босса и элиту действует «Губитель великанов», если он выпал картой.
	var dummy := _world.spawn_enemy({"id": &"zombie", "pos": knight.global_position + Vector2(300, 0), "hp_mult": 10.0})
	dummy.take_damage(20.0, 1)
	_check(is_equal_approx(knight.health - before, 10.0), "Вампиризм 50%: удар на 20 вернул 10 здоровья")
	dummy.queue_free()
	knight.add_bonus(&"test", {})
	knight.health = knight.max_health

	knight.apply_upgrade(DataRegistry.upgrade(&"thorns"), 3)
	var hud_passives: PassivesPanel = _world.get_node("HUD").passives
	_check(knight.get_upgrade_level(&"thorns") == 3 and hud_passives.entries().has(DataRegistry.upgrade(&"thorns")),
			"пассивка копится (+3 ур. картой) и видна на панели справа")


## Каждая следующая волна выпускает врагов крепче, а боссов рост волн не касается.
func _check_wave_scaling() -> void:
	var waves := _world.waves
	var skeleton := DataRegistry.enemy(&"skeleton")
	var pos := _world.player_spawn_position() + Vector2(0, -400)
	var first := waves.spawn_enemy(skeleton, pos, [], 0)
	var later := waves.spawn_enemy(skeleton, pos, [], 3)
	var ratio := later.max_health / first.max_health
	_check(is_equal_approx(ratio, 1.0 + 3 * DataRegistry.BALANCE.health_growth_per_wave) and later.damage_mult > first.damage_mult,
			"4-я волна крепче 1-й в %.2f раза — рост умеренный" % ratio)
	_check(is_equal_approx(first._speed, skeleton.speed * DataRegistry.BALANCE.enemy_speed_mult)
			and DataRegistry.BALANCE.enemy_speed_mult <= 0.8 and DataRegistry.BALANCE.enemy_projectile_speed_mult < 1.0,
			"враги медленнее на 20 %%: %.1f вместо %.1f; снаряды врагов ×%.2f" % [first._speed, skeleton.speed,
			DataRegistry.BALANCE.enemy_projectile_speed_mult])
	first.queue_free()
	later.queue_free()
	var expected := DataRegistry.BALANCE.xp_mult(GameState.level_index, waves.wave_stage())
	var total := 0
	for i in 2000:
		total += waves.xp_reward(1)
	_check(absf(total / 2000.0 - expected) < 0.05 and waves.xp_reward(10) >= 10,
			"опыт за врага растёт с глубиной и волной: ×%.2f (ждали ×%.2f)" % [total / 2000.0, expected])
	var balance := DataRegistry.BALANCE
	_check(balance.cycle_health_at(0) == 1.0 and is_equal_approx(balance.cycle_health_at(1), balance.cycle_health_mult)
			and is_equal_approx(balance.cycle_health_at(2), balance.cycle_health_mult * balance.cycle_health_mult)
			and balance.cycle_health_mult >= 1.5,
			"каждый круг — враги и боссы крепче: ×%.2f, ×%.2f" % [balance.cycle_health_at(1), balance.cycle_health_at(2)])
	_check(Player.xp_to_next(1) == 5 and Player.xp_to_next(2) == 12, "прокачка чуть медленнее: 5, 12, 19… опыта")
	var linear := balance.xp_first + balance.xp_step * (balance.xp_late_from + 29)
	_check(Player.xp_to_next(balance.xp_late_from) == balance.xp_first + balance.xp_step * (balance.xp_late_from - 1)
			and Player.xp_to_next(balance.xp_late_from + 30) > linear * 2,
			"после %d-го уровня опыт дорожает: на %d-м %d вместо %d" % [balance.xp_late_from, balance.xp_late_from + 30,
			Player.xp_to_next(balance.xp_late_from + 30), linear])

	# Победа над боссом уровня: весь опыт и золото на земле летят к героям.
	var hero := _world.local_player()
	var far := hero.global_position + Vector2(0, 700)
	var gem := _world.spawn_pickup({"kind": Pickup.Kind.XP, "pos": far, "value": 1})
	var coin := _world.spawn_pickup({"kind": Pickup.Kind.GOLD, "pos": far + Vector2(20, 0), "value": 3})
	var gold_before := hero.gold
	_world.flow.collect_level_loot()
	await _wait_until(func() -> bool: return not is_instance_valid(gem) and not is_instance_valid(coin), 8.0)
	_check(not is_instance_valid(gem) and not is_instance_valid(coin) and hero.gold > gold_before,
			"после босса уровня весь опыт и золото с локации собраны")


## CR-14: золото с элит, «Алчность», траты.
func _check_gold(knight: Player) -> void:
	var gold_before := knight.gold
	var elite := _world.spawn_enemy({"id": &"skeleton", "pos": knight.global_position + Vector2(30, 0), "elite": ["fast"]})
	elite.take_damage(1.0e9, 1)
	await _seconds(1.0)
	_check(knight.gold > gold_before, "элита оставила золото, монеты подобраны (CR-14)")
	knight.add_bonus(&"test_greed", {Player.STAT_GOLD_GAIN: 1.0})
	gold_before = knight.gold
	var expected := 10.0 * (1.0 + knight.stat(Player.STAT_GOLD_GAIN))
	_world.economy.collect_gold(knight, 10)
	_check(knight.gold - gold_before >= floori(expected) and knight.gold - gold_before <= ceili(expected),
			"«Алчность» увеличивает подобранное золото")
	knight.add_bonus(&"test_greed", {})
	gold_before = knight.gold
	_check(not knight.spend_gold(gold_before + 1) and knight.gold == gold_before, "потратить больше, чем есть, нельзя")


## CR-14: два торговца в разных частях карты; покупка, продажа, пояс зелий — с проверкой на хосте (ФТ-16).
func _check_merchants(knight: Player) -> void:
	var economy := _world.economy
	var artifacts := economy.find_merchant(LevelFlow.ARTIFACT_MERCHANT)
	var alchemist := economy.find_merchant(LevelFlow.ALCHEMIST)
	_check(_world.flow.merchants.size() == 2 and artifacts != null and alchemist != null,
			"на уровне торговец артефактами и алхимик")
	if artifacts == null or alchemist == null:
		return
	var reachable := true
	for m in _world.flow.merchants:
		var cell := _world.director.world_to_cell(m.global_position)
		reachable = reachable and _world.director.spawn_distance(cell) != EnemyDirector.UNREACHABLE
	_check(reachable, "до торговцев можно дойти от точки появления")
	_check(artifacts.global_position.distance_to(alchemist.global_position) >= 3.0 * Palette.tile_size(),
			"торговцы стоят в разных частях карты")

	var item_index := _offer_index(artifacts, Merchant.OFFER_ITEM)
	var stand := Vector2(0, 10)
	knight.gold = 0
	knight.teleport(artifacts.global_position + stand)
	_check(not economy.apply_buy(1, artifacts.merchant_id, item_index), "без золота покупка отклонена (ФТ-16)")
	knight.gold = 5000
	knight.teleport(alchemist.global_position + stand)
	_check(not economy.apply_buy(1, artifacts.merchant_id, item_index), "издалека покупка отклонена (ФТ-16)")
	knight.teleport(artifacts.global_position + stand)
	_check(not economy.apply_buy(4, artifacts.merchant_id, item_index), "покупка за несуществующего игрока отклонена")
	var price: int = artifacts.offers[item_index]["price"]
	var owned := knight.items_collected
	_check(economy.apply_buy(1, artifacts.merchant_id, item_index) and knight.gold == 5000 - price
			and knight.items_collected == owned + 1, "предмет куплен за золото — его характеристики прибавились")
	_check(not economy.apply_buy(1, artifacts.merchant_id, item_index), "проданный товар второй раз не купить")
	_items_picked.clear()
	_check(economy.apply_buy(1, artifacts.merchant_id, _offer_index(artifacts, &"mystery_bundle"))
			and _items_picked.size() == 1 and _items_picked[0]["rarity"] >= ItemRoller.Rarity.MAGIC,
			"загадочный свёрток — случайный предмет не ниже магического")
	_check(not economy.has_method(&"apply_sell") and not economy.has_method(&"submit_sell"),
			"торговцы лут не скупают — продажи нет")

	knight.teleport(alchemist.global_position + stand)
	var potion := _offer_index(alchemist, &"healing_potion")
	knight.potions = Player.BELT_SIZE
	_check(not economy.apply_buy(1, alchemist.merchant_id, potion), "в полный пояс зелье не купить")
	knight.potions = 0
	_check(economy.apply_buy(1, alchemist.merchant_id, potion) and knight.potions == 1, "зелье куплено в пояс")
	knight.health = knight.max_health * 0.3
	var health_before := knight.health
	_check(economy.apply_drink(1) and knight.health > health_before and knight.potions == 0, "Q: зелье выпито, здоровье восстановлено")
	_check(not economy.apply_drink(1), "пустой пояс — пить нечего")
	_check(economy.apply_buy(1, alchemist.merchant_id, _offer_index(alchemist, &"elixir_might"))
			and knight.buffs.has(&"elixir_might"), "эликсир алхимика дал бафф")
	var level_before := knight.level
	_check(economy.apply_buy(1, alchemist.merchant_id, _offer_index(alchemist, &"fruit_of_knowledge"))
			and knight.level == level_before + 1, "плод Древа знаний — новый уровень")

	# Окно торговца: у торговца экипировкой описание всплывает рядом со строкой товара, колонки нет;
	# у алхимика — колонка описания, как раньше.
	var shop := _world.get_node("ShopPanel") as ShopPanel
	knight.teleport(artifacts.global_position + stand)
	shop.open(artifacts)
	await _frames(4)
	_check(not shop.details.visible and shop.tips.is_showing(), "торговец экипировкой: описание товара — всплывающее окно")
	shop.close()
	knight.teleport(alchemist.global_position + stand)
	shop.open(alchemist)
	await _frames(4)
	_check(shop.details.visible and not shop.tips.is_showing(), "алхимик: описание товара колонкой, как раньше")
	shop.close()
	knight.gold = 0
	await _frames(2)


## CR-15: переброс карт левел-апа за золото; цена растёт; без золота и без предложения — отказ (ФТ-16).
func _check_reroll(knight: Player) -> void:
	_auto_pick = false
	await _frames(2)
	_drain_offers()
	_offers.clear()
	_world.upgrades.grant_xp(knight, Player.xp_to_next(knight.level), false)
	_check(_offers.size() == 1, "повышение уровня — предложение карт")
	knight.gold = 0
	_check(not _world.upgrades.apply_reroll(1), "переброс без золота отклонён (ФТ-16)")
	var cost := _world.economy.reroll_cost(knight)
	knight.gold = cost
	_check(_world.upgrades.apply_reroll(1) and knight.gold == 0 and _offers.size() == 2
			and (_offers[1][1] as Array).size() == 3 and knight.rerolls == 1, "переброс за золото — новые 3 карты")
	_check(_world.economy.reroll_cost(knight) > cost, "следующий переброс дороже")
	_check(not _world.upgrades.apply_reroll(2), "переброс без предложения отклонён")
	_drain_offers()
	_auto_pick = true


## Смещение от героя на distance в сторону, где до цели и за ней пол: враг не упрётся в стену.
func _free_offset(player: Player, distance: float) -> Vector2:
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var free := true
		for step in range(8, int(distance) + 24, 8):
			free = free and not _world.is_blocked(player.global_position + dir * step)
		if free:
			return dir * distance
	return Vector2.RIGHT * distance


## CR-17: изгнание карты — хост проверяет предложение и заряды; на место изгнанной встаёт другая.
func _check_banish(knight: Player) -> void:
	_auto_pick = false
	await _frames(2)
	_drain_offers()
	_offers.clear()
	_world.upgrades.grant_xp(knight, Player.xp_to_next(knight.level), false)
	var offer: Array = _world.upgrades.current_offer(1)
	var target := StringName()
	for card: Dictionary in (_offers[0][1] if not _offers.is_empty() else []):
		if UpgradePool.can_banish(card["id"], card["evolution"]):
			target = card["id"]
	var left := knight.banishes_left
	_check(left == DataRegistry.UPGRADE_RULES.banishes and target != &"", "у героя %d изгнания на забег" % left)
	_check(not _world.upgrades.apply_banish(1, &"no_such_card"), "изгнание карты не из предложения отклонено (ФТ-16)")
	_check(not _world.upgrades.apply_banish(2, target), "изгнание без своего предложения отклонено")
	_check(_world.upgrades.apply_banish(1, target), "карта изгнана")
	var after: Array = _world.upgrades.current_offer(1)
	var unique := {}
	var kept := 0
	for id in after:
		unique[id] = true
		if id != target and id in offer:
			kept += 1
	_check(knight.banishes_left == left - 1 and UpgradePool.banish_key(target) in knight.banished and not target in after
			and unique.size() == 3 and kept == 2, "на месте изгнанной — другая карта, две остальные на месте")
	knight.banishes_left = 0
	var another := StringName()
	for card: Dictionary in _offers.back()[1]:
		if UpgradePool.can_banish(card["id"], card["evolution"]):
			another = card["id"]
	_check(another == &"" or not _world.upgrades.apply_banish(1, another), "без зарядов изгнание отклонено")
	knight.banishes_left = DataRegistry.UPGRADE_RULES.banishes
	knight.banished.clear()
	_drain_offers()
	_auto_pick = true


## Карты левел-апа с самыми длинными текстами: текст в рамке карты, окно целиком на экране 640×360.
## Два худших случая: повышение уровня (строки «было → станет») и новый навык (статусы, руны, резонансы).
func _check_level_up_layout() -> void:
	_auto_pick = false
	await _frames(2)
	_drain_offers()
	var panel := _world.get_node("LevelUpPanel")
	var by_length := func(a: UpgradeData, b: UpgradeData) -> bool:
		return tr(a.description_key).length() > tr(b.description_key).length()
	var upgrades: Array = DataRegistry.UPGRADES.duplicate()
	upgrades.sort_custom(by_length)
	var skills: Array = upgrades.filter(func(u: UpgradeData) -> bool: return u is SkillData and not u.is_evolution)
	# Шаг 11.18: у карты эволюции — два значка «база → эволюция» в строке названия.
	var evolutions: Array = upgrades.filter(func(u: UpgradeData) -> bool: return u is SkillData and u.is_evolution)
	for setup: Array in [[upgrades, 1, false], [skills, 0, false], [evolutions, 0, true]]:
		var cards: Array = []
		for upgrade: UpgradeData in (setup[0] as Array).slice(0, UpgradePool.CARD_COUNT):
			var from: int = setup[1]
			cards.append({"id": upgrade.id, "from": from, "level": mini(from + 3, maxi(upgrade.max_level, from + 1)),
					"rarity": UpgradePool.Rarity.EPIC, "evolution": setup[2], "stage": 2 if setup[2] else 0})
		Events.level_up_offered.emit(1, cards)
		await _frames(12)  # подгонка карт меряет текст кадром позже и может пару раз уменьшить шрифт
		var names := ", ".join(cards.map(func(card: Dictionary) -> String: return String(card["id"])))
		_check(panel.visible and panel.cards_fit(), "левел-ап: самые длинные карты (%s) влезают в рамку и на экран" % names)
	# Карты ступеней эволюции: самые длинные названия навыков, ступень перед превращением (строка об облике).
	var by_name := func(a: UpgradeData, b: UpgradeData) -> bool: return tr(a.name_key).length() > tr(b.name_key).length()
	var with_form: Array = skills.filter(func(u: SkillData) -> bool: return u.evolution != null)
	with_form.sort_custom(by_name)
	var stage_cards: Array = []
	for skill: SkillData in with_form.slice(0, UpgradePool.CARD_COUNT):
		stage_cards.append({"id": UpgradePool.evolution_card_id(skill.id), "skill": skill.id, "from": 0, "level": 1,
				"stage": 1, "rarity": UpgradePool.Rarity.COMMON, "evolution": true})
	Events.level_up_offered.emit(1, stage_cards)
	await _frames(12)
	_check(panel.visible and panel.cards_fit() and panel.get_node("%Cards").get_child_count() == 3,
			"левел-ап: карты ступеней эволюции влезают в рамку и на экран")
	panel.hide()
	_world.request_pause(&"level_up", false)
	_offers.clear()
	_auto_pick = true


## Кооператив (14.10.2026): отложенный выбор улучшения — окно не всплывает само, внизу HUD подсказка, R открывает,
## R и Esc — «позже», после выбора следующее ждущее предложение открывается само. В одиночной игре проверяется
## с LevelUpPanel.defer_always (в сети он включён всегда).
func _check_deferred_level_up(knight: Player) -> void:
	_auto_pick = false
	await _frames(2)
	_drain_offers()
	var panel := _world.get_node("LevelUpPanel")
	var hud := _world.get_node("HUD")
	panel.defer_always = true
	panel._stored = []
	_world.upgrades.grant_xp(knight, Player.xp_to_next(knight.level) - knight.xp + Player.xp_to_next(knight.level + 1), false)
	await _frames(3)
	_check(not panel.visible and panel.has_offer() and knight.pending_choices == 2 and not get_tree().paused
			and hud._level_hint.visible and hud._level_hint.text.contains("2"),
			"кооп: окно улучшения само не всплывает, ждут 2 выбора, в HUD подсказка «%s»" % hud._level_hint.text)
	_press(KEY_R)
	await _frames(2)
	var opened: bool = panel.visible  # подсказку HUD здесь не сверить: в одиночной игре окно ставит мир на паузу
	_press(KEY_R)
	await _frames(2)
	var closed: bool = not panel.visible and panel.has_offer() and knight.pending_choices == 2
	_press(KEY_R)
	await _frames(2)
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(2)
	var esc_closed: bool = not panel.visible and panel.has_offer()
	_check(opened and closed and esc_closed, "R открывает окно, R и Esc закрывают — предложение ждёт у хоста %s"
			% [[opened, closed, esc_closed]])
	panel.open_offer()
	await _frames(1)
	(panel._card_buttons[0] as Button).pressed.emit()
	await _frames(4)
	_check(knight.pending_choices == 1 and panel.visible, "после выбора следующее ждущее предложение открылось само")
	(panel._card_buttons[0] as Button).pressed.emit()
	await _frames(4)
	_check(knight.pending_choices == 0 and not panel.visible and not panel.has_offer() and not hud._level_hint.visible,
			"все выборы сделаны — окно и подсказка скрыты")
	panel.defer_always = false
	_drain_offers()
	_auto_pick = true


func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	var up := event.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


## Шаги 11.18 и 11.26: значки всех навыков, пассивок и рун в атласе; новая эволюция в сборке — вспышка ячейки
## и сигнал для баннера.
func _check_skill_icons(knight: Player) -> void:
	var missing := DataRegistry.UPGRADES.filter(func(u: Variant) -> bool:
		return u is UpgradeData and not ItemIcon.has_icon((u as UpgradeData).icon_name())).map(
		func(u: UpgradeData) -> String: return String(u.id))
	for rune: SkillModifier in DataRegistry.SKILL_MODIFIERS:
		if not ItemIcon.has_icon(rune.icon_name()):
			missing.append(String(rune.id))
	var grid := SkillGrid.new()
	add_child(grid)
	grid.player = knight
	await _frames(2)
	var evolved: Array = []
	grid.evolved.connect(func(skill: SkillData, _stage: int) -> void: evolved.append(skill.id))
	var evolution: SkillData = DataRegistry.UPGRADES.filter(func(u: Variant) -> bool:
		return u is SkillData and u.is_evolution and not knight.upgrade_levels.has(u.id))[0]
	knight.upgrade_levels[evolution.id] = 1
	await _frames(2)
	var flashing := grid._flash.has(evolution.id)
	# Новая ступень эволюции взятого навыка — тоже вспышка и баннер.
	var held: StringName = grid.skills()[0].id
	var held_stage := knight.evolution_stage(held)
	knight.evolution_stages[held] = held_stage + 1
	await _frames(2)
	var stage_flash := grid._flash.has(held)
	knight.evolution_stages[held] = held_stage
	knight.upgrade_levels.erase(evolution.id)
	grid.queue_free()
	_check(missing.is_empty() and evolved == [evolution.id, held] and flashing and stage_flash,
			"значки навыков, пассивок и рун в атласе (нет: %s); эволюция и новая ступень — вспышка и баннер %s" % [missing, evolved])


## Шаг 4: карта руны в предложении хоста, панель её показывает, выбор вставляет руну (ФТ-16), изгнание
## убирает руну целиком; эволюция забирает руны навыка; резонанс — в характеристиках героя.
func _check_runes(knight: Player) -> void:
	var rules := DataRegistry.UPGRADE_RULES
	_auto_pick = false
	await _frames(2)
	_drain_offers()
	knight.level = maxi(knight.level, rules.rune_unlock_level)
	var rune_card := await _offer_with_rune(knight)
	_check(not rune_card.is_empty() and rune_card["level"] == rune_card["from"] + 1
			and knight.get_upgrade_level(rune_card["skill"]) > 0, "в предложении карта руны во взятый навык: %s" % rune_card.get("id", "—"))
	var panel := _world.get_node("LevelUpPanel")
	await _frames(1)
	_check(panel.visible and panel.get_node("%Cards").get_child_count() == 3, "панель левел-апа показала карты вместе с картой руны")
	_check(not _world.upgrades.apply_choice(1, UpgradePool.rune_card_id(&"rune_avatar", &"no_such_skill")),
			"карта руны не из предложения отклонена (ФТ-16)")
	if not rune_card.is_empty():
		var skill_id: StringName = rune_card["skill"]
		var before: int = knight.runes.get(skill_id, []).size()
		_check(_world.upgrades.apply_choice(1, rune_card["id"]) and rune_card["rune"] in knight.runes.get(skill_id, [])
				and knight.runes[skill_id].size() == before + 1, "выбор карты руны: хост вставил руну в навык")

	var to_banish: StringName = (await _offer_with_rune(knight)).get("id", &"")
	_check(to_banish != &"", "в следующих предложениях снова карта руны")
	if to_banish != &"":
		var rune_id := UpgradePool.parse_rune_card(to_banish)[0]
		_check(_world.upgrades.apply_banish(1, to_banish) and UpgradePool.banish_key(to_banish) in knight.banished,
				"карта руны изгнана — запомнена руна целиком")
		var back := _world.upgrades.current_offer(1).any(func(id: StringName) -> bool:
			return UpgradePool.is_rune_card(id) and UpgradePool.parse_rune_card(id)[0] == rune_id)
		_check(not back and _world.upgrades.current_offer(1).size() == 3, "изгнанная руна не вернулась, карт по-прежнему 3")
	knight.banishes_left = rules.banishes
	knight.banished.clear()
	_drain_offers()
	_auto_pick = true

	# Эволюция забирает руны; руна с тегом и навыки одной стихии дают резонанс в характеристиках.
	var hunter := _world.spawn_player(5, DataRegistry.hero(&"witch_hunter"))
	hunter.invulnerable = true
	hunter.alive = false
	await _frames(1)
	var bolts: SkillData = DataRegistry.upgrade(&"silver_bolts")
	while hunter.get_upgrade_level(&"silver_bolts") < 2 * DataRegistry.UPGRADE_RULES.evolution_step:
		hunter.apply_upgrade(bolts)
	_check(hunter.add_rune(&"silver_bolts", &"rune_split") and hunter.add_rune(&"silver_bolts", &"rune_fire")
			and not hunter.add_rune(&"silver_bolts", &"rune_fire"), "руны вставлены, повтор отклонён")
	hunter.apply_upgrade(bolts.evolution)
	var carried: Array = hunter.runes.get(bolts.evolution.id, [])
	_check(carried.size() == 2 and carried[0] == &"rune_split" and carried[1] == &"rune_fire" and not hunter.runes.has(&"silver_bolts"),
			"эволюция «%s» забрала руны навыка %s" % [bolts.evolution.id, carried])
	hunter.apply_upgrade(DataRegistry.upgrade(&"fire_beam"))
	hunter.apply_upgrade(DataRegistry.upgrade(&"fireball"))
	var fire := DataRegistry.synergy_for_tag(&"fire")
	var expected: float = fire.stats_for(fire.tier_for(3)).get(&"might:fire", 0.0)
	_check(expected > 0.0 and is_equal_approx(hunter.stat(&"might:fire"), expected)
			and hunter.stat_for(Player.STAT_MIGHT, DataRegistry.tag_mask([&"fire"])) >= expected,
			"резонанс «Огонь» (болты с Руной огня, луч, шар): +%d%% урона огнём" % roundi(expected * 100.0))
	hunter.queue_free()
	await _frames(2)


## Шаг 5: враг без физического тела скользит вдоль стен по сетке клеток (и может отойти от стены, которую
## задевает); поле потока ведёт в обход; кристаллов на земле не больше предела, опыт не теряется;
## снарядов героев не больше предела.
func _check_performance_limits(knight: Player) -> void:
	var director := _world.director
	var probe := _world.spawn_enemy({"id": &"skeleton", "pos": knight.global_position + Vector2(0, 600)})
	_check(not probe.is_class("CollisionObject2D") and probe.get_children().all(func(n: Node) -> bool: return not (n is CollisionShape2D)),
			"у врага нет физического тела — стены по сетке клеток")
	probe.queue_free()

	# Клетка пола со стеной справа: шаги вправо упираются в стену, назад — свободно.
	var level := GameState.current_level
	var tile := float(Palette.tile_size())
	var cell := Vector2i(-1, -1)
	for y in level.size:
		for x in level.size - 1:
			if cell.x < 0 and Palette.is_passable(level.get_tile(Vector2i(x, y))) \
					and not Palette.is_passable(level.get_tile(Vector2i(x + 1, y))):
				cell = Vector2i(x, y)
	_check(cell.x >= 0, "на карте есть пол у стены")
	if cell.x >= 0:
		var radius := 8.0
		var edge := (cell.x + 1) * tile
		var pos := (Vector2(cell) + Vector2(0.5, 0.5)) * tile
		var hit_wall := false
		for i in 30:
			pos = director.slide(pos, Vector2(8.0, 0.0), radius)
			hit_wall = hit_wall or director.blocked_last
		_check(hit_wall and pos.x <= edge - radius and pos.x > edge - radius - 1.0,
				"враг упирается в стену вплотную (x %.2f, край %.0f)" % [pos.x, edge - radius])
		var stuck := Vector2(edge - radius + 3.0, (cell.y + 0.5) * tile)  # уже задевает стену на 3 px
		var away := director.slide(stuck, Vector2(-5.0, 0.0), radius)
		_check(away.x < stuck.x and not director.blocked_last, "враг, задевший стену, может от неё отойти")
		var along := director.slide(Vector2(edge - radius - 0.5, (cell.y + 0.5) * tile), Vector2(4.0, 3.0), radius)
		_check(is_equal_approx(along.y, (cell.y + 0.5) * tile + 3.0), "у стены враг скользит вдоль неё")

	# Предел кристаллов: сверх него опыт добавляется к старым кристаллам, сумма опыта сохраняется.
	var cap := DataRegistry.BALANCE.max_xp_gems
	var far := knight.global_position + Vector2(0, -2000)
	var sum_xp := func() -> int:
		var total := 0
		for node in _world.pickups.get_children():
			if node is Pickup and node.kind == Pickup.Kind.XP:
				total += node.value
		return total
	var xp_before: int = sum_xp.call()
	for i in cap + 60:
		_world.upgrades.drop_xp(far + Vector2(i % 20, floori(i / 20.0)) * 4.0, 1)
	_check(_world.upgrades.gem_count() <= cap and sum_xp.call() - xp_before == cap + 60,
			"кристаллов на земле %d (предел %d), опыт не потерян" % [_world.upgrades.gem_count(), cap])
	var removed: Array[Pickup] = []
	for node in _world.pickups.get_children():
		if node is Pickup and node.kind == Pickup.Kind.XP:
			removed.append(node)
			node.queue_free()
	await _frames(2)
	# Бой рядом идёт: враг, убитый за эти 2 кадра, роняет новый кристалл — проверяются именно убранные.
	_check(not removed.is_empty() and _world.upgrades._gems.all(func(gem: Pickup) -> bool: return not removed.has(gem)),
			"подобранные и убранные кристаллы уходят из счёта")

	# Предел снарядов: контейнер полон — выстрел навыка не создаётся.
	var fillers: Array[Node2D] = []
	while not _world.projectiles_full():
		fillers.append(_world.spawn_projectile({"type": &"pulse", "pos": far, "radius": 4.0}))
	var runtime := SkillRuntime.new(DataRegistry.upgrade(&"bone_arrow"), 1)
	runtime.player = knight
	runtime.world = _world
	runtime.refresh()
	_check(runtime.shoot({"type": &"arrow", "pos": knight.global_position, "dir": Vector2.RIGHT}) == null,
			"предел снарядов (%d): новый выстрел героя не создаётся" % DataRegistry.BALANCE.max_hero_projectiles)
	for node in fillers:
		if is_instance_valid(node):
			node.queue_free()
	await _frames(2)


## Статистика забега (как в Megabonk): урон по навыку-источнику (удар, статус), без урона «сверх смерти»,
## убийства, полученный урон, сводка героя и её таблица на экране конца забега.
func _check_run_stats(knight: Player, party: Array[Player]) -> void:
	var stats := _world.run_stats
	var rec := stats.record(knight.peer_id())
	var far := knight.global_position + Vector2(0, 1500)
	var dummy := _world.spawn_enemy({"id": &"skeleton", "pos": far, "hp_mult": 1000.0})
	await _frames(1)
	var damage_of := func(source: StringName) -> float: return float(rec.damage.get(source, 0.0))
	var runtime: SkillRuntime = knight.skills()[0]  # навык, который у Рыцаря есть сейчас
	var held := runtime.data.id
	var held_before: float = damage_of.call(held)
	var health_before := dummy.health
	runtime.hit(dummy)
	_check(is_equal_approx(damage_of.call(held) - held_before, health_before - dummy.health),
			"урон удара навыка засчитан навыку %s (%.1f)" % [held, health_before - dummy.health])
	var burn_before: float = damage_of.call(&"fire_nova")
	_world.statuses.apply(dummy, &"burn", 50.0, knight.peer_id(), 1, 1.0, 0.0, &"fire_nova")
	await _seconds(1.2)
	_check(damage_of.call(&"fire_nova") > burn_before, "урон горения засчитан навыку, который поджёг")
	var kills_before := int(rec.kills.get(held, 0))
	held_before = damage_of.call(held)
	var left := dummy.health
	dummy.take_damage(1.0e9, knight.peer_id(), false, held)
	_check(is_equal_approx(damage_of.call(held) - held_before, left) and int(rec.kills.get(held, 0)) == kills_before + 1,
			"добивание: засчитано только оставшееся здоровье и одно убийство")
	knight.invulnerable = false
	var taken_before := rec.taken
	var hp := knight.health
	knight.take_damage(12.0)
	_check(is_equal_approx(rec.taken - taken_before, hp - knight.health), "полученный урон — потерянное здоровье")
	# Урон по герою растёт с его уровнем; урон среды (доля здоровья) — нет.
	var taken_rules := DataRegistry.BALANCE
	_check(is_equal_approx(taken_rules.damage_taken_mult(1), 1.0) and taken_rules.damage_taken_mult(21) > 1.35,
			"урон по герою растёт с уровнем: на 21-м ×%.2f" % taken_rules.damage_taken_mult(21))
	var level_was := knight.level
	var blow := 10.0 + knight.stat(Player.STAT_ARMOR)
	var hit := func(by_level: bool, amount: float) -> float:  # уклонение может сбросить удар — до первого попадания
		for attempt in 20:
			knight.heal(knight.max_health)
			knight.ward_ready = false
			var before := knight.health
			knight.take_damage(amount, null, by_level)
			if knight.health < before:
				return before - knight.health
		return 0.0
	knight.level = 21
	var flat: float = hit.call(false, blow)
	var scaled: float = hit.call(true, blow)
	# Удар больше любого здоровья снимает не больше max_hit_share — враги и боссы не убивают с 1–3 ударов.
	var capped_hit: float = hit.call(true, 1.0e6)
	knight.level = level_was
	knight.heal(knight.max_health)
	_check(flat > 0.0 and scaled > flat * 1.1,
			"герой 21-го уровня теряет больше здоровья от того же удара: %.1f против %.1f (урон среды не растёт)" % [scaled, flat])
	_check(capped_hit > 0.0 and capped_hit <= knight.max_health * taken_rules.max_hit_share + 0.01,
			"огромный удар снимает не больше %d %% здоровья: %.1f из %.1f"
			% [roundi(taken_rules.max_hit_share * 100.0), capped_hit, knight.max_health])
	knight.invulnerable = true
	knight.heal(knight.max_health)

	stats.publish_all()
	var summary := knight.run_stats
	var rows: Array = summary.get("skills", [])
	var held_row: Array = []
	for row: Array in rows:
		if row[0] == String(held):
			held_row = row
	_check(float(summary.get("time", 0.0)) > 0.0 and int(summary.get("xp", 0)) > 0, "сводка: время забега и опыт")
	_check(not held_row.is_empty() and held_row[4] == knight.get_upgrade_level(held) and held_row[3] > 0.0,
			"сводка: у навыка уровень и время у героя %s" % [held_row])
	_check(rows.size() < 2 or range(rows.size() - 1).all(func(i: int) -> bool: return rows[i][1] >= rows[i + 1][1]),
			"сводка: навыки по убыванию урона")
	_check(RunStatsView.clock(65.0) == "1:05" and RunStatsView.clock(3725.0) == "1:02:05", "время забега: м:сс и ч:мм:сс")
	_check(RunStatsView.short_number(999) == "999" and RunStatsView.short_number(2500000).ends_with(tr("NUM_M")),
			"короткие числа: 999 и миллионы")
	var view := RunStatsView.new()
	add_child(view)
	view.refresh(knight, party)
	_check(view.get_child_count() == 3, "экран статистики: сводка, таблица навыков и отряд")
	view.queue_free()


## Повышает уровень героя, пока в предложении не окажется карта руны (шанс UpgradeRules.rune_card_chance;
## карты хоста — от сида забега, поэтому число попыток одно и то же). Предложения без руны выбираются
## первой картой. Пусто — за 40 повышений карта руны так и не выпала.
func _offer_with_rune(player: Player) -> Dictionary:
	for attempt in 40:
		_offers.clear()
		_world.upgrades.grant_xp(player, Player.xp_to_next(player.level) - player.xp, false)
		await _frames(1)
		for card: Dictionary in (_offers.back()[1] if not _offers.is_empty() else []):
			if card.has("rune"):
				return card
		_world.upgrades.apply_choice(player.peer_id(), _world.upgrades.current_offer(player.peer_id())[0])
	return {}


## CR-17: Магнит душ — весь опыт уровня летит к подобравшему герою, где бы ни лежал.
func _check_soul_magnet(knight: Player) -> void:
	var far: Array[Pickup] = []
	for i in 4:
		far.append(_world.spawn_pickup({
			"kind": Pickup.Kind.XP, "pos": knight.global_position + Vector2(500 + i * 40, 300), "value": 1,
		}))
	await _frames(5)
	# Параметр без типа: в массиве будут и уже удалённые кристаллы.
	var still := func() -> bool: return far.all(func(p: Variant) -> bool: return is_instance_valid(p))
	var gone := func() -> bool: return far.all(func(p: Variant) -> bool: return not is_instance_valid(p))
	_check(still.call(), "далёкий опыт сам к герою не летит")
	_world.spawn_pickup({"kind": Pickup.Kind.MAGNET, "pos": knight.global_position})
	await _wait_until(gone, 4.0)
	_check(gone.call(), "Магнит душ притянул весь опыт уровня")


## Esc во время забега — меню паузы, а не выход в главное меню; Esc сначала закрывает окна поверх мира.
## «Последний вздох» (кооператив): павший герой — призрак; союзник рядом 3 с поднимает его с половиной
## здоровья, отошёл — прогресс тает. HUD: панель союзников.
func _check_last_breath(knight: Player, sorceress: Player) -> void:
	var revived: Array = []
	var on_revived := func(peer_id: int, by_peer_id: int) -> void: revived.append([peer_id, by_peer_id])
	Events.player_revived.connect(on_revived)
	var allies := _world.get_node("HUD").allies as AlliesPanel
	_check(allies.allies().size() == 2, "HUD: в панели союзников двое (свой герой не показан)")
	sorceress.alive = false
	sorceress.health = 0.0
	sorceress.position = knight.position + Vector2(400, 0)  # союзник далеко — никто не поднимает
	await _seconds(1.0)
	_check(not sorceress.alive and sorceress.revive_progress == 0.0, "павшего без союзника рядом не поднимают")
	sorceress.position = knight.position + Vector2(10, 0)
	await _seconds(1.5)
	var progress := sorceress.revive_progress
	_check(not sorceress.alive and progress > 0.3, "союзник рядом — кольцо воскрешения растёт")
	sorceress.position = knight.position + Vector2(400, 0)
	await _seconds(0.5)
	_check(sorceress.revive_progress < progress and sorceress.revive_progress > 0.0, "союзник отошёл — прогресс тает")
	sorceress.position = knight.position + Vector2(10, 0)
	await _wait_until(func() -> bool: return sorceress.alive, 5.0)
	_check(sorceress.alive and is_equal_approx(sorceress.health, sorceress.max_health * LastBreathSystem.REVIVE_HEALTH)
			and sorceress.revive_progress == 0.0, "«Последний вздох»: союзник поднял героя с половиной здоровья")
	_check(revived.size() == 1 and revived[0][0] == 2 and revived[0][1] != 2, "событие воскрешения: кого и кто поднял")
	RunConfig.hardcore = true
	sorceress.alive = false
	await _seconds(4.0)
	_check(not sorceress.alive, "в «Хардкоре» союзник павшего не поднимает")
	RunConfig.hardcore = false
	sorceress.revive()
	sorceress.position = knight.position
	Events.player_revived.disconnect(on_revived)


func _check_pause_menu() -> void:
	var pause := _world.get_node("PauseMenu") as PauseMenu
	_press_key(KEY_ESCAPE)
	_check(pause.visible and get_tree().paused and _world.is_inside_tree(), "Esc — меню паузы, мир стоит, забег не прерван")
	_press_key(KEY_ESCAPE)
	_check(not pause.visible and not get_tree().paused, "второй Esc — игра продолжается")
	_press_key(KEY_I)
	_check(pause.visible and pause.current_tab() == PauseMenu.Tab.HERO and get_tree().paused,
			"I — меню на вкладке «Герой» (экипировка и сумка)")
	_press_key(KEY_ESCAPE)
	_check(not pause.visible and not get_tree().paused, "Esc закрывает меню")
	pause.open(PauseMenu.Tab.SETTINGS)
	_press_key(KEY_I)
	_check(pause.visible and pause.current_tab() == PauseMenu.Tab.HERO, "I на другой вкладке переключает на «Героя»")
	pause.show_tab(PauseMenu.Tab.SKILLS)
	_check(pause.skills.visible and not pause.character.visible, "вкладка «Навыки и умения»")
	pause.close()
	_check(not get_tree().paused, "пауза снята")


## CR-04: таланты хаба действуют в забеге; чужие таланты и ранги выше предела — нет.
func _check_talents_in_run() -> void:
	var hero: HeroData = DataRegistry.hero(&"knight")
	var talents := {&"knight_vigor": 2, &"knight_mastery": 2, &"inheritance": 1, &"necro_lord": 5, &"knight_plate": 99}
	var guest := _world.spawn_player(4, hero, talents)
	_check(is_equal_approx(guest.max_health, hero.max_health + 30.0) and guest.health == guest.max_health,
			"«Закалка» 2 ранга: +30 к здоровью с начала забега")
	_check(guest.get_upgrade_level(hero.starting_weapon) == 3, "«Мастер клинка» 2 ранга: меч сразу 3-го уровня")
	_check(guest.gold == 40, "«Наследство»: золото в начале забега")
	_check(guest.stat(Player.STAT_NECROMANCY) == 0.0, "талант чужого класса не действует")
	_check(guest.stat(Player.STAT_ARMOR) == 5.0, "ранг выше предела ограничен данными (хост, ФТ-16)")
	_world.players.remove_child(guest)
	guest.queue_free()


## Шаг 6: телеграфы (рывок — полоса, направление закреплено; кольцо босса — круг до залпа), аффиксы-поведения
## элит (огненный след, морозная вспышка с холодом, телепорт к герою, призыв) и масштаб под число героев.
func _check_enemy_tells(knight: Player, party: Array[Player]) -> void:
	var tough := 1000.0
	var origin := knight.global_position
	var warns: Array[Projectile] = []
	var ground: Array[Projectile] = []
	var track := func(node: Node) -> void:
		var p := node as Projectile
		if p != null and p.kind == &"warn":
			warns.append(p)
		elif p != null and p.hostile and (p.kind == &"zone" or p.kind == &"blast"):
			ground.append(p)
	_world.projectiles.child_entered_tree.connect(track)
	# Волны стоят, толпа убрана: приёмы проверяемых врагов не упираются в предел живых и не тонут в чужих.
	var waves_were_active := _world.waves.active
	_world.waves.active = false
	for child in _world.enemies.get_children():
		if child is Enemy and not child.ally:
			child.queue_free()
	await _frames(2)

	var rider := _world.spawn_enemy({"id": &"death_rider", "pos": origin + Vector2(-150, 0), "hp_mult": tough})
	await _wait_until(func() -> bool: return not is_instance_valid(rider) or rider._charge_state == Enemy.ChargeState.WINDUP, 6.0)
	var lane: Array = warns.filter(func(w) -> bool: return is_instance_valid(w) and w.line)
	var locked_dir := rider._charge_dir if is_instance_valid(rider) else Vector2.ZERO
	_check(not lane.is_empty() and is_equal_approx((lane[0] as Projectile).max_distance,
			rider.data.charge_speed * rider.data.charge_time), "рывок: полоса на земле длиной в путь рывка")
	knight.global_position = origin + Vector2(0, 70)
	await _frames(6)
	_check(is_instance_valid(rider) and rider._charge_dir == locked_dir, "рывок: во время замаха направление не меняется")
	knight.global_position = origin
	if is_instance_valid(rider):
		rider.queue_free()

	# Шаг 12: приём босса начинается с телеграфа (полоса, круг или растущий взрыв), снаряды — только после замаха.
	warns.clear()
	ground.clear()
	_hostile_shots.clear()
	var biome_music := Sound.music_for(_world)
	var boss := _world.spawn_enemy({"id": &"dread_knight", "pos": origin + Vector2(0, -150), "hp_mult": tough})
	var boss_music: AudioStream = (load("res://data/audio/audio.tres") as AudioConfig).boss_music
	_check(biome_music != null and biome_music != boss_music and Sound.music_for(_world) == boss_music,
			"звук: на уровне — эмбиент биома, при живом боссе — трек босса (шаг 11.13)")
	await _wait_until(func() -> bool: return is_instance_valid(boss) and boss.brain().is_winding_up(), BossBrain.FIRST_DELAY + 1.0)
	await _frames(1)
	var opening := boss.brain().current() if is_instance_valid(boss) else null
	_check(opening != null and (not warns.is_empty() or not ground.is_empty())
			and not _hostile_shots.any(func(s: Array) -> bool: return s[0] == &"shard"),
			"приём босса %s: сначала телеграф, снарядов до удара нет" % (opening.id if opening != null else &"—"))
	if is_instance_valid(boss):
		boss.queue_free()

	ground.clear()
	var fiery := _world.spawn_enemy({"id": &"skeleton", "pos": origin + Vector2(140, 0), "hp_mult": tough, "elite": ["fiery"]})
	# След — каждые trail_step пути; навыки героев могут оглушить или заморозить элиту — ждём до 4 с.
	var has_trail := func() -> bool: return ground.any(func(p) -> bool: return is_instance_valid(p) and p.kind == &"zone")
	await _wait_until(has_trail, 4.0)
	_check(has_trail.call(), "Огненный: оставляет горящий след")
	fiery.queue_free()
	knight.invulnerable = false
	var hp := knight.health
	_world.spawn_projectile({"type": &"zone", "pos": knight.global_position, "radius": 12.0, "duration": 1.2, "tick": 0.5,
			"damage": 3.0, "hostile": true, "color": Color.ORANGE})
	# Если героя только что ударили, неуязвимость после удара откладывает первый тик зоны — ждём до 1 с.
	await _wait_until(func() -> bool: return knight.health < hp, 1.0)
	_check(knight.health < hp, "огненный след жжёт героя")

	ground.clear()
	var frozen := _world.spawn_enemy({"id": &"skeleton", "pos": origin + Vector2(30, 0), "hp_mult": tough, "elite": ["frozen"]})
	var nova: EliteAffixData = DataRegistry.elite_affix(&"frozen")
	await _wait_until(func() -> bool: return ground.any(func(p) -> bool: return is_instance_valid(p) and p.chill),
			nova.nova_interval)
	_check(ground.any(func(p) -> bool: return is_instance_valid(p) and p.chill and p.fuse > 0.0),
			"Ледяной: морозная вспышка с кругом-предупреждением %s" % str(
				[frozen._nova_cooldown, frozen.is_stunned(), frozen.is_feared(), frozen.global_position.distance_to(knight.global_position),
				ground.size()] if is_instance_valid(frozen) else ["убит"]))
	frozen.queue_free()
	var chills := knight.chills
	_world.spawn_projectile({"type": &"blast", "pos": knight.global_position, "radius": 20.0, "fuse": 0.05, "damage": 1.0,
			"hostile": true, "color": nova.color, "chill": true})
	await _frames(8)
	_check(knight.chills == chills + 1 and knight.is_chilled(), "морозная вспышка сковывает героя холодом")
	knight.invulnerable = true

	warns.clear()
	var blink: EliteAffixData = DataRegistry.elite_affix(&"teleporting")
	var jumper := _world.spawn_enemy({"id": &"zombie", "pos": origin + Vector2(-320, 0), "hp_mult": tough, "elite": ["teleporting"]})
	await _wait_until(func() -> bool: return is_instance_valid(jumper) and jumper._teleport_left > 0.0, blink.blink_interval)
	var mark_near := warns.any(func(w) -> bool:
		return is_instance_valid(w) and w.global_position.distance_to(knight.global_position) <= blink.blink_distance + 2.0)
	await _seconds(blink.blink_windup + 0.1)
	_check(mark_near and is_instance_valid(jumper) and jumper.global_position.distance_to(knight.global_position) < 70.0,
			"Телепортирующийся: метка у героя, затем перенос к нему")
	if is_instance_valid(jumper):
		jumper.queue_free()

	warns.clear()
	var summon: EliteAffixData = DataRegistry.elite_affix(&"summoner")
	var caller := _world.spawn_enemy({"id": &"zombie", "pos": origin + Vector2(110, -70), "hp_mult": tough, "elite": ["summoner"]})
	var minions: Array[Enemy] = []
	var count_minions := func(node: Node) -> void:
		var e := node as Enemy
		if e != null and e.data_id == &"zombie" and not e.is_elite() and is_equal_approx(e.health_mult, tough * summon.summon_health):
			minions.append(e)
	_world.enemies.child_entered_tree.connect(count_minions)
	await _wait_until(func() -> bool: return not minions.is_empty(), summon.summon_interval)
	_world.enemies.child_entered_tree.disconnect(count_minions)
	_check(warns.size() >= 1 and minions.size() >= 1, "Призыватель: метки, затем из них встают подручные %s" % str(
			[warns.size(), minions.size(), caller._summoner_cooldown, caller.is_stunned(), caller.is_feared(),
			_world.director.hostile_count(), _world.waves.table.max_alive] if is_instance_valid(caller) else ["убит"]))
	caller.queue_free()
	for m in minions:
		if is_instance_valid(m):
			m.queue_free()
	_world.projectiles.child_entered_tree.disconnect(track)
	_world.waves.active = waves_were_active

	var balance := DataRegistry.BALANCE
	_check(balance.coop_health_mult(1) == 1.0 and is_equal_approx(balance.coop_health_mult(2), 1.2)
			and is_equal_approx(balance.coop_health_mult(3), 1.3) and is_equal_approx(balance.coop_health_mult(4), 1.4),
			"кооператив: здоровье врагов ×1 / ×1,2 / ×1,3 / ×1,4 при 1 / 2 / 3 / 4 героях")
	var skeleton := DataRegistry.enemy(&"skeleton")
	var scaled := _world.waves.spawn_enemy(skeleton, origin + Vector2(0, 120))
	var expected := skeleton.max_health * RunConfig.enemy_health_mult() \
			* balance.enemy_health_mult(GameState.level_index, 0) * balance.coop_health_mult(party.size())
	_check(scaled != null and is_equal_approx(scaled.max_health, expected),
			"кооператив: у %d героев враг волны крепче в %.1f раза" % [party.size(), balance.coop_health_mult(party.size())])
	if scaled != null:
		scaled.queue_free()


## Шаг 8: интерактивные точки из данных — святилище, алтарь проклятий, разрушаемое, лор, пленник, мимик.
## Шаг 12: боссы — больше здоровья, приёмы из данных по фазам, каждый рисунок удара работает.
func _check_boss_attacks(knight: Player) -> void:
	var bosses := DataRegistry.ENEMIES.filter(func(e: EnemyData) -> bool: return e.is_boss)
	for info: EnemyData in bosses:
		var phases := info.phase_thresholds.size() + 1
		var opened := range(phases).all(func(p: int) -> bool:
			return info.attacks.any(func(a: BossAttack) -> bool: return a != null and a.min_phase == p))
		_check(info.attacks.size() >= 5 and phases >= 3 and opened and info.max_health >= 4000.0,
				"босс %s: %d приёмов, %d фазы, в каждой фазе новый приём, здоровье %.0f" % [info.id, info.attacks.size(),
				phases, info.max_health])
		for attack in info.attacks:
			if attack is BossSummon:
				_check(DataRegistry.enemy((attack as BossSummon).enemy_id) != null, "призыв %s: такой враг есть" % attack.id)

	var tough := 1000.0
	var origin := knight.global_position
	var waves_were_active := _world.waves.active
	_world.waves.active = false
	var balance := DataRegistry.BALANCE
	var pit_lord := DataRegistry.enemy(&"pit_lord")
	var grown := _world.waves.spawn_enemy(pit_lord, origin + Vector2(0, -160))
	var expected := pit_lord.max_health * RunConfig.enemy_health_mult() * balance.boss_health_at(GameState.level_index) \
			* balance.coop_health_mult(_world.get_players().size()) * (1.0 + _world.waves.level_curse_health)
	_check(grown != null and is_equal_approx(grown.max_health, expected)
			and balance.boss_health_at(3) > balance.enemy_health_mult(3, 0),
			"здоровье босса растёт с глубиной быстрее волн: на глубине 3 ×%.1f против ×%.1f"
			% [balance.boss_health_at(3), balance.enemy_health_mult(3, 0)])
	# Урон босса ×3 у первого → ×5 к финалу сверх роста врагов; подручные — без надбавки босса.
	var plain := _world.waves.spawn_enemy(DataRegistry.enemy(&"skeleton"), origin + Vector2(60, -160))
	_check(grown != null and plain != null
			and is_equal_approx(grown.damage_mult,
					plain.damage_mult / balance.enemy_damage_scale * balance.boss_damage_at(GameState.level_index))
			and is_equal_approx(balance.boss_damage_at(0), 1.5) and balance.boss_damage_at(3) >= 2.5
			and balance.boss_damage_at(10) == 2.5,
			"урон босса ×%.1f на глубине 0, ×%.2f к финалу (не больше ×2,5)" % [balance.boss_damage_at(0), balance.boss_damage_at(3)])
	_check(plain != null and is_equal_approx(plain.damage_mult, balance.enemy_damage_mult(GameState.level_index, 0)
			* RunConfig.enemy_damage_mult() * (1.0 + _world.waves.level_curse_damage) * 0.6),
			"урон обычных врагов по герою ×%.2f, у боссов — без этой поправки" % balance.enemy_damage_scale)
	if plain != null:
		plain.queue_free()
	# Снаряды врагов: медленнее (0,75 × 0,85) и на 25 % слабее; взрывы на земле — без изменений.
	var shot := _world.spawn_projectile({"type": &"shard", "pos": origin + Vector2(0, 400), "dir": Vector2.RIGHT,
			"speed": 100.0, "range": 10.0, "damage": 10.0, "hostile": true, "color": Color.WHITE})
	_check(shot != null and is_equal_approx(float(shot.get("speed")), 63.75) and is_equal_approx(float(shot.get("damage")), 7.5),
			"снаряд врага: скорость 100 → %s, урон 10 → %s" % [shot.get("speed") if shot != null else "—",
			shot.get("damage") if shot != null else "—"])
	if shot != null:
		shot.queue_free()
	# Дальнобойные в волнах выпадают на 10 % реже.
	var ranged_checked := 0
	var wrong_weights := 0
	for stage_table: BiomeData in DataRegistry.BIOMES:
		for entry: WaveEntry in stage_table.waves.waves:
			for i in entry.enemies.size():
				var ranged := WaveEntry.is_ranged(entry.enemies[i])
				ranged_checked += int(ranged)
				var expected_weight := entry.weights[i] * (balance.ranged_spawn_weight if ranged else 1.0)
				wrong_weights += int(not is_equal_approx(entry.pick_weights()[i], expected_weight))
	_check(ranged_checked > 0 and wrong_weights == 0 and WaveEntry.is_ranged(DataRegistry.enemy(&"skeleton_crossbowman"))
			and not WaveEntry.is_ranged(DataRegistry.enemy(&"zombie")),
			"дальнобойные в волнах ×%.1f (записей с ними: %d)" % [balance.ranged_spawn_weight, ranged_checked])
	if grown != null:
		_check(is_equal_approx(grown.damage_mult / balance.boss_damage_at(GameState.level_index),
				balance.enemy_damage_mult(GameState.level_index, 0) * RunConfig.enemy_damage_mult() * (1.0 + _world.waves.level_curse_damage)),
				"подручные босса бьют как враги волн (урон босса без надбавки)")
		grown.queue_free()
	var lord := _world.spawn_enemy({"id": &"pit_lord", "pos": origin + Vector2(0, -160), "hp_mult": tough})
	lord.set_status_effects(0.0, true, false, 0.0, 0)  # оглушён: свои приёмы не начинает, рисунки ниже — вручную
	await _frames(1)
	_check(is_equal_approx(lord.radius, pit_lord.radius * balance.boss_size_mult) and balance.boss_size_mult > 1.0
			and lord.body.scale.x > EnemyArt.sheet(&"pit_lord").scale,
			"босс крупнее обычного: радиус и облик ×%.2f" % balance.boss_size_mult)
	var base_speed := lord._speed
	lord.take_damage(lord.max_health * 0.3, 0)
	_check(lord.phase == 1 and lord.brain().phase == 1 and lord._speed > base_speed and lord.brain().current() == null,
			"порог здоровья: фаза 2, босс быстрее, приём оборван (замирает)")
	lord.take_damage(lord.max_health * 0.5, 0)
	_check(lord.phase == 3 and lord.body.modulate.r > lord.body.modulate.g, "последняя фаза — облик ярости")
	lord.health = lord.max_health
	_check(lord.phase == 3, "лечение не возвращает прошлую фазу")
	await _frames(1)

	# Каждый рисунок удара — на Владыке Бездны (у него все 9): за несколько секунд что-то появилось в мире.
	var spawned := [0]
	var count_spawn := func(_node: Node) -> void: spawned[0] += 1
	_world.projectiles.child_entered_tree.connect(count_spawn)
	_world.enemies.child_entered_tree.connect(count_spawn)
	var rng := RandomNumberGenerator.new()
	var kinds := {}
	for attack: BossAttack in lord.data.attacks:
		if not is_instance_valid(lord):
			break
		spawned[0] = 0
		var cast := BossCast.new(lord, _world, knight, 3, rng)
		var start := lord.global_position
		attack.telegraph(cast)
		await _seconds(attack.windup)
		attack.strike(cast)
		for i in 360:
			await get_tree().physics_frame
			cast.time += 1.0 / 60.0
			cast.moving = false
			if not attack.tick(cast, 1.0 / 60.0):
				break
		var moved := lord.global_position.distance_to(start) > 20.0
		kinds[attack.get_script().get_global_name()] = spawned[0] > 0 or moved
		lord.global_position = start
	_world.projectiles.child_entered_tree.disconnect(count_spawn)
	_world.enemies.child_entered_tree.disconnect(count_spawn)
	_check(kinds.size() == 9 and kinds.values().all(func(ok: bool) -> bool: return ok),
			"все 9 рисунков ударов босса срабатывают: %s" % [kinds])
	if is_instance_valid(lord):
		lord.queue_free()
	for child in _world.enemies.get_children():
		if child is Enemy and not child.ally:
			child.queue_free()
	_world.waves.active = waves_were_active
	await _frames(2)


func _check_interactables(knight: Player) -> void:
	var placements_ok := DataRegistry.INTERACTABLES.all(func(p: InteractableData) -> bool:
		return p.placement in InteractableData.PLACEMENTS)
	_check(DataRegistry.INTERACTABLES.size() >= 11 and DataRegistry.LORE.size() == 10 and placements_ok,
			"точки карты и записи лора — в данных")
	_check(_world.props.get_children().any(func(n: Node) -> bool: return n is Interactable),
			"точки встали на уровне по меткам модели")
	var waves_were_active := _world.waves.active
	_world.waves.active = false
	var origin := knight.global_position
	var next := [950]
	var point := func(type: StringName, at: Vector2, lore: StringName = &"") -> Node2D:
		next[0] += 1
		return _world.spawn_prop({"kind": &"interactable", "type": type, "pos": at, "id": next[0], "lore": lore})

	var shrine: Interactable = point.call(&"shrine_fury", origin + Vector2(20, 0))
	_check(shrine.activate(knight) and shrine.used and knight.buffs.has(&"shrine_fury"), "святилище: бафф получен, святилище погасло")

	var altar: Interactable = point.call(&"curse_altar", origin + Vector2(-20, 0))
	var plain := _world.waves.spawn_enemy(DataRegistry.enemy(&"skeleton"), origin + Vector2(0, 200))
	_check(altar.activate(knight) and is_equal_approx(_world.waves.reward_mult(), 1.5), "алтарь проклятий: награда уровня +50 %")
	var cursed := _world.waves.spawn_enemy(DataRegistry.enemy(&"skeleton"), origin + Vector2(0, 210))
	_check(is_equal_approx(cursed.max_health, plain.max_health * 1.4), "алтарь проклятий: новые враги на 40 % крепче")
	plain.queue_free()
	cursed.queue_free()
	_world.waves.level_curse_health = 0.0
	_world.waves.level_curse_damage = 0.0
	_world.waves.level_curse_reward = 0.0

	var coins_before := _world.pickups.get_children().filter(func(n: Node) -> bool: return n is Pickup and n.kind == Pickup.Kind.GOLD).size()
	var barrel: Interactable = point.call(&"barrel", origin + Vector2(0, 60))
	var gold_was := knight.gold
	knight.teleport(barrel.global_position)
	await _frames(6)
	var coins_after := _world.pickups.get_children().filter(func(n: Node) -> bool: return n is Pickup and n.kind == Pickup.Kind.GOLD).size()
	# монеты сразу летят к герою, что стоит рядом: считается и золото на земле, и подобранное
	_check(barrel.used and (coins_after > coins_before or knight.gold > gold_was),
			"бочка разбилась от касания и рассыпала золото %s" % str([barrel.used, coins_before, coins_after, gold_was, knight.gold]))
	knight.teleport(origin)

	# Пасхалка: Золотое ведро опрокидывается от касания — гора золота, опыт, зелье и легендарный предмет.
	_dropped_rarities.clear()
	var bucket: Interactable = point.call(&"golden_bucket", origin + Vector2(60, 60))
	var bucket_gold := knight.gold
	knight.teleport(bucket.global_position)
	await _frames(6)
	_check(bucket.used and bucket.art_id() == &"debris_gold" and _dropped_rarities.has(ItemRoller.Rarity.LEGENDARY)
			and DataRegistry.interactable(&"golden_bucket").gold.x >= 300,
			"Золотое ведро опрокинуто: золото, опыт, зелье и легендарный предмет (было золота %d)" % bucket_gold)
	knight.teleport(origin)

	var lore_point: Interactable = point.call(&"lore_site", origin + Vector2(30, 30), &"lost_seeker")
	var chronicle: ChronicleRecorder = _world.get_node("Systems/Chronicle")
	var panel := LorePanel.open(_world, DataRegistry.lore(&"lost_seeker"), lore_point)
	Events.lore_read.emit(&"lost_seeker")
	_check(panel.visible and panel._title.text != "" and &"lost_seeker" in chronicle.summary().lore,
			"лор: текст открыт, запись ушла в «Летопись»")
	panel.hide()

	var prisoner: Interactable = point.call(&"prisoner", origin + Vector2(-60, -40))
	var items_before := _items_on_ground()
	_check(prisoner.activate(knight) and prisoner.stage == Interactable.Stage.GUARDED
			and prisoner.guards_left() == prisoner.data.guard_count, "пленник: по E нападает стража")
	for guard in prisoner._guards:
		if is_instance_valid(guard):
			guard.take_damage(1.0e9, 1)
	await _frames(4)
	_check(prisoner.stage == Interactable.Stage.DONE and prisoner.used and _items_on_ground() > items_before
			and chronicle.summary().rescued >= 1, "пленник: стража перебита — свободен, награда на земле")

	var chest: Chest = _world.spawn_prop({"kind": &"chest", "pos": origin + Vector2(70, -30), "id": 990})
	chest.mimic = true
	var gold_before := knight.gold
	var mimics: Array[Enemy] = []
	var catch_mimic := func(node: Node) -> void:
		if node is Enemy and (node as Enemy).data_id == &"mimic":
			mimics.append(node)
	_world.enemies.child_entered_tree.connect(catch_mimic)
	var items_mimic := _items_on_ground()  # герои рядом могут убить мимика сразу — добыча считается от активации
	_check(chest.activate(knight) and chest.used and knight.gold == gold_before, "мимик: золото не списано, сундук ожил")
	_world.enemies.child_entered_tree.disconnect(catch_mimic)
	for m in mimics:
		if is_instance_valid(m) and not m.dead:
			m.take_damage(1.0e9, 1)
	await _frames(2)
	_check(mimics.size() == 1 and _items_on_ground() >= items_mimic + 2, "мимик повержен — вдвое больше добычи %s" % str(
			[mimics.size(), items_mimic, _items_on_ground()]))
	_world.waves.active = waves_were_active


func _items_on_ground() -> int:
	return _world.pickups.get_children().filter(func(n: Node) -> bool: return n is Pickup and n.kind == Pickup.Kind.ITEM).size()


## Особые враги: веер выстрелов, навесной огонь, рывок, самоподрыв, лечение, телепорт, деление.
func _check_special_enemies(knight: Player) -> void:
	var tough := 1000.0  # враги переживают оружие героя, пока проверяется их поведение
	var origin := knight.global_position
	_hostile_shots.clear()
	var crossbow := _world.spawn_enemy({"id": &"skeleton_crossbowman", "pos": origin + Vector2(150, 0), "hp_mult": tough})
	var shards := func() -> int: return _hostile_shots.filter(func(s: Array) -> bool: return s[0] == &"shard").size()
	await _wait_until(func() -> bool: return shards.call() >= 3, 5.0)  # первый залп — через shot_interval
	_check(shards.call() >= 3, "скелет-арбалетчик стреляет веером из 3 болтов")
	crossbow.queue_free()

	_hostile_shots.clear()
	var pyro := _world.spawn_enemy({"id": &"pyromancer", "pos": origin + Vector2(0, 180), "hp_mult": tough})
	var lobs := func() -> Array:
		return _hostile_shots.filter(func(s: Array) -> bool:
			return s[0] == &"blast" and (s[1] as Vector2).distance_to(knight.global_position) < 24.0)
	await _wait_until(func() -> bool: return not lobs.call().is_empty(), 6.0)  # первый выстрел — через shot_interval
	var lobbed: Array = lobs.call()
	_check(not lobbed.is_empty(), "пиромант бьёт навесом: взрыв появляется под героем %s" % str([
			_hostile_shots.size(), get_tree().paused, _world._pause_reasons.keys(),
			pyro.global_position.distance_to(knight.global_position) if is_instance_valid(pyro) else -1.0,
			_hostile_shots.map(func(s: Array) -> String: return "%s@%.0f" % [s[0], (s[1] as Vector2).distance_to(knight.global_position)])]))
	pyro.queue_free()

	var rider := _world.spawn_enemy({"id": &"death_rider", "pos": origin + Vector2(-160, 0), "hp_mult": tough})
	var rider_speed := rider.data.speed
	var top_speed := 0.0
	var stunned_frames := 0
	var nearest := INF
	# Оглушение от навыков героев сбивает замах и откладывает рывок на charge_interval (4 с): ждём до 12 с.
	for i in 720:
		await get_tree().physics_frame
		if not is_instance_valid(rider) or top_speed > rider_speed * 3.0:
			break  # герои могли убить всадника — важно, был ли рывок до этого
		top_speed = maxf(top_speed, rider.velocity.length())
		stunned_frames += int(rider.is_stunned())
		var near_player := _world.director.nearest_player(rider.global_position)
		if near_player != null:
			nearest = minf(nearest, rider.global_position.distance_to(near_player.global_position))
	_check(top_speed > rider_speed * 3.0, "мёртвый всадник делает рывок (скорость %.0f, оглушён кадров %d, ближе всего %.0f, жив %s)"
			% [top_speed, stunned_frames, nearest, is_instance_valid(rider)])
	if is_instance_valid(rider):
		rider.queue_free()

	_hostile_shots.clear()
	var corpse := _world.spawn_enemy({"id": &"bloated_corpse", "pos": origin + Vector2(14, 0), "hp_mult": tough})
	await _seconds(1.0)
	_check(not is_instance_valid(corpse) and _hostile_shots.any(func(s: Array) -> bool: return s[0] == &"blast"),
			"раздутый труп взрывается вплотную к герою")

	var priest := _world.spawn_enemy({"id": &"dark_priest", "pos": origin + Vector2(0, -220), "hp_mult": tough})
	var patient := _world.spawn_enemy({"id": &"zombie", "pos": origin + Vector2(20, -220), "hp_mult": tough})
	await _frames(2)
	patient.health = patient.max_health * 0.3
	var hurt := patient.health
	await _seconds(priest.data.heal_interval + 0.3)
	_check(patient.health > hurt, "тёмный жрец лечит раненых врагов")
	priest.queue_free()
	patient.queue_free()

	var mage := _world.spawn_enemy({"id": &"phantom_mage", "pos": origin + Vector2(330, 0), "hp_mult": tough})
	var jumped := false
	var last := mage.global_position
	for i in 420:
		await get_tree().physics_frame
		if not is_instance_valid(mage):
			break
		jumped = jumped or mage.global_position.distance_to(last) > 60.0
		last = mage.global_position
	_check(jumped, "призрачный маг телепортируется ближе к герою")
	if is_instance_valid(mage):
		mage.queue_free()

	var before := _count_enemies(&"rot_droplet")
	var spawned := [0]
	var count_drops := func(node: Node) -> void:
		if node is Enemy and (node as Enemy).data_id == &"rot_droplet":
			spawned[0] += 1
	_world.enemies.child_entered_tree.connect(count_drops)
	var blob := _world.spawn_enemy({"id": &"rot_blob", "pos": origin + Vector2(0, 90)})
	blob.take_damage(1.0e9, 1)
	await _frames(2)
	_world.enemies.child_entered_tree.disconnect(count_drops)
	# Считаются появившиеся капли: слабую каплю навыки героя рядом могут убить за эти 2 кадра.
	_check(spawned[0] == 3, "гнилостная масса делится на 3 капли (появилось %d, живы %d)" % [
		spawned[0], _count_enemies(&"rot_droplet") - before])


## CR-15: новые пассивки — Сокрушение, Губитель великанов, Казнь, Второе дыхание, Оберег, Ярость, Проклятие.
func _check_new_passives(knight: Player) -> void:
	# Карты, взятые раньше автоматически, тоже дают эти характеристики — ожидания считаются от итога.
	var crit_before := knight.crit_mult()
	knight.add_bonus(&"test_passives", {Player.STAT_CRIT_DAMAGE: 0.5, Player.STAT_GIANT_SLAYER: 0.5, Player.STAT_EXECUTE: 0.2})
	_check(is_equal_approx(knight.crit_mult() - crit_before, 0.5) and knight.crit_mult() >= 2.5,
			"Сокрушение: +0.5 к множителю удачного удара (×%.2f)" % knight.crit_mult())
	var far := knight.global_position + Vector2(0, -900)
	var elite := _world.spawn_enemy({"id": &"skeleton", "pos": far, "hp_mult": 1000.0, "elite": ["fast"]})
	var common := _world.spawn_enemy({"id": &"skeleton", "pos": far + Vector2(40, 0), "hp_mult": 1000.0})
	await _frames(1)
	var elite_before := elite.health
	var common_before := common.health
	elite.take_damage(100.0, 1)
	common.take_damage(100.0, 1)
	var slayer := knight.stat(Player.STAT_GIANT_SLAYER)
	_check(slayer >= 0.5 and is_equal_approx(elite_before - elite.health, 100.0 * (1.0 + slayer))
			and is_equal_approx(common_before - common.health, 100.0),
			"Губитель великанов: по элите +%d %% урона, по обычному врагу — без прибавки" % roundi(slayer * 100.0))
	common.health = common.max_health * 0.25
	common.take_damage(common.max_health * 0.1, 1)
	_check(common.dead, "Казнь: враг ниже 20 % здоровья погибает сразу")
	elite.queue_free()

	knight.add_bonus(&"test_passives", {Player.STAT_REVIVAL: 1.0, Player.STAT_DODGE: -10.0})
	knight.invulnerable = false
	knight.ward_ready = false
	var revivals_before := knight.revivals_left()  # карта «Второе дыхание» могла выпасть раньше — зарядов больше одного
	knight.health = 1.0  # один удар снимает не больше max_hit_share — смертелен он только для раненого
	knight.take_damage(1.0e9)
	_check(knight.alive and is_equal_approx(knight.health, knight.max_health * DataRegistry.BALANCE.revival_health)
			and knight.revivals_left() == revivals_before - 1,
			"Второе дыхание: смертельный удар — и герой встаёт с половиной здоровья (зарядов %d → %d)"
			% [revivals_before, knight.revivals_left()])
	knight.add_bonus(&"test_passives", {Player.STAT_WARD: 0.5, Player.STAT_DODGE: -10.0})
	knight._ward_timer = 0.0  # карта Оберега могла выпасть раньше — таймер её заряда уже шёл
	await _frames(3)
	knight.ward_ready = true  # за эти кадры заряд мог снять удар врага рядом — герой не неуязвим
	var health := knight.health
	knight.take_damage(30.0)
	_check(health == knight.health and not knight.ward_ready, "Оберег поглотил удар целиком")
	var ward := knight.capped(Player.STAT_WARD)  # + карты «Оберега» из левел-апов; предел — StatDef
	_check(ward >= 0.5 and is_equal_approx(knight.ward_interval(), DataRegistry.BALANCE.ward_interval * (1.0 - ward)),
			"Оберег заряжается быстрее: −%d %% к времени заряда" % roundi(ward * 100.0))
	knight.invulnerable = true

	knight.add_bonus(&"test_passives", {Player.STAT_BERSERK: 0.5})
	knight.health = knight.max_health
	var calm := knight.damage_mult()
	knight.health = knight.max_health * 0.4
	_check(is_equal_approx(knight.damage_mult() - calm, 0.5), "Ярость: +50 % урона при здоровье ниже половины")
	knight.health = knight.max_health
	knight.add_bonus(&"test_passives", {})

	var xp_before := knight.stat(Player.STAT_XP_GAIN)
	knight.apply_upgrade(DataRegistry.upgrade(&"curse"))
	_check(knight.stat(Player.STAT_CURSE) > 0.0 and knight.stat(Player.STAT_XP_GAIN) > xp_before,
			"Проклятие: больше врагов, но и больше опыта")
	_check(_world.waves._curse() >= knight.stat(Player.STAT_CURSE), "волны знают Проклятие отряда")


## Шаг 2: статусы на враге — урон со временем, стаки, контроль, реакции; теги, сопротивления, порча,
## прибавка «по тегу»; флаги статусов в снимке врага для клиентов.
func _check_statuses(knight: Player) -> void:
	var statuses := _world.statuses
	var far := knight.global_position + Vector2(0, -900)
	var dummy := _world.spawn_enemy({"id": &"zombie", "pos": far, "hp_mult": 1000.0})
	var neighbour := _world.spawn_enemy({"id": &"zombie", "pos": far + Vector2(20, 0), "hp_mult": 1000.0})
	await _frames(2)  # сетка врагов перестраивается в кадре физики

	var burn := DataRegistry.status(&"burn")
	for i in burn.max_stacks + 2:
		statuses.apply(dummy, &"burn", 100.0, 1)
	_check(statuses.stacks_of(dummy, &"burn") == burn.max_stacks, "горение: стаков не больше %d" % burn.max_stacks)
	var before := dummy.health
	await _seconds(1.05)
	var burned := before - dummy.health
	var expected := 100.0 * burn.dot_share * burn.max_stacks
	_check(burned > expected * 0.45 and burned < expected * 1.55, "горение жжёт: %.0f урона за секунду (ждали ~%.0f)" % [burned, expected])
	_check(dummy.status_flags & (1 << burn.visual_bit) != 0 and dummy.body.modulate == burn.color,
			"горящий враг окрашен оттенком горения")
	await _seconds(burn.duration)
	_check(statuses.stacks_of(dummy, &"burn") == 0 and dummy.status_flags == 0 and dummy.body.modulate == Color.WHITE,
			"горение истекло — оттенок снят")

	statuses.apply(dummy, &"stun")
	var pos := dummy.global_position
	await _seconds(0.3)
	_check(dummy.is_stunned() and dummy.global_position.distance_to(pos) < 0.5, "оглушённый враг стоит на месте")
	await _seconds(DataRegistry.status(&"stun").duration)
	_check(not dummy.is_stunned(), "оглушение прошло")

	var reactions := statuses.reactions_total
	for i in 5:
		statuses.apply(dummy, &"chill", 10.0, 1)
	_check(dummy.is_stunned() and statuses.stacks_of(dummy, &"freeze") == 1 and statuses.stacks_of(dummy, &"chill") == 0
			and statuses.reactions_total == reactions + 1, "пятый стак холода — заморозка (реакция)")
	statuses.remove(dummy, &"freeze")
	_check(not dummy.is_stunned(), "снятая заморозка отпускает врага")

	neighbour.global_position = dummy.global_position + Vector2(16, 0)  # пока шли проверки, оба брели к герою
	await _frames(2)
	statuses.apply(dummy, &"oil")
	var neighbour_before := neighbour.health
	statuses.apply(dummy, &"burn", 50.0, 1)
	_check(statuses.stacks_of(dummy, &"oil") == 0 and neighbour.health < neighbour_before,
			"горение по маслу — взрыв, задевает соседа (%.0f урона)" % (neighbour_before - neighbour.health))
	statuses.remove(dummy, &"burn")

	var hp := neighbour.health
	neighbour.take_hit(HitInfo.make(100.0, 1))
	var plain := hp - neighbour.health
	for i in 5:
		statuses.apply(neighbour, &"hex")
	hp = neighbour.health
	neighbour.take_hit(HitInfo.make(100.0, 1))
	_check(is_equal_approx(hp - neighbour.health, plain * 1.3), "порча 5 стаков: +30 %% урона (%.0f → %.0f)" % [plain, hp - neighbour.health])
	statuses.remove(neighbour, &"hex")

	var zombie := DataRegistry.enemy(&"zombie")
	var saved := zombie.resistances
	zombie.resistances = {&"fire": 0.5}
	hp = neighbour.health
	neighbour.take_hit(HitInfo.make(100.0, 1, DataRegistry.tag_mask([&"fire", &"projectile"])))
	var fire := hp - neighbour.health
	hp = neighbour.health
	neighbour.take_hit(HitInfo.make(100.0, 1, DataRegistry.tag_mask([&"cold"])))
	_check(is_equal_approx(fire, plain * 0.5) and is_equal_approx(hp - neighbour.health, plain),
			"сопротивление огню 50 %%: огонь %.0f, холод %.0f" % [fire, hp - neighbour.health])
	zombie.resistances = saved

	var fire_mask := DataRegistry.tag_mask([&"fire"])
	var cold_mask := DataRegistry.tag_mask([&"cold"])
	var fire_before := knight.damage_mult(fire_mask)  # предмет с огненным префиксом (шаг 7) уже мог прибавить
	var cold_before := knight.damage_mult(cold_mask)
	knight.add_bonus(&"test_scoped", {&"might:fire": 0.5})
	_check(is_equal_approx(knight.damage_mult(fire_mask) - fire_before, 0.5) and is_equal_approx(knight.damage_mult(cold_mask), cold_before),
			"Мощь «по тегу»: +50 % только огненным ударам")
	knight.add_bonus(&"test_scoped", {})

	var fireball: SkillData = DataRegistry.upgrade(&"fireball")
	neighbour.take_hit(knight.make_hit(10.0, DataRegistry.tag_mask(fireball.tags), fireball.on_hit))
	_check(statuses.stacks_of(neighbour, &"burn") > 0, "огненный шар поджигает (статус из данных оружия)")

	var snapshot := EnemySnapshot.new()
	snapshot.pack([neighbour])
	var record: Array = snapshot.unpack()[0]
	_check(int(record[3]) & (1 << burn.visual_bit) != 0, "флаги статусов уходят клиентам в снимке врага")
	snapshot.free()

	var boss := _world.spawn_enemy({"id": &"dread_knight", "pos": far + Vector2(-60, 0)})
	await _frames(1)
	_check(not statuses.apply(boss, &"fear") and statuses.apply(boss, &"chill") and boss.is_slowed(),
			"страх на босса не действует, холод — слабее")
	for enemy: Enemy in [dummy, neighbour, boss]:
		if is_instance_valid(enemy):
			enemy.queue_free()
	await _frames(2)


## CR-16: испытания — натиск у Алтаря и стая Проклятого тотема; награда только за успех.
func _check_challenges(knight: Player) -> void:
	_challenges.clear()
	var altar := _world.spawn_prop({"kind": &"trial_altar", "pos": knight.global_position + Vector2(0, 40), "id": 903}) as ChallengeAltar
	knight.teleport(altar.global_position)
	await _frames(2)
	var alive_before := _world.director.hostile_count()
	_check(_world.apply_interact(1, 903) and altar.active and _world.waves.surge_left > 0.0, "E у алтаря — испытание началось")
	_check(not _world.apply_interact(1, 903), "начатое испытание второй раз не начать")
	await _seconds(2.0)
	_check(_world.director.hostile_count() > alive_before, "натиск: врагов становится больше")
	_dropped_rarities.clear()
	altar.time_left = 0.05
	await _wait_until(func() -> bool: return not altar.active, 2.0)  # левел-ап может на миг поставить мир на паузу
	_check(_challenges.size() == 1 and _challenges[0] == [ChallengeAltar.TRIAL, true] and _world.waves.surge_left == 0.0,
			"продержались — испытание пройдено, натиск закончился %s" % [_challenges])
	_check(_dropped_rarities.any(func(r: int) -> bool: return r >= ItemRoller.Rarity.RARE), "награда за испытание — редкий предмет")

	var totem := _world.spawn_prop({"kind": &"cursed_totem", "pos": knight.global_position + Vector2(0, 60), "id": 904}) as ChallengeAltar
	knight.teleport(totem.global_position)
	await _frames(2)
	_check(_world.apply_interact(1, 904) and totem._pack.size() == ChallengeAltar.TOTEM_PACK, "тотем призвал стаю чемпионов")
	_check(totem._pack.all(func(e: Enemy) -> bool: return e.elite_affixes.size() == ChallengeAltar.TOTEM_AFFIXES),
			"у каждого чемпиона стаи по 2 аффикса")
	for enemy in totem._pack:
		enemy.take_damage(1.0e9, 1)
	await _wait_until(func() -> bool: return not totem.active, 2.0)
	_check(_challenges.size() == 2 and _challenges[1] == [ChallengeAltar.CURSED, true], "стая перебита — испытание пройдено")

	# «Награды нет» — только от испытания: враги волн на время проверки убраны (с элиты тоже падают предметы).
	_world.waves.active = false
	for child in _world.enemies.get_children():
		if child is Enemy and not child.ally:
			child.queue_free()
	var cursed := _world.spawn_prop({"kind": &"cursed_totem", "pos": knight.global_position + Vector2(0, -60), "id": 905}) as ChallengeAltar
	knight.teleport(cursed.global_position)
	await _frames(2)
	_world.apply_interact(1, 905)
	for enemy in cursed._pack:
		enemy.max_health = 1.0e12
		enemy.health = 1.0e12
	_dropped_rarities.clear()
	cursed.time_left = 0.05
	await _wait_until(func() -> bool: return not cursed.active, 2.0)
	_check(_challenges.size() == 3 and _challenges[2] == [ChallengeAltar.CURSED, false]
			and not _dropped_rarities.any(func(r: int) -> bool: return r >= ItemRoller.Rarity.RARE),
			"не успели за время — испытание провалено, награды нет %s" % [_challenges])
	_world.waves.active = true
	for enemy in cursed._pack:
		if is_instance_valid(enemy):
			enemy.queue_free()


## Инвентарь показывает все характеристики героя.
func _check_character_sheet(knight: Player) -> void:
	var rows := StatSheet.rows(knight, _world.economy.chest_price(knight))
	var translated := rows.all(func(row: Array) -> bool: return TranslationServer.translate(row[0]) != row[0])
	_check(rows.size() >= 28 and translated, "лист героя: %d характеристик, все с подписью" % rows.size())
	_check(rows.all(func(row: Array) -> bool: return row.size() == 4), "у каждой строки листа есть основа")
	var menu := _world.get_node("PauseMenu") as PauseMenu
	_press_key(KEY_I)
	var sheet := menu.character.sheet
	_check(menu.visible and sheet.get_child_count() >= rows.size() * 3, "на вкладке «Герой» виден лист: подпись, основа, итог")

	# Окно предмета (ItemTooltip): поверх меню, раскладку вкладки не меняет. Сумки нет — под куклой сумма
	# характеристик подобранных предметов.
	var tab := menu.character
	tab.refresh()
	await _frames(2)
	_check(not tab.has_method(&"_on_bag_input") and tab.stacked.get_child_count() > 0
			and tab._collected.text.contains(str(knight.items_collected)),
			"сумки нет: под куклой — «собрано предметов: %d» и их характеристики" % knight.items_collected)
	var column := tab.get_child(0) as Control
	var layout := column.size
	var cell: Control = null
	for button in tab._doll.get_children():
		if button.focus_mode != Control.FOCUS_NONE:  # слот с предметом
			cell = button
			break
	_check(cell != null, "на кукле есть предмет")
	if cell != null:
		cell.mouse_entered.emit()
		await _frames(3)
		_check(tab.tips.tip.visible and tab.tips.tip.modulate.a > 0.0 and column.size == layout,
				"окно предмета появилось поверх меню, кукла не сдвинулась")
		cell.mouse_exited.emit()
		await _frames(1)
		_check(not tab.tips.tip.visible, "мышь ушла с предмета — окно скрыто")
	_press_key(KEY_I)
	_check(not menu.visible and not get_tree().paused, "меню закрыто")


## CR-04: профиль хаба — души, таланты, сброс, сохранение; сцена хаба собирается.
func _check_meta_profile() -> void:
	MetaProfile.path = "user://test_profile.json"
	MetaProfile.legacy_path = "user://test_profile.cfg"
	SaveFile.remove(MetaProfile.path)
	MetaProfile.load_profile()
	var knight: HeroData = DataRegistry.hero(&"knight")
	var necro: HeroData = DataRegistry.hero(&"necromancer")
	var vigor := DataRegistry.talent(&"knight_vigor")
	var inheritance := DataRegistry.talent(&"inheritance")
	_check(DataRegistry.talents_for(knight).size() == 8, "у Рыцаря 8 талантов: 3 общих и 5 классовых")
	var mending := DataRegistry.talent(&"soul_mending")
	_check(mending != null and mending.is_global() and mending.stat == Player.STAT_REGEN and mending.max_rank == 4
			and is_equal_approx(mending.per_rank * mending.max_rank, 4.0),
			"Алтарь душ: «Исцеление души» — общий талант, 4 ранга, до 4 здоровья в секунду")
	_check(not MetaProfile.upgrade(vigor, knight), "без душ талант не купить")
	MetaProfile.grant(500, false)
	_check(MetaProfile.upgrade(vigor, knight) and MetaProfile.rank(vigor, knight) == 1 and MetaProfile.souls == 470,
			"«Закалка» куплена за 30 душ")
	_check(MetaProfile.next_cost(vigor, knight) == 45, "следующий ранг дороже")
	_check(not MetaProfile.upgrade(vigor, necro), "талант чужого класса не купить")
	MetaProfile.upgrade(inheritance, knight)
	_check(MetaProfile.rank(inheritance, necro) == 1, "общий талант действует для всех героев")
	MetaProfile.load_profile()
	_check(MetaProfile.souls == 430 and MetaProfile.rank(vigor, knight) == 1 and MetaProfile.count(&"runs") == 1,
			"профиль сохраняется и загружается")
	_check(MetaProfile.respec(knight) == 30 and MetaProfile.rank(vigor, knight) == 0
			and MetaProfile.rank(inheritance, knight) == 1 and MetaProfile.souls == 460,
			"сброс талантов класса возвращает души, общие таланты остаются")
	_check(MetaProfile.talents_for(knight) == {&"inheritance": 1}, "в забег уходят только взятые таланты")
	_check(DataRegistry.META_RULES.run_reward(200, 3, true, DataRegistry.BALANCE.hardcore_reward) == 370,
			"награда за забег: убийства + уровни + победа, в ХК ×2")
	_check_sanctuary()
	_check_save_file()
	_check_quests()
	SaveFile.remove(MetaProfile.path)
	MetaProfile.path = MetaProfile.DEFAULT_PATH
	MetaProfile.legacy_path = MetaProfile.LEGACY_PATH
	MetaProfile.load_profile()


## Шаг 10.3: ходячее Убежище — станции, статуи классов (закрытый класс не выбрать), окна станций.
func _check_sanctuary() -> void:
	var hub: Sanctuary = load(ScenePaths.HUB).instantiate()
	add_child(hub)
	# Шаг 11.12: реквизит в духе Diablo — из атласа, у крупного «нажать E» дальше.
	var gate_station: HubStation = hub.stations.filter(func(s: HubStation) -> bool: return s.id == &"gate")[0]
	_check([&"fire", &"gate", &"war_table", &"chronicle", &"board", &"altar", &"exit"].all(
			func(id: StringName) -> bool: return HubProp.has_prop(id)) and hub.fire.get_child(0) is HubProp
			and gate_station.reach() > HubStation.REACH and gate_station.height() > 60.0,
			"Убежище: костёр, портал, стол, летопись, доска, алтарь и дверь — из атласа реквизита")
	var castle_tiles: TileSet = LevelArt.style_named(SanctuaryMap.ART_STYLE)["tileset"]
	var carpets := hub.get_node("Level").get_children().filter(func(n: Node) -> bool: return n is CastleCarpet)
	var decor: Array = []
	for n in hub.props.get_children():
		if n != hub.fire and n.get_child_count() > 0 and n.get_child(0) is HubProp and (n.get_child(0) as HubProp).texture != null:
			decor.append(n)
	_check(FileAccess.file_exists(LevelArt.TILES_DIR + "castle.json") and hub.art.tile_set == castle_tiles
			and carpets.size() == 1 and HubProp.has_prop(&"pillar") and HubProp.has_prop(&"armor")
			and decor.size() >= SanctuaryMap.DECOR.size(),
			"Убежище — тронный зал замка: атлас «castle», ковровая дорожка, колонны и доспехи (%d)" % decor.size())
	var audio: AudioConfig = load("res://data/audio/audio.tres")
	_check(audio.hub_music != null and Sound.music_for(hub) == audio.hub_music and Sound.music_for(self) == audio.menu_music,
			"звук: в Убежище — свой эмбиент, в меню — свой (шаг 11.13)")
	_check(hub.stations.size() == DataRegistry.HEROES.size() + SanctuaryMap.STATIONS.size(),
			"Убежище: статуи всех классов и 6 станций")
	var statue_of := func(id: StringName) -> HubStation:
		for station in hub.stations:
			if station.hero != null and station.hero.id == id:
				return station
		return null
	var locked: HubStation = statue_of.call(&"blood_priest")
	var open: HubStation = statue_of.call(&"sorceress")
	var before := hub.hero
	hub.interact(locked)
	_check(locked.locked and hub.hero == before, "Убежище: закрытый класс у статуи не выбрать")
	hub.interact(open)
	_check(hub.hero.id == &"sorceress" and MetaProfile.last_hero == &"sorceress" and open.selected,
			"Убежище: у статуи открытого класса герой сменился и запомнился")
	var altar := hub.open_window(&"altar") as TalentsWindow
	_check(altar.visible and hub.window_open() and altar._rows.get_child_count() == DataRegistry.talents_for(hub.hero).size(),
			"Убежище: Алтарь душ — таланты выбранного героя")
	altar.close_window()
	var board := hub.open_window(&"board")
	var quest_rows := board.body.get_child(0).get_child(0)
	_check(quest_rows.get_child_count() == DataRegistry.QUESTS.size(), "Убежище: на Доске все задания")
	board.close_window()
	var chronicle := hub.open_window(&"chronicle")
	var tabs: TabContainer = chronicle.body.get_child(0)
	var bestiary := tabs.get_child(1).get_child(0)
	_check(tabs.get_tab_count() == 4 and bestiary.get_child_count() == DataRegistry.ENEMIES.size(),
			"Убежище: Летопись — рекорды, бестиарий, трофеи, записи")
	chronicle.close_window()
	var gate := hub.open_window(&"gate") as GateWindow
	gate.hardcore_toggle.button_pressed = true
	_check(hub.hardcore and hub.window_open(), "Убежище: Врата — «Хардкор» на забег")
	# Шаг 12.3: кнопка печатей во Вратах открывает окно печатей; + и - меняют ранг в пределах данных.
	hub.seals = {}
	gate.seals_button.pressed.emit()
	var seals_window := hub._windows[&"seals"] as SealsWindow
	var first: SealData = DataRegistry.SEALS[0]
	var cells: Array = seals_window._rows.get(first.id, [])
	var plus := cells[2] as Button if cells.size() == 3 else null
	for i in first.max_rank + 2:
		if plus != null:
			plus.pressed.emit()
	var capped := seals_window.rank_of(first.id)
	(cells[1] as Button).pressed.emit()
	_check(seals_window.visible and not gate.visible and seals_window._rows.size() == DataRegistry.SEALS.size()
			and capped == first.max_rank and seals_window.rank_of(first.id) == first.max_rank - 1
			and seals_window._total.text.contains(str(SealData.heat_of(hub.seals))),
			"Убежище: окно печатей — все печати, ранг не выше предела, сумма Скверны (%d)" % SealData.heat_of(hub.seals))
	seals_window._back()
	_check(gate.visible and not seals_window.visible, "Убежище: из окна печатей — назад к Вратам")
	hub.seals = {}
	gate.close_window()
	_check(not hub.window_open(), "Убежище: окна закрываются")
	hub.queue_free()


## Шаг 10: надёжный профиль — порча, обрыв записи, перенос старого формата, мусор в файле.
func _check_save_file() -> void:
	var main := MetaProfile.path
	SaveFile.remove(main)
	MetaProfile.load_profile()
	MetaProfile.grant(100, false)
	MetaProfile.grant(50, true)  # прошлая версия (100 душ) уходит в резервную копию
	_check(FileAccess.file_exists(main + SaveFile.BACKUP_SUFFIX), "профиль: при записи остаётся резервная копия")
	MetaProfile.take_notice()

	_overwrite(main, FileAccess.get_file_as_string(main).replace("150", "999"))
	MetaProfile.load_profile()
	_check(MetaProfile.souls == 100 and MetaProfile.take_notice() == "PROFILE_RESTORED"
			and FileAccess.file_exists(main + SaveFile.DAMAGED_SUFFIX),
			"профиль: правка файла ломает контрольную сумму — загружена копия, испорченный файл сохранён")
	_check(SaveFile.read(main, MetaProfile.FORMAT).source == SaveFile.Source.MAIN,
			"профиль: восстановленная копия снова стала основным файлом")

	MetaProfile.grant(7, false)
	_overwrite(main + SaveFile.TEMP_SUFFIX, "{\"format\": \"vault-profile\", \"vers")
	MetaProfile.load_profile()
	_check(MetaProfile.souls == 107 and not FileAccess.file_exists(main + SaveFile.TEMP_SUFFIX),
			"профиль: обрывок временного файла не мешает, основной цел, обрывок убран")
	var temp_text := FileAccess.get_file_as_string(main)
	DirAccess.rename_absolute(main, main + SaveFile.TEMP_SUFFIX)
	MetaProfile.load_profile()
	_check(MetaProfile.souls == 107 and SaveFile.read(main, MetaProfile.FORMAT).source == SaveFile.Source.MAIN,
			"профиль: обрыв между записью и переименованием — берётся целый временный файл")

	for suffix in ["", SaveFile.BACKUP_SUFFIX]:
		_overwrite(main + suffix, temp_text.left(40))
	MetaProfile.load_profile()
	_check(MetaProfile.souls == 0 and MetaProfile.take_notice() == "PROFILE_LOST", "профиль: всё испорчено — новый профиль и сообщение")

	SaveFile.remove(main)
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "souls", 321)
	legacy.set_value("meta", "last_hero", "necromancer")
	legacy.set_value("meta", "runs", 4)
	legacy.set_value("meta", "victories", 1)
	legacy.set_value("meta", "talents", {"*": {"inheritance": 2}, "knight": {"knight_vigor": 1}})
	legacy.save(MetaProfile.legacy_path)
	MetaProfile.load_profile()
	_check(MetaProfile.souls == 321 and MetaProfile.last_hero == &"necromancer" and MetaProfile.count(&"runs") == 4
			and MetaProfile.rank(DataRegistry.talent(&"inheritance"), DataRegistry.hero(&"knight")) == 2
			and FileAccess.file_exists(main) and FileAccess.file_exists(MetaProfile.legacy_path + ".migrated")
			and not FileAccess.file_exists(MetaProfile.legacy_path),
			"профиль: старый profile.cfg перенесён в новый формат")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MetaProfile.legacy_path + ".migrated"))

	SaveFile.write(main, MetaProfile.FORMAT, MetaProfile.VERSION,
			{"souls": -50, "chronicle": {"counters": {"runs": "много", "victories": -9}}, "talents": {"*": {"inheritance": "x", "ancestral_wisdom": 1e30}}})
	MetaProfile.load_profile()
	_check(MetaProfile.souls == 0 and MetaProfile.count(&"runs") == 0 and MetaProfile.count(&"victories") == 0
			and MetaProfile.rank(DataRegistry.talent(&"inheritance"), DataRegistry.hero(&"knight")) == 0
			and MetaProfile.rank(DataRegistry.talent(&"ancestral_wisdom"), DataRegistry.hero(&"knight"))
				== DataRegistry.talent(&"ancestral_wisdom").max_rank,
			"профиль: мусор в данных приводится к пределам")
	SaveFile.remove(main)


## Шаг 10: «Летопись», задания Доски и открытия классов и навыков; перенос профиля версии 1.
func _check_quests() -> void:
	var main := MetaProfile.path
	SaveFile.remove(main)
	MetaProfile.load_profile()
	var locked := MetaProfile.locked_skills()
	var with_unlock := DataRegistry.QUESTS.filter(func(q: QuestData) -> bool: return q.unlock != &"")
	_check(DataRegistry.QUESTS.size() >= 10 and with_unlock.size() == 10, "задания: 13 на доске, 10 открывают класс или навык")
	_check(not MetaProfile.is_unlocked(&"pyromancer") and MetaProfile.is_unlocked(&"knight")
			and MetaProfile.is_unlocked(&"sorceress") and locked.size() == 7 and &"meteor" in locked,
			"открытия: новый профиль — 3 класса и все навыки, кроме 7 за задания")
	var starting_locked := DataRegistry.HEROES.filter(func(h: HeroData) -> bool: return h.starting_weapon in locked)
	_check(starting_locked.is_empty(), "открытия: стартовый навык героя не закрыт")

	var rng := RandomNumberGenerator.new()
	rng.seed = 10
	var leaked := false
	for i in 300:
		for id in UpgradePool.roll({&"sword_arc": 1}, rng, {}, locked):
			leaked = leaked or id in locked
	_check(not leaked, "открытия: закрытых навыков нет в картах левел-апа")

	var necropolis := DataRegistry.quest(&"necropolis")
	var unique: StringName = DataRegistry.UNIQUE_ITEMS[0].id
	var enemy: StringName = DataRegistry.ENEMIES[0].id
	MetaProfile.grant(50, false, {"hero": "knight", "depth": 2, "levels": 1, "kills": 40, "bosses": 1, "chests": 2,
			"uniques": [unique, unique, "нет_такого"], "seen": {enemy: 5, "нет_такого": 3}})
	MetaProfile.grant(10, false, {"hero": "knight", "depth": 1, "levels": 0, "kills": 70})
	var record := MetaProfile.hero_record(&"knight")
	_check(MetaProfile.count(&"depth") == 2 and MetaProfile.count(&"kills") == 110 and MetaProfile.count(&"runs") == 2
			and MetaProfile.count(&"trophies") == 1 and MetaProfile.count(&"bestiary") == 1 and MetaProfile.seen(enemy) == 5
			and record.runs == 2 and record.best_depth == 2 and record.best_kills == 70 and record.kills == 110,
			"Летопись: суммы, лучшая глубина, трофеи и бестиарий без неизвестных id")
	var claimable := MetaProfile.claimable_quests()
	_check(MetaProfile.quest_done(necropolis) and claimable.size() == 1 and claimable[0] == necropolis
			and not MetaProfile.is_unlocked(&"pyromancer"), "задание выполнено — награда ждёт на доске")
	_check(MetaProfile.claim(necropolis) and not MetaProfile.claim(necropolis) and MetaProfile.is_unlocked(&"pyromancer")
			and not MetaProfile.claim(DataRegistry.quest(&"inferno")), "награда: класс открыт, второй раз не выдаётся")
	MetaProfile.load_profile()
	_check(MetaProfile.is_unlocked(&"pyromancer") and MetaProfile.quest_claimed(necropolis) and MetaProfile.count(&"kills") == 110,
			"Летопись и открытия сохраняются в профиле")

	SaveFile.remove(main)
	SaveFile.write(main, MetaProfile.FORMAT, 1, {"souls": 75, "last_hero": "witch_hunter", "runs": 6, "victories": 2,
			"talents": {"*": {"inheritance": 1}}})
	MetaProfile.load_profile()
	_check(MetaProfile.count(&"runs") == 6 and MetaProfile.count(&"victories") == 2 and MetaProfile.souls == 75
			and MetaProfile.is_unlocked(&"witch_hunter") and not MetaProfile.is_unlocked(&"pyromancer")
			and SaveFile.read(main, MetaProfile.FORMAT).version == MetaProfile.VERSION,
			"профиль версии 1: забеги и победы — в Летопись, последний герой остаётся открытым")
	SaveFile.remove(main)

	# Версия 2: задание и лор Владыки Гнили (финальный босс до замены) — под id Владыки Бездны.
	SaveFile.write(main, MetaProfile.FORMAT, 2, {"quests": ["rot_lord"], "unlocked": ["blood_priest"],
			"chronicle": {"counters": {"victories": 1}, "lore": ["rot_lord"]}})
	MetaProfile.load_profile()
	var final_quest := DataRegistry.quest(&"abyss_lord")
	_check(final_quest != null and MetaProfile.quest_claimed(final_quest) and not final_quest in MetaProfile.claimable_quests()
			and MetaProfile.has_lore(&"abyss_lord") and MetaProfile.is_unlocked(&"blood_priest"),
			"профиль версии 2: полученная награда за финального босса и прочитанный трактат не теряются")
	SaveFile.remove(main)


## Шаг 10: итог забега для «Летописи» — враги, встреченные в мире, без союзных призывов.
func _check_chronicle_recorder() -> void:
	var chronicle: ChronicleRecorder = _world.get_node("Systems/Chronicle")
	var summary := chronicle.summary()
	var seen: Dictionary = summary.seen
	var allies := seen.keys().filter(func(id: StringName) -> bool: return DataRegistry.enemy(id) == null)
	_check(summary.hero == String(RunConfig.get_hero().id) and summary.depth == GameState.level_index + 1
			and not seen.is_empty() and allies.is_empty(), "Летопись: мир собирает итог забега %s" % [seen.keys()])


func _overwrite(file_path: String, text: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _count_enemies(id: StringName) -> int:
	return _world.enemies.get_children().filter(func(n: Node) -> bool:
		return n is Enemy and not n.dead and n.data.id == id).size()


## Пройти обычный уровень: таймер → босс → Ключ → портал.
func _complete_level(knight: Player) -> void:
	var start := GameState.level_index
	GameState.level_time_left = 0.05
	await _seconds(0.5)
	for boss in _bosses_alive():
		boss.take_damage(1.0e9, 1)
	await _frames(2)
	var key := _find_key()
	if key != null:
		knight.teleport(key.global_position)
	await _wait_until(func() -> bool: return _world.flow.phase == LevelFlow.Phase.PORTAL, 3.0)
	knight.teleport(_world.flow.portal.global_position)
	await _wait_until(func() -> bool:
		return GameState.level_index == start + 1 and _world.flow.phase in [LevelFlow.Phase.WAVES, LevelFlow.Phase.FINAL_BOSS], 10.0)
	await _frames(2)
	_check(GameState.level_index == start + 1, "уровень %d пройден" % (start + 1))


## Подойти к объекту карты данного класса и подождать.
func _visit(player: Player, type: Variant) -> MapObject:
	var target := _find_prop(type) as MapObject
	if target != null:
		player.teleport(target.global_position)
		await _seconds(0.3)
	return target


func _find_prop(type: Variant) -> Node:
	for child in _world.props.get_children():
		if is_instance_of(child, type):
			return child
	return null


func _check_defeat() -> void:
	_world.queue_free()
	GameState.end_run()
	await _frames(2)
	_run_result = -1
	RunConfig.start_new_run(DataRegistry.HEROES[1], true, 777)
	_world = load(ScenePaths.WORLD).instantiate()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	(_world.get_node("PauseMenu") as PauseMenu).pause_on_focus_out = false
	await _wait_until(func() -> bool: return _world.find_player(1) != null, 10.0)
	var player := _world.find_player(1)
	player.health = 1.0  # один удар снимает не больше max_hit_share
	player.take_damage(1.0e9)
	await _frames(2)
	_check(not player.alive and _run_result == 0, "гибель всех игроков завершает забег поражением")
	_check(_world.flow.phase == LevelFlow.Phase.DEFEAT and not GameState.running, "мир остановлен после поражения")
	GameState.end_run()


# --- Вспомогательное ---

## Пока проверяется не левел-ап, карты своего игрока выбираются сами — иначе панель ставит мир на паузу.
func _on_level_up_offered(peer_id: int, cards: Array) -> void:
	_offers.append([peer_id, cards])
	if _auto_pick and peer_id == 1:
		_drain_offers.call_deferred()


func _drain_offers() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var guard := 0
	while not _world.upgrades.current_offer(1).is_empty() and guard < 100:
		_world.upgrades.apply_choice(1, _world.upgrades.current_offer(1)[0])
		guard += 1
	_world.get_node("LevelUpPanel").hide()
	_world.request_pause(&"level_up", false)


func _bosses_alive() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for child in _world.enemies.get_children():
		if child is Enemy and not child.dead and child.data.is_boss:
			result.append(child)
	return result


func _find_key() -> Pickup:
	for child in _world.pickups.get_children():
		if child is Pickup and child.kind == Pickup.Kind.KEY:
			return child
	return null


## Есть ли у HUD метка цели этого цвета (стрелка у края экрана или маркер над целью).
func _has_marker(color: Color) -> bool:
	var markers: OffscreenMarkers = _world.get_node("HUD").markers
	return markers.targets().any(func(target: Array) -> bool: return target[1] == color)


## Индекс предложения торговца: по виду (предмет) или по id товара.
func _offer_index(merchant: Merchant, key: StringName) -> int:
	for i in merchant.offers.size():
		var offer: Dictionary = merchant.offers[i]
		if offer["kind"] == key or offer.get("id", &"") == key:
			return i
	return -1


## Нажать и отпустить клавишу — событие идёт тем же путём, что ввод игрока.
func _press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(ceili(seconds * Engine.physics_ticks_per_second))


## timeout — в игровом времени. Но генерация уровня идёт в фоновом потоке в реальном времени, а с --fixed-fps
## без окна 600 кадров пролетают за ~10 мс. Поэтому ждём и не меньше REAL_TIME_FLOOR_MS реального времени.
func _wait_until(condition: Callable, timeout: float) -> void:
	const REAL_TIME_FLOOR_MS := 5000
	var deadline := Time.get_ticks_msec() + REAL_TIME_FLOOR_MS
	var frames := 0
	while frames < ceili(timeout * Engine.physics_ticks_per_second) or Time.get_ticks_msec() < deadline:
		if condition.call():
			return
		await get_tree().physics_frame
		frames += 1


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  OK   ", description)
	else:
		_failures += 1
		printerr("  FAIL ", description)
