class_name UpgradePool
extends RefCounted
## Выбор карт левел-апа: ровно CARD_COUNT уникальных карт при любом состоянии героя (ФТ-10, ТК-10).
## Порядок: карта ступени эволюции (DESIGN 3) — в предложении, как только есть (не больше
## UpgradeRules.evolution_cards_per_offer), затем оружие и пассивки, которые можно взять или улучшить, и, если
## их меньше трёх, запасные карты (FILLER, без предела уровня). Оружие занимает слоты
## (UpgradeRules.max_weapons), пассивки — нет. Взятая эволюция дальше качается как обычное оружие.
## Ступени эволюции: на 5, 10, 15 и 20 уровне навыка — карта следующей ступени (I–IV), без пассивки. У навыка
## с обликом эволюции (SkillData.evolution) ступень II — превращение (карта с id облика), у остальных и после
## превращения — карта «evo:<навык>» (сильнее урон, перезарядка, область, количество — SkillStats).
## Разнообразие: в новом предложении есть и оружие, и пассивка (если обе можно взять); карты из
## прошлых предложений выпадают реже (антиповтор, UpgradeRules.repeat_weights); изгнанные — никогда.
## Редкость карты (обычная, редкая, эпическая, легендарная) решает, сколько уровней карта даёт сразу.
##
## Шаг 4. Сродство класса: навыки с тегами класса (HeroData.affinity_tags) выпадают чаще.
## Карта руны — руна забега в конкретный навык героя, id вида «rune:<руна>:<навык>» (add_rune_cards):
## встаёт на место обычной карты или запасной, поэтому карт по-прежнему ровно три и все разные.
## Изгоняется руна целиком (banish_key). Проверка — tools/mechanics_test.gd.

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

const CARD_COUNT := 3
const RUNE_PREFIX := "rune:"
const EVOLUTION_PREFIX := "evo:"
const STAGE_NAMES: PackedStringArray = ["", "I", "II", "III", "IV", "V", "VI"]


## levels: id улучшения → уровень у героя (0 или нет ключа — не взято).
## repeat: id → множитель веса (антиповтор); blocked: id, которых в выборе быть не должно (изгнанные,
## карты, что уже лежат на столе, когда меняется одна). count — сколько карт нужно; карты эволюции — только
## в полном предложении (замена изгнанной карты их не добавляет).
## affinity — маска тегов сродства класса (DataRegistry.tag_mask(HeroData.affinity_tags)).
## stages — ступени эволюции навыков (Player.evolution_stages): id навыка → ступень.
static func roll(levels: Dictionary, rng: RandomNumberGenerator, repeat: Dictionary = {}, blocked: Array = [],
		count: int = CARD_COUNT, affinity: int = 0, stages: Dictionary = {}) -> Array[StringName]:
	var weapons := 0
	for id: StringName in levels:
		var owned := DataRegistry.upgrade(id)
		if owned != null and levels[id] > 0 and owned.kind == UpgradeData.Kind.WEAPON:
			weapons += 1
	var free_weapon_slot := weapons < DataRegistry.UPGRADE_RULES.max_weapons

	var evolutions: Array[StringName] = []
	var regular: Array[StringName] = []
	var fillers: Array[StringName] = []
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		if upgrade.id in blocked:
			continue
		var level: int = levels.get(upgrade.id, 0)
		var weapon := upgrade as SkillData
		if weapon != null and level > 0:
			var card := evolution_card(weapon, level, int(stages.get(weapon.id, 0)), levels)
			if card != &"" and card in blocked and card != evolution_card_id(weapon.id):
				card = evolution_card_id(weapon.id)  # облик закрыт в профиле — ступень без превращения
			if card != &"" and not card in blocked:
				evolutions.append(card)
		if weapon != null and weapon.is_evolution:
			if level > 0 and not upgrade.is_maxed(level):
				regular.append(upgrade.id)  # уже взятая эволюция качается как оружие
			continue  # впервые облик эволюции выпадает только картой ступени
		if weapon != null and weapon.evolution != null and levels.get(weapon.evolution.id, 0) > 0:
			continue  # оружие уже эволюционировало
		match upgrade.kind:
			UpgradeData.Kind.FILLER:
				fillers.append(upgrade.id)
			UpgradeData.Kind.WEAPON:
				if _can_take(upgrade, level, free_weapon_slot):
					regular.append(upgrade.id)
			UpgradeData.Kind.PASSIVE:
				if _can_take(upgrade, level, true):
					regular.append(upgrade.id)

	var cards: Array[StringName] = []
	_shuffle(evolutions, rng)
	var evolution_slots := DataRegistry.UPGRADE_RULES.evolution_cards_per_offer if count == CARD_COUNT else 0
	for id in evolutions:
		if cards.size() < mini(count, evolution_slots):
			cards.append(id)
	var rest: Array[StringName] = []
	if count == CARD_COUNT:  # пёстрое предложение: хотя бы одно оружие и одна пассивка
		for kind in [UpgradeData.Kind.WEAPON, UpgradeData.Kind.PASSIVE]:
			if cards.size() + rest.size() >= count or _has_kind(cards, kind) or _has_kind(rest, kind):
				continue
			var of_kind := regular.filter(func(id: StringName) -> bool: return DataRegistry.upgrade(id).kind == kind)
			if not of_kind.is_empty():
				var picked := _pick(of_kind, repeat, rng, affinity)
				rest.append(picked)
				regular.erase(picked)
	while cards.size() + rest.size() < count and not regular.is_empty():
		var picked := _pick(regular, repeat, rng, affinity)
		rest.append(picked)
		regular.erase(picked)
	_shuffle(fillers, rng)
	for id in fillers:
		if cards.size() + rest.size() < count:
			rest.append(id)
	_shuffle(rest, rng)  # оружие не всегда первым
	cards.append_array(rest)
	return cards


