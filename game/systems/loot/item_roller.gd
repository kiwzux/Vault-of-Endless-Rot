class_name ItemRoller
extends RefCounted
## Предметы в стиле Diablo (CR-07, шаг 7): редкость, встроенная характеристика базы и случайные аффиксы.
## Предмет — словарь из простых типов, чтобы передаваться по сети и в spawn-данных:
## {"base": StringName, "rarity": int, "unique": StringName, "affixes": Array, "curse": StringName,
##  "stats": {stat: value}}.
## stats уже посчитаны при выпадении — подобранный предмет навсегда прибавляет их к характеристикам героя
## (17.10.2026: предметы копятся, сумки нет — Player.receive_item); поэтому значения — LootTable.stack_power от прежних.
##
## Шаг 7: пять редкостей — обычный, магический, редкий, легендарный, проклятый.
## - Аффиксы — префиксы и суффиксы из пулов по слоту базы и уровню глубины (AffixData.fits): у магического
##   1–2 (не больше одного каждого вида), у редкого 3–4 (не больше двух каждого вида).
## - Легендарный — UniqueItemData: фиксированные характеристики и легендарная руна навыков (Player.skill_modifiers).
## - Проклятый — cursed_affixes аффиксов, каждый в cursed_power раз сильнее, и одно проклятие (curse) —
##   штраф к характеристике, которой нет среди бонусов. Штраф копится вместе с бонусами — проклятый предмет риск.

## Новые редкости — только в конец: число уходит в spawn-данные по сети.
enum Rarity { NORMAL, MAGIC, RARE, LEGENDARY, CURSED }

const RARITY_COLORS: Array[Color] = [
	Color(0.92, 0.9, 0.85), Color(0.4, 0.55, 1.0), Color(1.0, 0.85, 0.3), Color(1.0, 0.55, 0.15), Color(0.85, 0.2, 0.3),
]
const RARITY_KEYS: PackedStringArray = ["RARITY_NORMAL", "RARITY_MAGIC", "RARITY_RARE", "RARITY_LEGENDARY", "RARITY_CURSED"]
## Сколько аффиксов у редкости: [мин, макс] и не больше скольких каждого вида (префикс, суффикс).
const AFFIX_COUNT := {Rarity.NORMAL: [0, 0], Rarity.MAGIC: [1, 2], Rarity.RARE: [3, 4]}
const AFFIX_PER_KIND := {Rarity.MAGIC: 1, Rarity.RARE: 2, Rarity.CURSED: 2}
## Цвет строки проклятия в подсказке.
const CURSE_COLOR := Color(0.95, 0.35, 0.35)
## Подписи и формат характеристик — StatDef (data/stats/); на предмете бывают только те, у кого on_items.
## Предел значения одной характеристики на предмете: защищает от испорченных данных из сети.
const MAX_STAT_VALUE := 1000.0


## Редкость по таблице весов: с глубиной магические и выше выпадают чаще; ниже min_rarity — не выпадает.
## Проклятый не «выше» легендарного: гарантия легендарного (финальный босс) проклятым не оборачивается.
## find_mult — шанс магических и лучших сверх глубины (Скверна забега, шаг 12.3; RunConfig.magic_find_mult).
static func roll_rarity(rng: RandomNumberGenerator, table: LootTable, depth: int, min_rarity: int,
		find_mult: float = 1.0) -> int:
	var weights := table.rarity_weights.duplicate()
	for r in weights.size():
		if r < min_rarity or (r == Rarity.CURSED and min_rarity > Rarity.RARE):
			weights[r] = 0.0
		elif r > Rarity.NORMAL:
			weights[r] *= (1.0 + table.magic_find_per_level * depth) * find_mult
	return rng.rand_weighted(weights)


