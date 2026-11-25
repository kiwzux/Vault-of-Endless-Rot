extends Control
## Настройки: язык переключается сразу, без перезапуска (НФТ-08); режим экрана и размер окна.

@onready var language_option: OptionButton = %LanguageOption
@onready var volume_slider: HSlider = %VolumeSlider


func _ready() -> void:
	for i in Settings.LOCALES.size():
		language_option.add_item("LANG_" + Settings.LOCALES[i].to_upper(), i)
	language_option.select(Settings.LOCALES.find(Settings.locale))
	language_option.item_selected.connect(func(i: int) -> void: Settings.set_locale(Settings.LOCALES[i]))

	volume_slider.value = Settings.master_volume
	volume_slider.value_changed.connect(Settings.set_master_volume)
	DisplayOptions.bind_audio(volume_slider)

	%DamageNumbersToggle.button_pressed = Settings.show_damage_numbers
	%DamageNumbersToggle.toggled.connect(Settings.set_show_damage_numbers)
	DisplayOptions.bind(%DisplayModeOption, %WindowSizeOption)
	DisplayOptions.bind_loot_filter(%LootFilterOption)
	DisplayOptions.bind_graphics(self)

	%BackButton.pressed.connect(_on_back_pressed)
	language_option.grab_focus()


func _on_back_pressed() -> void:
	Settings.save_settings()
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)