## Изгнать можно оружие, пассивку и руну; эволюцию и запасную карту — нет (гарантия ФТ-10 держится на них).
static func can_banish(card_id: StringName, evolution: bool) -> bool:
	if is_rune_card(card_id):
		return true
	var upgrade := DataRegistry.upgrade(card_id)
	return upgrade != null and not evolution and upgrade.kind != UpgradeData.Kind.FILLER


## Что запоминается при изгнании: у карты руны — руна целиком («rune:<руна>»), у остальных — сама карта.
static func banish_key(card_id: StringName) -> StringName:
	var socket := parse_rune_card(card_id)
	return StringName(RUNE_PREFIX + String(socket[0])) if not socket.is_empty() else card_id


## Редкость карты. luck — шанс удачного удара героя: «Удача» повышает шанс редких карт.
## Редкость не даёт больше уровней, чем осталось до максимума: лишнее понижается до подходящей.
static func roll_rarity(upgrade: UpgradeData, level: int, luck: float, rng: RandomNumberGenerator) -> Rarity:
	var rules := DataRegistry.UPGRADE_RULES
	var weights := _lucky(rules.rarity_weights, luck)
	var rarity := rng.rand_weighted(weights)
	if upgrade.max_level > 0:
		while rarity > Rarity.COMMON and rules.rarity_levels[rarity] > upgrade.max_level - level:
			rarity -= 1
	return rarity as Rarity


## Сколько уровней даёт карта этой редкости.
static func levels_for(rarity: int) -> int:
	var levels := DataRegistry.UPGRADE_RULES.rarity_levels
	return levels[clampi(rarity, 0, levels.size() - 1)]


## Нужно не меньше CARD_COUNT запасных карт, иначе гарантия ФТ-10 не держится.
static func filler_count() -> int:
	var n := 0
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		if upgrade.kind == UpgradeData.Kind.FILLER:
			n += 1
	return n


# --- Ступени эволюции ---

## Карта следующей ступени эволюции навыка skill уровня level со ступенью stage; пусто — ступени нет (все взяты
## или навык ещё не дорос: ступень N — с уровня evolution_step × N). Ступень превращения у навыка с обликом
## эволюции — карта облика (если облик ещё не взят, levels — уровни героя).
static func evolution_card(skill: SkillData, level: int, stage: int, levels: Dictionary = {}) -> StringName:
	var rules := DataRegistry.UPGRADE_RULES
	if stage >= rules.evolution_stages or level < rules.evolution_step * (stage + 1):
		return &""
	if is_transform(skill, stage + 1) and int(levels.get(skill.evolution.id, 0)) == 0:
		return skill.evolution.id
	return evolution_card_id(skill.id)