static func roll(rng: RandomNumberGenerator, rarity: int, depth: int, table: LootTable) -> Dictionary:
	if rarity == Rarity.LEGENDARY:
		var unique: UniqueItemData = DataRegistry.UNIQUE_ITEMS[rng.randi_range(0, DataRegistry.UNIQUE_ITEMS.size() - 1)]
		var fixed := {}
		for stat in unique.stats:
			_add(fixed, StringName(str(stat)), float(unique.stats[stat]) * table.stack_power)
		return {"base": unique.base.id, "rarity": rarity, "unique": unique.id, "affixes": [], "curse": &"",
				"stats": fixed}

	var power := (1.0 + table.power_per_level * depth) * table.stack_power
	var base: ItemBaseData = DataRegistry.ITEM_BASES[rng.randi_range(0, DataRegistry.ITEM_BASES.size() - 1)]
	var stats := {}
	_add(stats, base.implicit_stat, rng.randf_range(base.implicit_min, base.implicit_max) * power)
	var count := table.cursed_affixes if rarity == Rarity.CURSED else rng.randi_range(AFFIX_COUNT[rarity][0], AFFIX_COUNT[rarity][1])
	var boost := table.cursed_power if rarity == Rarity.CURSED else 1.0
	var affixes: Array = []
	var pools := {
		AffixData.Kind.PREFIX: _pool(base, depth, AffixData.Kind.PREFIX),
		AffixData.Kind.SUFFIX: _pool(base, depth, AffixData.Kind.SUFFIX),
	}
	var left := {AffixData.Kind.PREFIX: AFFIX_PER_KIND.get(rarity, 0), AffixData.Kind.SUFFIX: AFFIX_PER_KIND.get(rarity, 0)}
	for i in count:
		var kinds := pools.keys().filter(func(k: int) -> bool: return left[k] > 0 and not pools[k].is_empty())
		if kinds.is_empty():
			break
		var kind: int = kinds[rng.randi_range(0, kinds.size() - 1)]
		var pool: Array = pools[kind]
		var affix: AffixData = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		left[kind] -= 1
		affixes.append(affix.id)
		_add(stats, affix.stat, rng.randf_range(affix.min_value, affix.max_value) * power * boost)
	var curse: StringName = &""
	if rarity == Rarity.CURSED:
		var curses := _pool(base, depth, AffixData.Kind.CURSE).filter(func(a: AffixData) -> bool: return not stats.has(a.stat))
		if not curses.is_empty():
			var picked: AffixData = curses[rng.randi_range(0, curses.size() - 1)]
			curse = picked.id
			_add(stats, picked.stat, rng.randf_range(picked.min_value, picked.max_value) * power)
	return {"base": base.id, "rarity": rarity, "unique": &"", "affixes": affixes, "curse": curse, "stats": stats}


## Аффиксы вида kind, подходящие базе и глубине.
static func _pool(base: ItemBaseData, depth: int, kind: AffixData.Kind) -> Array:
	return DataRegistry.AFFIXES.filter(func(a: AffixData) -> bool: return a.kind == kind and a.fits(base, depth))


## Проверка предмета, пришедшего от другого участника сессии или из spawn-данных.
static func is_valid(item: Variant) -> bool:
	if not (item is Dictionary):
		return false
	var rarity: Variant = item.get("rarity")
	if not (rarity is int) or rarity < Rarity.NORMAL or rarity > Rarity.CURSED:
		return false
	if DataRegistry.item_base(item.get("base", &"")) == null:
		return false
	var curse: Variant = item.get("curse", &"")
	if not (curse is StringName or curse is String):
		return false
	if curse != &"" and (DataRegistry.affix(StringName(curse)) == null or DataRegistry.affix(StringName(curse)).kind != AffixData.Kind.CURSE):
		return false
	var stats: Variant = item.get("stats")
	if not (stats is Dictionary):
		return false
	for stat in stats:
		var value: Variant = stats[stat]
		var def := DataRegistry.stat_def(StringName(str(stat)))
		if def == null or not def.on_items or not (value is float or value is int):
			return false
		if is_nan(float(value)) or absf(float(value)) > MAX_STAT_VALUE:
			return false
	return true


static func slot_of(item: Dictionary) -> int:
	return DataRegistry.item_base(item["base"]).slot


## Легендарка предмета; null — предмет не легендарный.
static func legendary(item: Dictionary) -> UniqueItemData:
	var id: StringName = StringName(str(item.get("unique", "")))
	return DataRegistry.unique_item(id) if id != &"" else null


## Значок предмета (шаг 11.15): у легендарки — свой, иначе вариант базы по значению встроенной характеристики —
## оно случайно при выпадении и одинаково у всех участников, поэтому значок в словарь предмета не добавляется.
## Пусто — у базы нет значков (ItemIcon нарисует силуэт слота).
static func icon_of(item: Dictionary) -> StringName:
	var unique := legendary(item)
	if unique != null and unique.icon != &"":
		return unique.icon
	var base := DataRegistry.item_base(item.get("base", &""))
	if base == null or base.icons.is_empty():
		return &""
	var value := float(item.get("stats", {}).get(base.implicit_stat, 0.0))
	return StringName(base.icons[absi(hash(snappedf(value, 0.0001))) % base.icons.size()])


