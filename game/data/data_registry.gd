class_name DataRegistry
extends RefCounted
## Каталог игровых данных (шаг 2, R1). Списки собираются сами: каждый .tres нужного класса из папки
## data/<вид>/ попадает в каталог при первом обращении. Новый герой, враг, оружие, предмет, статус или
## тег — один новый файл, без правки кода. ResourceLoader.list_directory видит и ресурсы экспортированной
## сборки (.remap).
##
## Порядок — по полю order (если оно есть у ресурса), затем по id. Он одинаковый у всех участников
## сессии, поэтому номера в списках (биты тегов, выбор аффиксов от сида) совпадают у хоста и клиентов.
## Повтор id — ошибка данных: в каталог попадает первый файл, в журнал — ошибка.

const UPGRADE_RULES: UpgradeRules = preload("res://data/upgrades/upgrade_rules.tres")
const LOOT_TABLE: LootTable = preload("res://data/loot/loot_table.tres")
const META_RULES: MetaRules = preload("res://data/talents/meta_rules.tres")
## Золото, зелья и цены (CR-14).
const ECONOMY: EconomyTable = preload("res://data/economy/economy.tres")
## Формулы урона, защиты, опыта и роста врагов (шаг 2, R7).
const BALANCE: BalanceConfig = preload("res://data/balance/balance.tres")
## Облик без влияния на игру (шаг 11.8): свет, «сочность», частицы — у каждого участника свой.
const VISUAL: VisualConfig = preload("res://data/visual/visual.tres")
## Битов в маске тегов: целое GDScript — 64 бита, старший не трогаем.
const MAX_TAGS := 62

## Герои в порядке показа в хабе (HeroData.order).
static var HEROES: Array = _scan("res://data/heroes/", HeroData)
## Все враги, включая улучшенные тиры (CR-09), мини-босса статуи и боссов.
static var ENEMIES: Array = _scan("res://data/enemies/", EnemyData)
static var ELITE_AFFIXES: Array = _scan("res://data/enemies/elite_affixes/", EliteAffixData)
## Навыки (data/skills/), их эволюции, пассивки и запасные карты (data/upgrades/); карты левел-апа
## выбираются случайно (ФТ-10).
static var UPGRADES: Array = _merge(_scan("res://data/skills/", SkillData), _scan("res://data/upgrades/", UpgradeData))
## Модификаторы навыков — руны забега (шаг 3); карты рун в левел-апе — шаг 4 (UpgradePool).
static var SKILL_MODIFIERS: Array = _scan("res://data/skills/modifiers/", SkillModifier)
## Резонансы тегов (шаг 4): навыки с одним тегом усиливают друг друга (Synergies).
static var SYNERGIES: Array = _scan("res://data/synergies/", SynergyData)
static var ITEM_BASES: Array = _scan("res://data/loot/bases/", ItemBaseData)
static var AFFIXES: Array = _scan("res://data/loot/affixes/", AffixData)
static var UNIQUE_ITEMS: Array = _scan("res://data/loot/uniques/", UniqueItemData)
## Таланты хаба (CR-04): порядок показа — TalentData.order.
static var TALENTS: Array = _scan("res://data/talents/", TalentData)
## Задания Доски заданий в Убежище (шаг 10): открывают классы и навыки.
static var QUESTS: Array = _scan("res://data/quests/", QuestData)
## Печати Скверны — модификаторы сложности забега (шаг 12.3).
static var SEALS: Array = _scan("res://data/seals/", SealData)
## Интерактивные точки карты и записи лора (шаг 8).
static var INTERACTABLES: Array = _scan("res://data/interactables/", InteractableData)
static var LORE: Array = _scan("res://data/lore/", LoreData)
static var MERCHANTS: Array = _scan("res://data/merchants/", MerchantData)
static var GOODS: Array = _scan("res://data/merchants/goods/", GoodsData)
## Ядро боя (шаг 2): характеристики, теги, статусы и их реакции.
static var STATS: Array = _scan("res://data/stats/", StatDef)
static var TAGS: Array = _scan("res://data/tags/", TagDef)
static var STATUSES: Array = _scan("res://data/statuses/", StatusEffectData)
static var STATUS_REACTIONS: Array = _scan("res://data/statuses/reactions/", StatusReaction)
## Биомы — этапы круга забега (шаг 9): условие CVAE, волны с боссом, правила слоя объектов. Порядок — этапы.
static var BIOMES: Array = _scan("res://data/biomes/", BiomeData)