## Ступень stage навыка skill — превращение в облик эволюции.
static func is_transform(skill: SkillData, stage: int) -> bool:
	return skill != null and skill.evolution != null and stage == DataRegistry.UPGRADE_RULES.evolution_transform_stage


static func evolution_card_id(skill_id: StringName) -> StringName:
	return StringName(EVOLUTION_PREFIX + String(skill_id))


## id навыка из id карты ступени («evo:<навык>»); пусто — это не карта ступени. id приходит и по сети.
static func parse_evolution_card(card_id: StringName) -> StringName:
	var text := String(card_id)
	if not text.begins_with(EVOLUTION_PREFIX) or text.length() == EVOLUTION_PREFIX.length():
		return &""
	return StringName(text.substr(EVOLUTION_PREFIX.length()))


## «II» для ступени 2.
static func stage_name(stage: int) -> String:
	return STAGE_NAMES[stage] if stage >= 0 and stage < STAGE_NAMES.size() else str(stage)


# --- Карты рун (шаг 4) ---

static func rune_card_id(rune_id: StringName, skill_id: StringName) -> StringName:
	return StringName("%s%s:%s" % [RUNE_PREFIX, rune_id, skill_id])


## [id руны, id навыка] из id карты руны; пусто — это не карта руны. id приходит и по сети — разбор строгий.
static func parse_rune_card(card_id: StringName) -> Array[StringName]:
	var text := String(card_id)
	if not text.begins_with(RUNE_PREFIX):
		return []
	var parts := text.substr(RUNE_PREFIX.length()).split(":")
	if parts.size() != 2 or parts[0] == "" or parts[1] == "":
		return []
	return [StringName(parts[0]), StringName(parts[1])]


static func is_rune_card(card_id: StringName) -> bool:
	return not parse_rune_card(card_id).is_empty()


## Можно ли вставить руну rune в навык skill (runes — Player.runes): у навыка есть действие, руна подходит
## ему по тегам и действию, такой руны в навыке ещё нет и есть свободное гнездо (UpgradeRules.runes_per_skill).
static func can_socket(rune: SkillModifier, skill: SkillData, runes: Dictionary) -> bool:
	if rune == null or skill == null or skill.action == null:
		return false
	if not SkillStats.fits(rune, DataRegistry.tag_mask(skill.tags), skill.action.kind()):
		return false
	var socketed: Array = runes.get(skill.id, [])
	return not rune.id in socketed and socketed.size() < DataRegistry.UPGRADE_RULES.runes_per_skill


## Карты рун, которые можно предложить герою: [[id карты, вес], …]. Только во взятые навыки; вес — по редкости
## руны (с «Удачей») и антиповтору; изгнанные руны и карты из blocked не предлагаются.
static func rune_candidates(levels: Dictionary, runes: Dictionary, luck: float, repeat: Dictionary = {},
		blocked: Array = []) -> Array:
	var result := []
	var weights := _lucky(DataRegistry.UPGRADE_RULES.rune_rarity_weights, luck)
	for id: Variant in levels:
		var skill := DataRegistry.upgrade(StringName(str(id))) as SkillData
		if skill == null or int(levels[id]) <= 0:
			continue
		for rune: SkillModifier in DataRegistry.SKILL_MODIFIERS:
			if not can_socket(rune, skill, runes):
				continue
			var card := rune_card_id(rune.id, skill.id)
			if card in blocked or banish_key(card) in blocked:
				continue
			var weight: float = weights[clampi(rune.rarity, 0, weights.size() - 1)] * float(repeat.get(card, 1.0))
			result.append([card, maxf(weight, 0.01)])
	return result