## Имя для интерфейса (уже переведённое): легендарный — своё имя, иначе [префикс] база [суффикс] — первый
## аффикс каждого вида; префикс согласуется с родом базы.
static func display_name(item: Dictionary) -> String:
	var unique := legendary(item)
	if unique != null:
		return TranslationServer.translate(unique.name_key)
	var base := DataRegistry.item_base(item["base"])
	var prefix := ""
	var suffix := ""
	for id in item.get("affixes", []):
		var affix := DataRegistry.affix(StringName(str(id)))
		if affix == null:
			continue
		if affix.kind == AffixData.Kind.PREFIX and prefix == "":
			prefix = TranslationServer.translate(affix.display_key(base))
		elif affix.kind == AffixData.Kind.SUFFIX and suffix == "":
			suffix = TranslationServer.translate(affix.display_key(base))
	var text := TranslationServer.translate(base.name_key)
	if prefix != "":
		text = "%s %s" % [prefix, text.to_lower()] if TranslationServer.get_locale().begins_with("ru") else "%s %s" % [prefix, text]
	if suffix != "":
		text += " " + suffix
	return text


## Строки характеристик без проклятия (его показывает curse_line).
static func stat_lines(item: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var stats: Dictionary = item.get("stats", {})
	var cursed_stat := _curse_stat(item)
	for stat: StringName in stats:
		if stat == cursed_stat:
			continue
		var line := stat_line(stat, stats[stat])
		if line != "":
			lines.append(line)
	return lines


## «Проклятие «Иссушение»: −20 к здоровью»; пусто — предмет не проклят.
static func curse_line(item: Dictionary) -> String:
	var stat := _curse_stat(item)
	if stat == &"":
		return ""
	var curse := DataRegistry.affix(StringName(str(item["curse"])))
	return TranslationServer.translate("ITEM_CURSE_LINE").format({
		"name": TranslationServer.translate(curse.name_key), "line": stat_line(stat, item["stats"].get(stat, 0.0)),
	})


## «Легендарная руна: огненные навыки…»; пусто — у предмета её нет.
static func legendary_line(item: Dictionary) -> String:
	var unique := legendary(item)
	if unique == null or unique.modifier == null:
		return ""
	return TranslationServer.translate("ITEM_LEGEND_LINE").format(
			{"text": TranslationServer.translate(unique.modifier.description_key)})


## Бонусы предмета: характеристики и легендарная руна (без проклятия — его окна показывают отдельной
## строкой цвета CURSE_COLOR).
static func bonus_lines(item: Dictionary) -> PackedStringArray:
	var lines := stat_lines(item)
	var legend := legendary_line(item)
	if legend != "":
		lines.append(legend)
	return lines


## Весь текст подсказки одним столбцом: бонусы и проклятие (сравнение с надетым, панель сборки).
static func tooltip_lines(item: Dictionary) -> PackedStringArray:
	var lines := bonus_lines(item)
	var curse := curse_line(item)
	if curse != "":
		lines.append(curse)
	return lines


static func _curse_stat(item: Dictionary) -> StringName:
	var id: StringName = StringName(str(item.get("curse", "")))
	var curse := DataRegistry.affix(id) if id != &"" else null
	return curse.stat if curse != null else &""


## Переведённая строка характеристики («+12% урона»; «по тегу» — «+12% урона (Огонь)»); пустая —
## характеристика без StatDef.
static func stat_line(stat: StringName, value: float) -> String:
	var def := DataRegistry.stat_def(stat)
	if def == null:
		return ""
	if def.whole:
		value = floorf(value) if value >= 0.0 else ceilf(value)
	var shown := _number(absf(value) * 100.0 if def.is_percent() else absf(value))
	var template := TranslationServer.translate(def.line_key)
	if value < 0.0:  # штраф проклятия: «−20 к здоровью», а не «+-20»
		template = template.replace("+{value}", "−{value}")
	var line := template.format({"value": shown})
	var tag := DataRegistry.stat_tag(stat)
	if tag != null:
		line = TranslationServer.translate("STAT_SCOPED").format({"line": line, "tag": TranslationServer.translate(tag.name_key)})
	return line


## Число без лишних нулей: 7 → «7», 0.3 → «0.3», 0.12 → «0.12».
static func _number(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")


## Ценность для куклы: обычный < магический < редкий = проклятый < легендарный (у него руна навыков).
static func rank(item: Dictionary) -> int:
	match int(item.get("rarity", 0)):
		Rarity.LEGENDARY:
			return 4
		Rarity.RARE, Rarity.CURSED:
			return 2
		Rarity.MAGIC:
			return 1
	return 0


static func rarity_color(item: Dictionary) -> Color:
	return RARITY_COLORS[clampi(int(item.get("rarity", 0)), 0, RARITY_COLORS.size() - 1)]


static func _add(stats: Dictionary, stat: StringName, value: float) -> void:
	var def := DataRegistry.stat_def(stat)
	var rounded := snappedf(value, 0.01) if def == null or def.is_percent() else snappedf(value, 0.1)
	stats[stat] = stats.get(stat, 0.0) + rounded