static var _enemies := _index(ENEMIES)
static var _elite_affixes := _index(ELITE_AFFIXES)
static var _upgrades := _index(UPGRADES)
static var _item_bases := _index(ITEM_BASES)
static var _affixes := _index(AFFIXES)
static var _unique_items := _index(UNIQUE_ITEMS)
static var _talents := _index(TALENTS)
static var _quests := _index(QUESTS)
static var _seals := _index(SEALS)
static var _interactables := _index(INTERACTABLES)
static var _lore := _index(LORE)
static var _biomes := _index(BIOMES)
static var _heroes := _index(HEROES)
## Открытие (id героя или навыка) → задание, которое его открывает; после _heroes и _upgrades.
static var _quests_by_unlock := _make_quests_by_unlock()
static var _merchants := _index(MERCHANTS)
static var _goods := _index(GOODS)
static var _stats := _index(STATS)
static var _tags := _index(TAGS)
static var _statuses := _index(STATUSES)
static var _skill_modifiers := _index(SKILL_MODIFIERS)
## id тега → резонанс этого тега.
static var _synergies_by_tag := _make_synergies_by_tag()
## id тега → бит маски.
static var _tag_bits := _make_tag_bits()
## Бит флагов снимка врага → [цвет, приоритет] сильнейшего эффекта с этим битом (оттенок у клиентов).
static var _status_tints := _make_status_tints()
## id статуса → маска тегов его урона.
static var _status_masks := _make_status_masks()


## Все поиски возвращают null, если id нет: id приходят и по сети (spawn-данные, выбор карты).
static func enemy(id: StringName) -> EnemyData:
	return _enemies.get(id)


static func elite_affix(id: StringName) -> EliteAffixData:
	return _elite_affixes.get(id)


static func upgrade(id: StringName) -> UpgradeData:
	return _upgrades.get(id)


static func item_base(id: StringName) -> ItemBaseData:
	return _item_bases.get(id)


static func affix(id: StringName) -> AffixData:
	return _affixes.get(id)


static func unique_item(id: StringName) -> UniqueItemData:
	return _unique_items.get(id)


static func talent(id: StringName) -> TalentData:
	return _talents.get(id)


## Таланты героя в порядке показа: общие, затем классовые.
static func talents_for(hero: HeroData) -> Array[TalentData]:
	var result: Array[TalentData] = []
	for item: TalentData in TALENTS:
		if item.fits(hero):
			result.append(item)
	return result


static func hero(id: StringName) -> HeroData:
	return _heroes.get(id)


static func quest(id: StringName) -> QuestData:
	return _quests.get(id)


static func seal(id: StringName) -> SealData:
	return _seals.get(id)


static func interactable(id: StringName) -> InteractableData:
	return _interactables.get(id)


static func lore(id: StringName) -> LoreData:
	return _lore.get(id)


static func biome(id: StringName) -> BiomeData:
	return _biomes.get(id)


## Точки, что встают на месте placement с уровня глубины depth.
static func interactables_for(placement: StringName, depth: int) -> Array:
	return INTERACTABLES.filter(func(i: InteractableData) -> bool: return i.placement == placement and i.fits(depth))


## Задание, которое открывает класс или навык id; null — открыт с самого начала.
static func quest_for_unlock(id: StringName) -> QuestData:
	return _quests_by_unlock.get(id)


static func merchant(id: StringName) -> MerchantData:
	return _merchants.get(id)


static func goods(id: StringName) -> GoodsData:
	return _goods.get(id)


static func status(id: StringName) -> StatusEffectData:
	return _statuses.get(id)


static func skill_modifier(id: StringName) -> SkillModifier:
	return _skill_modifiers.get(id)


static func tag(id: StringName) -> TagDef:
	return _tags.get(id)


## Резонанс тега; null — у тега резонанса нет.
static func synergy_for_tag(tag_id: StringName) -> SynergyData:
	return _synergies_by_tag.get(tag_id)


## Описание характеристики. Для характеристики «по тегу» («might:fire») — описание базовой, если такой
## тег есть; иначе null.
static func stat_def(id: StringName) -> StatDef:
	var key := String(id)
	var colon := key.find(":")
	if colon < 0:
		return _stats.get(id)
	if not _tag_bits.has(StringName(key.substr(colon + 1))):
		return null
	return _stats.get(StringName(key.left(colon)))


## Тег характеристики «по тегу» («might:fire» → огонь); у обычной — null.
static func stat_tag(id: StringName) -> TagDef:
	var key := String(id)
	var colon := key.find(":")
	return null if colon < 0 else _tags.get(StringName(key.substr(colon + 1)))


## Бит тега в маске; 0 — тега нет.
static func tag_bit(id: StringName) -> int:
	return _tag_bits.get(id, 0)


static func tag_mask(ids: Array) -> int:
	var mask := 0
	for id: Variant in ids:
		mask |= tag_bit(StringName(str(id)))
	return mask


