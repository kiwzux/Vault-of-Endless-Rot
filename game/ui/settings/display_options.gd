class_name DisplayOptions
extends RefCounted
## Строки «Режим экрана» и «Размер окна» для экранов настроек (главное меню и пауза): заполняет списки,
## связывает их с Settings и обновляет, если режим сменили клавишей F11 или Alt+Enter.
## Размер окна недоступен во весь экран.


static func bind(mode_option: OptionButton, size_option: OptionButton) -> void:
	for i in Settings.DISPLAY_MODE_KEYS.size():
		mode_option.add_item(Settings.DISPLAY_MODE_KEYS[i], i)
	for size in Settings.window_sizes():  # id — номер размера в Settings.WINDOW_SIZES
		size_option.add_item(Settings.window_size_text(size), Settings.WINDOW_SIZES.find(size))  # «1280 × 720» — не ключ перевода
	mode_option.item_selected.connect(func(index: int) -> void: Settings.set_display_mode(mode_option.get_item_id(index)))
	size_option.item_selected.connect(func(index: int) -> void:
		Settings.set_window_size(Settings.WINDOW_SIZES[size_option.get_item_id(index)]))
	var refresh := func() -> void: _refresh(mode_option, size_option)
	Settings.display_changed.connect(refresh)
	mode_option.tree_exiting.connect(func() -> void: Settings.display_changed.disconnect(refresh))
	_refresh(mode_option, size_option)


## Строка «Фильтр лута» (шаг 7): всё / без обычных / только редкие и выше.
static func bind_loot_filter(option: OptionButton) -> void:
	for i in Settings.LOOT_FILTER_KEYS.size():
		option.add_item(Settings.LOOT_FILTER_KEYS[i], i)
	option.select(Settings.loot_filter)
	option.item_selected.connect(func(index: int) -> void: Settings.set_loot_filter(option.get_item_id(index)))


## Настройки графики (техзадание, раздел 8): «Качество эффектов» (шаг 11.8: низкое — без карты света / среднее /
## высокое), «Предел FPS», «Тряска камеры», «Стоп-кадр при ударе» (шаг 11.9), «Пост-эффекты» (шаг 11.10).
## Узлы ищутся по уникальным именам в экране настроек screen.
static func bind_graphics(screen: Node) -> void:
	var quality: OptionButton = screen.get_node("%QualityOption")
	for i in Settings.QUALITY_KEYS.size():
		quality.add_item(Settings.QUALITY_KEYS[i], i)
	quality.select(Settings.effects_quality)
	quality.item_selected.connect(func(index: int) -> void: Settings.set_effects_quality(quality.get_item_id(index)))
	var fps: OptionButton = screen.get_node("%FpsOption")
	for limit in Settings.FPS_LIMITS:
		fps.add_item("FPS_UNLIMITED" if limit == 0 else str(limit), limit)  # «60» — не ключ, останется как есть
	fps.select(fps.get_item_index(Settings.fps_limit))
	fps.item_selected.connect(func(index: int) -> void: Settings.set_fps_limit(fps.get_item_id(index)))
	for toggle: Array in [["%ShakeToggle", Settings.screen_shake, Settings.set_screen_shake],
			["%HitStopToggle", Settings.hit_stop, Settings.set_hit_stop],
			["%PostEffectsToggle", Settings.post_effects, Settings.set_post_effects]]:
		var button: CheckButton = screen.get_node(toggle[0])
		button.button_pressed = toggle[1]
		button.toggled.connect(toggle[2])


## Ползунки «Музыка» и «Звуки» (шаг 11.13) — сразу под общей громкостью, в той же сетке: в главном меню и в меню
## забега одинаково, без правки сцен.
static func bind_audio(volume_slider: HSlider) -> void:
	var grid := volume_slider.get_parent()
	var at := volume_slider.get_index() + 1
	for row: Array in [["SETTINGS_MUSIC", Settings.music_volume, Settings.set_music_volume],
			["SETTINGS_SFX", Settings.sfx_volume, Settings.set_sfx_volume]]:
		var label := Label.new()
		label.text = row[0]
		var slider := volume_slider.duplicate() as HSlider
		slider.unique_name_in_owner = false
		slider.value = row[1]
		slider.value_changed.connect(row[2])
		grid.add_child(label)
		grid.move_child(label, at)
		grid.add_child(slider)
		grid.move_child(slider, at + 1)
		at += 2


static func _refresh(mode_option: OptionButton, size_option: OptionButton) -> void:
	mode_option.select(mode_option.get_item_index(Settings.display_mode))
	# Сохранённый размер не влезает на этот экран — показан тот, что встал: самый крупный из влезающих.
	size_option.select(size_option.get_item_index(Settings.WINDOW_SIZES.find(Settings.fitted_window_size())))
	size_option.disabled = Settings.display_mode == Settings.DisplayMode.FULLSCREEN
