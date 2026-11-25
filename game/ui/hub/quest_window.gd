class_name QuestWindow
extends HubWindow
## Доска заданий (шаг 10.2–10.3): цели «Летописи» с прогрессом и наградой. Выполненное задание отдаёт
## награду кнопкой — души и открытие класса или навыка (MetaProfile.claim).


func build() -> void:
	set_title(tr("HUB_BOARD_TITLE"))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	body.add_child(HubWindow.make_scroll(rows))
	for quest: QuestData in DataRegistry.QUESTS:
		rows.add_child(_quest_row(quest))


func _quest_row(quest: QuestData) -> HBoxContainer:
	var done := MetaProfile.quest_done(quest)
	var claimed := MetaProfile.quest_claimed(quest)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	info.add_child(HubWindow.make_label(tr(quest.name_key), 10, GOOD_COLOR if claimed else TITLE_COLOR))
	var goal := tr(quest.description_key).format({"target": quest.target})
	var progress := tr("HUB_QUEST_PROGRESS").format({"value": MetaProfile.quest_progress(quest), "target": quest.target})
	info.add_child(HubWindow.make_label("%s · %s" % [goal, progress], 8, TEXT_COLOR))
	info.add_child(HubWindow.make_label(reward_text(quest), 8, DIM_COLOR))
	row.add_child(info)
	var button := Button.new()
	button.custom_minimum_size = Vector2(84, 0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 9)
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.text = tr("HUB_QUEST_CLAIMED") if claimed else tr("HUB_QUEST_CLAIM")
	button.disabled = claimed or not done
	button.pressed.connect(_claim.bind(quest))
	row.add_child(button)
	return row


## «Награда: Пиромант, +100 душ».
static func reward_text(quest: QuestData) -> String:
	var parts := PackedStringArray()
	if quest.unlock != &"":
		var hero := DataRegistry.hero(quest.unlock)
		var skill := DataRegistry.upgrade(quest.unlock)
		if hero != null:
			parts.append(HubWindow.tr_static("HUB_REWARD_HERO").format({"name": HubWindow.tr_static(hero.name_key)}))
		elif skill != null:
			parts.append(HubWindow.tr_static("HUB_REWARD_SKILL").format({"name": HubWindow.tr_static(skill.name_key)}))
	if quest.reward_souls > 0:
		parts.append(HubWindow.tr_static("HUB_REWARD_SOULS").format({"souls": quest.reward_souls}))
	return HubWindow.tr_static("HUB_REWARD_LINE").format({"reward": ", ".join(parts)})


func _claim(quest: QuestData) -> void:
	if MetaProfile.claim(quest):
		sanctuary.on_quest_claimed(quest)
		refresh.call_deferred()