## Маска тегов урона статуса (горение — огонь).
static func status_mask(id: StringName) -> int:
	return _status_masks.get(id, 0)


## Теги маски в порядке каталога.
static func tags_in(mask: int) -> Array[TagDef]:
	var result: Array[TagDef] = []
	for item: TagDef in TAGS:
		if mask & tag_bit(item.id):
			result.append(item)
	return result


## Оттенок врага по флагам статусов из снимка (биты 1–7); null-цвет не бывает: нет эффектов — белый.
static func status_tint(flags: int) -> Color:
	var best := Color.WHITE
	var best_priority := -1
	for bit in range(1, 8):
		if flags & (1 << bit) and _status_tints.has(bit) and _status_tints[bit][1] > best_priority:
			best = _status_tints[bit][0]
			best_priority = _status_tints[bit][1]
	return best


static func wave_table_for(level_index: int) -> WaveTable:
	return RunPlan.biome(level_index).waves


## Базовый навык, который эволюционирует в evolution_id; null — это не эволюция.
static func evolution_base(evolution_id: StringName) -> SkillData:
	for item in UPGRADES:
		if item is SkillData and item.evolution != null and item.evolution.id == evolution_id:
			return item
	return null


# --- Сборка каталога ---

## Все ресурсы класса type из папки dir (без вложенных папок), по order и id.
static func _scan(dir: String, type: Script) -> Array:
	var found: Array = []
	var ids := {}
	for file in ResourceLoader.list_directory(dir):
		if file.ends_with("/") or not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var res := load(dir + file)
		if res == null or not is_instance_of(res, type):
			continue
		var id: StringName = res.get("id")
		if ids.has(id):
			push_error("DataRegistry: повтор id «%s» в %s — файл %s пропущен" % [id, dir, file])
			continue
		ids[id] = true
		found.append(res)
	found.sort_custom(_before)
	return found



## Два списка в один, по порядку каталога; повтор id — ошибка данных, остаётся первый.
static func _merge(first: Array, second: Array) -> Array:
	var result := first.duplicate()
	var ids := _index(first)
	for item: Resource in second:
		if ids.has(item.get("id")):
			push_error("DataRegistry: повтор id «%s» в разных папках" % item.get("id"))
			continue
		result.append(item)
	result.sort_custom(_before)
	return result


static func _before(a: Resource, b: Resource) -> bool:
	var order_a: Variant = a.get("order")
	var order_b: Variant = b.get("order")
	var oa := int(order_a) if order_a != null else 0
	var ob := int(order_b) if order_b != null else 0
	if oa != ob:
		return oa < ob
	return String(a.get("id")) < String(b.get("id"))


static func _index(list: Array) -> Dictionary:
	var result := {}
	for item: Resource in list:
		result[item.get("id")] = item
	return result


## Открытие → задание. Открыть можно героя или навык; стартовый навык героя закрыть нельзя — им герой
## начинает забег. Ошибка данных — в журнал, такое задание ничего не закрывает.
static func _make_quests_by_unlock() -> Dictionary:
	var starting := {}
	for item: HeroData in HEROES:
		starting[item.starting_weapon] = true
	var result := {}
	for item: QuestData in QUESTS:
		if item.unlock == &"":
			continue
		if not (_heroes.has(item.unlock) or _upgrades.has(item.unlock)) or starting.has(item.unlock) \
				or result.has(item.unlock) or not item.counter in QuestData.COUNTERS:
			push_error("DataRegistry: задание «%s» не может открывать «%s» (счётчик %s)" % [item.id, item.unlock, item.counter])
			continue
		result[item.unlock] = item
	return result


static func _make_tag_bits() -> Dictionary:
	var result := {}
	if TAGS.size() > MAX_TAGS:
		push_error("DataRegistry: тегов %d, в маску помещается %d" % [TAGS.size(), MAX_TAGS])
	for i in mini(TAGS.size(), MAX_TAGS):
		result[TAGS[i].id] = 1 << i
	return result


static func _make_synergies_by_tag() -> Dictionary:
	var result := {}
	for item: SynergyData in SYNERGIES:
		if result.has(item.tag):
			push_error("DataRegistry: у тега «%s» два резонанса — %s пропущен" % [item.tag, item.id])
			continue
		result[item.tag] = item
	return result


static func _make_status_masks() -> Dictionary:
	var result := {}
	for item: StatusEffectData in STATUSES:
		result[item.id] = tag_mask(item.tags)
	return result


static func _make_status_tints() -> Dictionary:
	var result := {}
	for item: StatusEffectData in STATUSES:
		var bit := item.visual_bit
		if bit > 0 and (not result.has(bit) or item.tint_priority > result[bit][1]):
			result[bit] = [item.color, item.tint_priority]
	return result