## Карты рун в предложение cards (на месте прежних, число и уникальность карт не меняются): с шансом
## chance (меньше 0 — UpgradeRules.rune_card_chance) — одна вместо обычной карты (той, чей тип
## в предложении повторяется, — пёстрость сохраняется); запасные карты руны заменяют всегда, пока есть
## подходящие. Эволюции не заменяются.
static func add_rune_cards(cards: Array[StringName], levels: Dictionary, runes: Dictionary, luck: float,
		rng: RandomNumberGenerator, repeat: Dictionary = {}, blocked: Array = [], chance: float = -1.0) -> void:
	if chance < 0.0:
		chance = DataRegistry.UPGRADE_RULES.rune_card_chance
	var targets: Array[int] = []
	for i in cards.size():
		var upgrade := DataRegistry.upgrade(cards[i])
		if upgrade != null and upgrade.kind == UpgradeData.Kind.FILLER:
			targets.append(i)
	if rng.randf() < chance:
		var regular := _replaceable(cards)
		if not regular.is_empty() and targets.size() < cards.size():
			targets.push_front(regular[rng.randi_range(0, regular.size() - 1)])
	if targets.is_empty():
		return
	var candidates := rune_candidates(levels, runes, luck, repeat, blocked + Array(cards))
	for index in targets:
		if candidates.is_empty():
			return
		var weights := PackedFloat32Array()
		for candidate: Array in candidates:
			weights.append(candidate[1])
		var picked: StringName = candidates[rng.rand_weighted(weights)][0]
		cards[index] = picked
		var rune := parse_rune_card(picked)[0]
		candidates = candidates.filter(func(candidate: Array) -> bool: return parse_rune_card(candidate[0])[0] != rune)


static func _can_take(upgrade: UpgradeData, level: int, has_free_slot: bool) -> bool:
	if level > 0:
		return not upgrade.is_maxed(level)
	return has_free_slot


static func _has_kind(ids: Array[StringName], kind: UpgradeData.Kind) -> bool:
	for id in ids:
		var upgrade := DataRegistry.upgrade(id)
		if upgrade != null and upgrade.kind == kind:
			return true
	return false


## Обычные карты, которые можно заменить руной (не эволюции и не запасные): сначала карты повторяющегося
## типа — тогда в предложении остаются и навык, и пассивка; если повторов нет — карта навыка (руна тоже
## улучшает навык), иначе любая обычная.
static func _replaceable(cards: Array[StringName]) -> Array[int]:
	var by_kind := {}
	var regular: Array[int] = []
	for i in cards.size():
		var upgrade := DataRegistry.upgrade(cards[i])
		if upgrade == null or upgrade.kind == UpgradeData.Kind.FILLER:
			continue
		if upgrade is SkillData and (upgrade as SkillData).is_evolution:
			continue
		by_kind[upgrade.kind] = int(by_kind.get(upgrade.kind, 0)) + 1
		regular.append(i)
	var kind_of := func(i: int) -> int: return DataRegistry.upgrade(cards[i]).kind
	var repeated := regular.filter(func(i: int) -> bool: return by_kind[kind_of.call(i)] > 1)
	if not repeated.is_empty():
		return repeated
	var skills := regular.filter(func(i: int) -> bool: return kind_of.call(i) == UpgradeData.Kind.WEAPON)
	return skills if not skills.is_empty() else regular


## Случайная карта с учётом антиповтора и сродства класса: недавние выпадают реже, но не исчезают совсем.
static func _pick(ids: Array, repeat: Dictionary, rng: RandomNumberGenerator, affinity: int = 0) -> StringName:
	var weights := PackedFloat32Array()
	for id: StringName in ids:
		var weight := maxf(float(repeat.get(id, 1.0)), 0.01)
		var skill := DataRegistry.upgrade(id) as SkillData
		if affinity != 0 and skill != null and DataRegistry.tag_mask(skill.tags) & affinity:
			weight *= DataRegistry.UPGRADE_RULES.affinity_weight
		weights.append(weight)
	return ids[rng.rand_weighted(weights)]


## Веса редкости с «Удачей»: редкие (все, кроме первого) ×(1 + luck_factor × удача).
static func _lucky(base: PackedFloat32Array, luck: float) -> PackedFloat32Array:
	var weights := base.duplicate()
	for r in range(1, weights.size()):
		weights[r] *= 1.0 + DataRegistry.UPGRADE_RULES.luck_factor * maxf(luck, 0.0)
	return weights


## Фишер — Йейтс на RNG хоста: карты воспроизводимы от сида забега.
static func _shuffle(items: Array[StringName], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := items[i]
		items[i] = items[j]
		items[j] = tmp
