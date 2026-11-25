class_name SkillsTab
extends ScrollContainer
## Вкладка «Навыки и умения» меню (шаг 11.7, как «Traits and Abilities» в Halls of Torment): класс героя с чертой,
## навыки (уровень, ступень эволюции, руны, описание), пассивки с итоговой прибавкой и резонансы тегов (сколько навыков с тегом,
## пороги и прибавки). Всё — из синхронизированных свойств героя (upgrade_levels, runes), работает и на клиенте.

const LABEL_COLOR := Color(0.72, 0.66, 0.54)
const VALUE_COLOR := Color(0.95, 0.9, 0.78)
const RUNE_COLOR := Color(0.55, 0.7, 1.0)

var player: Player
var _column: VBoxContainer


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 4)
	add_child(_column)


func refresh() -> void:
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	if player == null or not is_instance_valid(player):
		return
	var hero := player.hero
	_column.add_child(_header(tr(hero.name_key)))
	_column.add_child(_line(tr(hero.description_key), LABEL_COLOR, 9))

	_column.add_child(_header(tr("PAUSE_TAB_SKILLS_LIST")))
	var skills := false
	for id: StringName in player.upgrade_levels:
		var skill := DataRegistry.upgrade(id) as SkillData
		if skill == null or player.upgrade_levels[id] <= 0:
			continue
		skills = true
		var level: int = player.upgrade_levels[id]
		var title := "%s · %s" % [tr(skill.name_key), tr("UPGRADE_LEVEL").format({"level": level})]
		var stage := player.evolution_stage(id)
		if stage > 0:
			title += " · " + tr("SKILL_EVOLUTION_STAGE").format({"stage": UpgradePool.stage_name(stage),
					"max": UpgradePool.stage_name(DataRegistry.UPGRADE_RULES.evolution_stages)})
		_column.add_child(_entry(skill.icon_color, title, _rune_line(skill), tr(skill.description_key), skill.icon_name(),
				_rune_icons(skill)))
	if not skills:
		_column.add_child(_line(tr("RUN_STATS_NO_DATA"), LABEL_COLOR, 9))

	var passives: Array[PassiveData] = []
	for id: StringName in player.upgrade_levels:
		var passive := DataRegistry.upgrade(id) as PassiveData
		if passive != null and player.upgrade_levels[id] > 0:
			passives.append(passive)
	if not passives.is_empty():
		_column.add_child(_header(tr("PAUSE_TAB_PASSIVES")))
		for passive in passives:
			var level: int = player.upgrade_levels[passive.id]
			_column.add_child(_entry(passive.icon_color, "%s · %s" % [tr(passive.name_key), tr("UPGRADE_LEVEL").format({"level": level})],
					ItemRoller.stat_line(passive.stat, passive.per_level * level), tr(passive.description_key), passive.icon_name()))

	var resonances := Synergies.progress(player.upgrade_levels, player.runes).filter(func(entry: Array) -> bool:
		return entry[2] > 0)
	if not resonances.is_empty():
		_column.add_child(_header(tr("PAUSE_TAB_RESONANCES")))
		for entry: Array in resonances:
			var synergy: SynergyData = entry[0]
			var tag := DataRegistry.tag(synergy.tag)
			_column.add_child(_entry(tag.color if tag != null else LABEL_COLOR, Synergies.display_name(synergy),
					"", Synergies.tooltip(synergy, entry[2])))


func _rune_line(skill: SkillData) -> String:
	var names := PackedStringArray()
	for id: Variant in player.runes.get(skill.id, []):
		var rune := DataRegistry.skill_modifier(StringName(str(id)))
		if rune != null:
			names.append(tr(rune.name_key))
	return tr("CARD_RUNES").format({"list": ", ".join(names)}) if not names.is_empty() else ""


## Значки рун навыка по порядку гнёзд (шаг 11.26).
func _rune_icons(skill: SkillData) -> Array[StringName]:
	var icons: Array[StringName] = []
	for id: Variant in player.runes.get(skill.id, []):
		var rune := DataRegistry.skill_modifier(StringName(str(id)))
		if rune != null:
			icons.append(rune.icon_name())
	return icons


## Строка списка: значок (атлас ItemIcon, шаг 11.18; нет — квадрат цвета), название, строка прибавки или рун
## (перед ней — значки рун, шаг 11.26), описание.
func _entry(color: Color, title: String, accent: String, description: String, icon_name: StringName = &"",
		accent_icons: Array[StringName] = []) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var texture := ItemIcon.texture(icon_name) if icon_name != &"" else null
	if texture != null:
		row.add_child(_picture(texture, 26.0))
	else:
		var icon := PanelContainer.new()
		icon.theme_type_variation = &"SlotPanel"
		icon.custom_minimum_size = Vector2(20, 20)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var swatch := ColorRect.new()
		swatch.color = color
		icon.add_child(swatch)
		row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(_line(title, VALUE_COLOR, 10))
	if accent != "":
		var accent_row := HBoxContainer.new()
		accent_row.add_theme_constant_override("separation", 2)
		for icon in accent_icons:
			var rune_texture := ItemIcon.texture(icon)
			if rune_texture != null:
				accent_row.add_child(_picture(rune_texture, 12.0))
		var accent_label := _line(accent, RUNE_COLOR, 8)
		accent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		accent_row.add_child(accent_label)
		text.add_child(accent_row)
	if description != "":
		text.add_child(_line(description, LABEL_COLOR, 8))
	row.add_child(text)
	return row


func _picture(texture: Texture2D, side: float) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.custom_minimum_size = Vector2(side, side)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	picture.texture_filter = ItemIcon.FILTER
	return picture


func _header(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HeaderLabel"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	return label


func _line(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # текст уже переведён через tr()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
