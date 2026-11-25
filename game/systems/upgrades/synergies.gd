class_name Synergies
extends RefCounted
## Резонансы героя (шаг 4, SynergyData): сколько у героя навыков с каждым тегом и какие пороги
## достигнуты. Чистые функции от уровней улучшений и рун забега. Оба словаря хост синхронизирует всем
## (Player, ФТ-14), поэтому характеристики резонансов хост считает в Player.collect_stats, а клиент
## по тем же данным — HUD, карты левел-апа и лист героя; результат совпадает.


## Маска тегов навыка вместе с тегами его рун (встроенных и забега): Руна огня делает навык огненным.
## Подходит ли руна, решается по собственным тегам навыка — как в SkillStats.compute.
static func skill_mask(skill: SkillData, rune_ids: Array) -> int:
	var base := DataRegistry.tag_mask(skill.tags)
	var kind := skill.action.kind() if skill.action != null else &""
	var mask := base
	var mods: Array = skill.modifiers.duplicate()
	for id: Variant in rune_ids:
		mods.append(DataRegistry.skill_modifier(StringName(str(id))))
	for mod: SkillModifier in mods:
		if mod != null and SkillStats.fits(mod, base, kind):
			mask |= DataRegistry.tag_mask(mod.add_tags)
	return mask


## id тега → сколько у героя навыков с этим тегом (levels — Player.upgrade_levels, runes — Player.runes).
static func counts(levels: Dictionary, runes: Dictionary) -> Dictionary:
	var result := {}
	for id: Variant in levels:
		var skill := DataRegistry.upgrade(StringName(str(id))) as SkillData
		if skill == null or int(levels[id]) <= 0:
			continue
		for tag: TagDef in DataRegistry.tags_in(skill_mask(skill, runes.get(skill.id, []))):
			result[tag.id] = int(result.get(tag.id, 0)) + 1
	return result


## Достигнутые резонансы в порядке каталога: [[SynergyData, порог, навыков с тегом], …].
static func active(levels: Dictionary, runes: Dictionary) -> Array:
	return _with_counts(counts(levels, runes), true)


## Все резонансы, у которых есть хотя бы один навык с тегом (для HUD): [[SynergyData, порог, навыков], …].
static func progress(levels: Dictionary, runes: Dictionary) -> Array:
	return _with_counts(counts(levels, runes), false)


## Сумма характеристик достигнутых резонансов: {характеристика: значение}.
static func stats(levels: Dictionary, runes: Dictionary) -> Dictionary:
	var result := {}
	for entry: Array in active(levels, runes):
		var bonus := (entry[0] as SynergyData).stats_for(entry[1])
		for stat: Variant in bonus:
			var key := StringName(str(stat))
			result[key] = float(result.get(key, 0.0)) + float(bonus[stat])
	return result


## «Резонанс: Огонь».
static func display_name(synergy: SynergyData) -> String:
	return TranslationServer.translate("SYNERGY_NAME").format({"tag": tag_name(synergy)})


## Переведённое имя тега резонанса: «Огонь».
static func tag_name(synergy: SynergyData) -> String:
	var tag := DataRegistry.tag(synergy.tag)
	if tag == null:
		return String(synergy.tag)
	return TranslationServer.translate(tag.name_key)


## Строки характеристик порога tier: «+18% урона (Огонь)», «+5% к области».
static func stat_lines(synergy: SynergyData, tier: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var bonus := synergy.stats_for(tier)
	for stat: Variant in bonus:
		var line := ItemRoller.stat_line(StringName(str(stat)), float(bonus[stat]))
		if line != "":
			lines.append(line)
	return lines


## Подсказка резонанса: название, число навыков, действующий порог и следующий.
static func tooltip(synergy: SynergyData, count: int) -> String:
	var tier := synergy.tier_for(count)
	var lines := PackedStringArray([display_name(synergy) + " · " + TranslationServer.translate("SYNERGY_COUNT").format({"count": count})])
	if tier > 0:
		lines.append_array(stat_lines(synergy, tier))
	var next := synergy.next_threshold(count)
	if next > 0:
		lines.append(TranslationServer.translate("SYNERGY_NEXT").format({"count": next}))
		for line in stat_lines(synergy, synergy.tier_for(next)):
			lines.append("  " + line)
	return "\n".join(lines)


## Как карта изменит резонансы: [[SynergyData, было навыков, станет], …] для тегов, которых станет больше.
## new_mask — теги, которые получит навык skill_id (новый навык или руна, добавляющая тег).
static func gains(levels: Dictionary, runes: Dictionary, skill_id: StringName, new_mask: int) -> Array:
	var result := []
	var before := counts(levels, runes)
	var skill := DataRegistry.upgrade(skill_id) as SkillData
	var had := 0
	if skill != null and int(levels.get(skill_id, 0)) > 0:
		had = skill_mask(skill, runes.get(skill_id, []))
	for tag: TagDef in DataRegistry.tags_in(new_mask & ~had):
		var synergy := DataRegistry.synergy_for_tag(tag.id)
		if synergy != null:
			var count: int = before.get(tag.id, 0)
			result.append([synergy, count, count + 1])
	return result


static func _with_counts(by_tag: Dictionary, reached_only: bool) -> Array:
	var result := []
	for synergy: SynergyData in DataRegistry.SYNERGIES:
		var count: int = by_tag.get(synergy.tag, 0)
		var tier := synergy.tier_for(count)
		if count > 0 and (tier > 0 or not reached_only):
			result.append([synergy, tier, count])
	return result
