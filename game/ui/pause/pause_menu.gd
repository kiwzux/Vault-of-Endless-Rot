class_name PauseMenu
extends CanvasLayer
## Меню забега в духе Halls of Torment (шаг 11.7): вкладки «Герой» (экипировка, сумка, характеристики, урон
## навыков — CharacterTab; бывший инвентарь CR-07), «Навыки и умения» (SkillsTab), «Настройки» (язык, громкость,
## цифры урона, режим экрана, размер окна, фильтр лута) и «Выход» (сводка забега, управление, выход в Убежище
## с подтверждением — души сохраняются). Меню закрывает игровое поле между боковыми панелями HUD; кнопка
## «Меню» справа становится «Продолжить».
##
## Открывается Esc (P, Start), клавишей I (Tab) — сразу на «Героя» — и кнопкой «Меню» HUD. Повторное нажатие
## закрывает; I на другой вкладке переключает на «Героя». В одиночной игре мир стоит (World.request_pause); в сети
## остальные игроки продолжают бой — об этом предупреждает надпись. Окно сворачивается — одиночная игра сама
## встаёт на паузу. Поверх выбора карт левел-апа меню открывается, выбор остаётся; поверх окна торговца — нет.

enum Tab { HERO, SKILLS, SETTINGS, QUIT }

const PAUSE_REASON := &"pause_menu"

## Вкладки «Герой» и «Навыки» (строятся кодом).
var character: CharacterTab
var skills: SkillsTab
## Окно потеряло фокус — пауза (одиночная игра). Проверки механик в окне выключают: иначе переключение на
## другое окно, пока они идут, ставит мир на паузу, и падают все проверки после этого.
var pause_on_focus_out := true

var _world: World
var _tab := Tab.HERO
## Фокус, который был до открытия меню (например, карта левел-апа): вернётся после закрытия.
var _restore_focus: Control

@onready var stats: Label = %Stats
@onready var net_note: Label = %NetNote
@onready var pages: PanelContainer = %Pages
@onready var settings_box: Control = %SettingsBox
@onready var quit_box: Control = %QuitBox
@onready var language_option: OptionButton = %LanguageOption
@onready var volume_slider: HSlider = %VolumeSlider
@onready var damage_numbers_toggle: CheckButton = %DamageNumbersToggle
@onready var tab_buttons: Array[Button] = [%TabHero, %TabSkills, %TabSettings, %TabQuit]


func _ready() -> void:
	hide()
	_world = World.of(self)
	character = CharacterTab.new()
	character.world = _world
	character.hide()
	pages.add_child(character)
	skills = SkillsTab.new()
	skills.hide()
	pages.add_child(skills)
	var group := ButtonGroup.new()
	for i in tab_buttons.size():
		tab_buttons[i].button_group = group
		tab_buttons[i].pressed.connect(show_tab.bind(i))
	%Resume.pressed.connect(close)
	%ConfirmYesButton.pressed.connect(func() -> void: _world.leave_run())
	Events.inventory_changed.connect(func(peer_id: int) -> void:
		if visible and _tab == Tab.HERO and peer_id == multiplayer.get_unique_id():
			character.refresh())

	for i in Settings.LOCALES.size():
		language_option.add_item("LANG_" + Settings.LOCALES[i].to_upper(), i)
	language_option.select(Settings.LOCALES.find(Settings.locale))
	language_option.item_selected.connect(func(i: int) -> void:
		Settings.set_locale(Settings.LOCALES[i])
		_update_stats())
	volume_slider.value = Settings.master_volume
	volume_slider.value_changed.connect(Settings.set_master_volume)
	DisplayOptions.bind_audio(volume_slider)
	damage_numbers_toggle.button_pressed = Settings.show_damage_numbers
	damage_numbers_toggle.toggled.connect(Settings.set_show_damage_numbers)
	DisplayOptions.bind(%DisplayModeOption, %WindowSizeOption)
	DisplayOptions.bind_loot_filter(%LootFilterOption)
	DisplayOptions.bind_graphics(self)


func _unhandled_input(event: InputEvent) -> void:
	var inventory := event.is_action_pressed(&"inventory")
	if not (inventory or event.is_action_pressed(&"pause") or (visible and event.is_action_pressed(&"ui_cancel"))):
		return
	if not visible:
		if can_open():
			get_viewport().set_input_as_handled()
			open(Tab.HERO)
		return
	get_viewport().set_input_as_handled()
	if inventory and _tab != Tab.HERO:
		show_tab(Tab.HERO)
	else:
		close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_out and can_open() and multiplayer.get_peers().is_empty():
		open(Tab.HERO)


func _process(_delta: float) -> void:
	if visible and _tab == Tab.HERO:
		character.refresh_live()


## Забег идёт: не конец забега и не окно торговца (оно закрывается само).
func can_open() -> bool:
	if visible or _world == null or _world.flow.phase in [LevelFlow.Phase.DEFEAT, LevelFlow.Phase.VICTORY]:
		return false
	return not _world.is_ui_open(&"shop")


func open(tab: Tab = Tab.HERO) -> void:
	_restore_focus = get_viewport().gui_get_focus_owner()
	character.player = _world.local_player()
	skills.player = character.player
	net_note.visible = not multiplayer.get_peers().is_empty()
	show()
	_world.request_pause(PAUSE_REASON, true)
	show_tab(tab)


func close() -> void:
	hide()
	Settings.save_settings()
	_world.request_pause(PAUSE_REASON, false)
	if is_instance_valid(_restore_focus) and _restore_focus.is_visible_in_tree():
		_restore_focus.grab_focus()
	_restore_focus = null


func current_tab() -> Tab:
	return _tab


func show_tab(tab: Tab) -> void:
	_tab = tab
	var shown: Array[Control] = [character, skills, settings_box, quit_box]
	for i in shown.size():
		shown[i].visible = i == tab
		tab_buttons[i].set_pressed_no_signal(i == tab)
	match tab:
		Tab.HERO:
			character.refresh()
		Tab.SKILLS:
			skills.refresh()
		Tab.QUIT:
			_update_stats()
	var first: Control = tab_buttons[tab]
	# Отложенно: кнопка становится видимой только после раскладки; меню могли уже закрыть.
	(func() -> void:
		if first.is_visible_in_tree():
			first.grab_focus()).call_deferred()


func _update_stats() -> void:
	var index := GameState.level_index
	var place := tr("BANNER_FINAL_LAIR") if RunPlan.is_final(index) else tr(RunPlan.biome_key(index))
	var seconds := ceili(GameState.level_time_left)
	var text := tr("PAUSE_STATS_PLACE").format({"place": place, "depth": index + 1})
	if not RunPlan.is_final(index):
		text += "\n" + tr("PAUSE_STATS_TIME").format({"time": "%d:%02d" % [floori(seconds / 60.0), seconds % 60]})
	var biome := RunPlan.biome(index)
	if biome.hazard_name_key != "":  # шаг 9: чем опасны клетки биома
		text += "\n" + tr("PAUSE_STATS_HAZARD").format({"name": tr(biome.hazard_name_key), "effect": tr(biome.hazard_desc_key)})
	var player := _world.local_player()
	if player != null:
		text += "\n" + tr("PAUSE_STATS_HERO").format({
			"hero": tr(player.hero.name_key), "level": player.level, "kills": player.kills, "gold": player.gold,
		})
	stats.text = text
