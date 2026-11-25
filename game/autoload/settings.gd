extends Node
## Настройки игрока: язык интерфейса (НФТ-08), громкость, цифры урона, экран, качество эффектов, раскладка по умолчанию.
## Экран: в окне или во весь экран (F11 или Alt+Enter переключают в любой момент); размер окна — из списка
## WINDOW_SIZES (16:9). С 18.10.2026 графика вчетверо детальнее базовых 640×360 (под 2560×1440) и сглаживается при
## уменьшении, поэтому масштаб дробный (stretch «fractional»): игра заполняет любой экран 16:9, а не только кратный.
## Настройки экрана локальные: в сеть не уходят.

signal display_changed

enum DisplayMode { WINDOWED, FULLSCREEN }

const PATH := "user://settings.cfg"
const LOCALES: PackedStringArray = ["ru", "en"]
const DEFAULT_LOCALE := "ru"
## Ключи перевода режимов экрана — в порядке DisplayMode.
const DISPLAY_MODE_KEYS: PackedStringArray = ["DISPLAY_WINDOWED", "DISPLAY_FULLSCREEN"]
const BASE_SIZE := Vector2i(640, 360)
## Размеры окна на выбор (16:9); в списке настроек — только те, что влезают на экран.
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(640, 360), Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3200, 1800), Vector2i(3840, 2160)]
## Окно по умолчанию, если влезает на экран.
const DEFAULT_WINDOW_SIZE := Vector2i(1280, 720)
## Запас под рамку окна и панель задач: окно не должно уходить за край экрана.
const WINDOW_DECOR := Vector2i(16, 48)

const KEY_BINDINGS := {
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"debug_overlay": [KEY_F3],
	&"inventory": [KEY_I, KEY_TAB],
	&"pause": [KEY_ESCAPE, KEY_P],
	&"interact": [KEY_E],
	&"drink_potion": [KEY_Q],
	&"toggle_fullscreen": [KEY_F11],
}
const STICK_BINDINGS := {
	&"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_down": [JOY_AXIS_LEFT_Y, 1.0],
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
}
const BUTTON_BINDINGS := {
	&"pause": JOY_BUTTON_START,
	&"inventory": JOY_BUTTON_BACK,
	&"interact": JOY_BUTTON_X,
	&"drink_potion": JOY_BUTTON_Y,
}

var locale := DEFAULT_LOCALE
var master_volume := 0.8
## Шины Music и SFX (шаг 11.13, default_bus_layout.tres): эмбиент тише по умолчанию — фон, а не песня.
var music_volume := 0.6
var sfx_volume := 0.8
## Всплывающие цифры урона над врагами.
var show_damage_numbers := true
var display_mode := DisplayMode.WINDOWED
## Размер окна (только в режиме «В окне»); не влезает на экран — берётся наибольший из WINDOW_SIZES, что влезает.
var window_size := DEFAULT_WINDOW_SIZE
## Фильтр лута (шаг 7): предметы ниже этой редкости (ItemRoller.Rarity) лежат без подписи, сияния и звука —
## подобрать их можно. Только облик у этого игрока: в сеть не уходит. Ключи — LOOT_FILTER_KEYS по уровню.
var loot_filter := 0

## Качество эффектов (шаг 11.8): 0 — низкое (без карты света), 1 — среднее, 2 — высокое. Что меняется по
## качеству — VisualConfig (*_by_quality). Только облик у этого игрока: в сеть не уходит.
var effects_quality := 2
## Тряска камеры и стоп-кадр при сильном ударе (шаг 11.9, Juice). Стоп-кадр бывает только в одиночной игре.
var screen_shake := true
var hit_stop := true
## Пост-эффекты (шаг 11.10, PostFx): виньетка, красные края при ране, аберрация на малом здоровье.
var post_effects := true
## Предел FPS (Engine.max_fps), 0 — без предела.
var fps_limit := 0

signal loot_filter_changed
signal graphics_changed

const LOOT_FILTER_KEYS: PackedStringArray = ["LOOT_FILTER_ALL", "LOOT_FILTER_MAGIC", "LOOT_FILTER_RARE"]
const QUALITY_KEYS: PackedStringArray = ["QUALITY_LOW", "QUALITY_MEDIUM", "QUALITY_HIGH"]
const FPS_LIMITS: PackedInt32Array = [0, 30, 60, 120, 144]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # F11 работает и на паузе
	_register_default_inputs()
	load_settings()
	TranslationServer.set_locale(locale)
	_apply_volume()
	_apply_display()
	# Без окна (проверки) и без предела — не трогаем: net_test задаёт --max-fps сам.
	if fps_limit > 0 and DisplayServer.get_name() != "headless":
		Engine.max_fps = fps_limit


## Раньше интерфейса: Alt+Enter не должен нажимать кнопку в фокусе.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var alt_enter := key != null and key.pressed and not key.echo and key.alt_pressed \
			and key.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if alt_enter or event.is_action_pressed(&"toggle_fullscreen"):
		get_viewport().set_input_as_handled()
		var windowed := display_mode == DisplayMode.FULLSCREEN
		set_display_mode(DisplayMode.WINDOWED if windowed else DisplayMode.FULLSCREEN)


func set_display_mode(value: int) -> void:
	display_mode = clampi(value, 0, DisplayMode.size() - 1) as DisplayMode
	_apply_display()
	save_settings()
	display_changed.emit()


func set_window_size(value: Vector2i) -> void:
	if value in WINDOW_SIZES:
		window_size = value
	_apply_display()
	save_settings()
	display_changed.emit()


## Размеры окна, которые влезают на текущий экран (хотя бы наименьший).
func window_sizes() -> Array[Vector2i]:
	var sizes: Array[Vector2i] = []
	var usable := Vector2i(1 << 30, 1 << 30)
	if DisplayServer.get_name() != "headless":
		usable = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size - WINDOW_DECOR
	for size in WINDOW_SIZES:
		if size.x <= usable.x and size.y <= usable.y:
			sizes.append(size)
	if sizes.is_empty():
		sizes.append(WINDOW_SIZES[0])
	return sizes


## Размер, который реально встанет: выбранный или наибольший из влезающих, если выбранный не влезает.
func fitted_window_size() -> Vector2i:
	var sizes := window_sizes()
	return window_size if window_size in sizes else sizes.back()


static func window_size_text(size: Vector2i) -> String:
	return "%d × %d" % [size.x, size.y]


func set_locale(value: String) -> void:
	if value not in LOCALES:
		return
	locale = value
	TranslationServer.set_locale(locale)  # интерфейс обновится без перезапуска
	save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volume()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volume()


func set_show_damage_numbers(value: bool) -> void:
	show_damage_numbers = value
	save_settings()


func set_loot_filter(value: int) -> void:
	loot_filter = clampi(value, 0, LOOT_FILTER_KEYS.size() - 1)
	save_settings()
	loot_filter_changed.emit()


func set_effects_quality(value: int) -> void:
	effects_quality = clampi(value, 0, QUALITY_KEYS.size() - 1)
	save_settings()
	graphics_changed.emit()


func set_screen_shake(value: bool) -> void:
	screen_shake = value
	save_settings()
	graphics_changed.emit()


func set_hit_stop(value: bool) -> void:
	hit_stop = value
	save_settings()
	graphics_changed.emit()


func set_post_effects(value: bool) -> void:
	post_effects = value
	save_settings()
	graphics_changed.emit()


func set_fps_limit(value: int) -> void:
	fps_limit = value if value in FPS_LIMITS else 0
	Engine.max_fps = fps_limit
	save_settings()
	graphics_changed.emit()


## Виден ли предмет редкости rarity во всей красе (подпись, сияние, звук).
func shows_loot(rarity: int) -> bool:
	return rarity >= loot_filter


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	locale = config.get_value("ui", "locale", DEFAULT_LOCALE)
	if locale not in LOCALES:
		locale = DEFAULT_LOCALE
	show_damage_numbers = bool(config.get_value("ui", "damage_numbers", show_damage_numbers))
	loot_filter = clampi(int(config.get_value("ui", "loot_filter", loot_filter)), 0, LOOT_FILTER_KEYS.size() - 1)
	master_volume = config.get_value("audio", "master_volume", master_volume)
	music_volume = config.get_value("audio", "music_volume", music_volume)
	sfx_volume = config.get_value("audio", "sfx_volume", sfx_volume)
	display_mode = clampi(int(config.get_value("display", "mode", display_mode)), 0, DisplayMode.size() - 1) as DisplayMode
	var saved: Variant = config.get_value("display", "window_size", Vector2i.ZERO)
	if saved is Vector2i and saved in WINDOW_SIZES:
		window_size = saved
	elif config.has_section_key("display", "window_scale"):  # до 18.10.2026 — кратность 640×360
		var legacy := BASE_SIZE * clampi(int(config.get_value("display", "window_scale", 2)), 1, 6)
		window_size = legacy if legacy in WINDOW_SIZES else DEFAULT_WINDOW_SIZE
	effects_quality = clampi(int(config.get_value("graphics", "quality", effects_quality)), 0, QUALITY_KEYS.size() - 1)
	screen_shake = bool(config.get_value("graphics", "screen_shake", screen_shake))
	hit_stop = bool(config.get_value("graphics", "hit_stop", hit_stop))
	post_effects = bool(config.get_value("graphics", "post_effects", post_effects))
	fps_limit = int(config.get_value("graphics", "fps_limit", fps_limit))
	if fps_limit not in FPS_LIMITS:
		fps_limit = 0


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("ui", "locale", locale)
	config.set_value("ui", "damage_numbers", show_damage_numbers)
	config.set_value("ui", "loot_filter", loot_filter)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("display", "mode", display_mode)
	config.set_value("display", "window_size", window_size)
	config.set_value("graphics", "quality", effects_quality)
	config.set_value("graphics", "screen_shake", screen_shake)
	config.set_value("graphics", "hit_stop", hit_stop)
	config.set_value("graphics", "post_effects", post_effects)
	config.set_value("graphics", "fps_limit", fps_limit)
	config.save(PATH)


## Режим и размер окна. Без окна (headless: проверки, сервер) — ничего не делает.
func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if display_mode == DisplayMode.FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size := fitted_window_size()
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))
	for bus: Array in [[&"Music", music_volume], [&"SFX", sfx_volume]]:
		var index := AudioServer.get_bus_index(bus[0])
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(bus[1]))


func _register_default_inputs() -> void:
	for action: StringName in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for keycode: Key in KEY_BINDINGS[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)
		if STICK_BINDINGS.has(action):
			var stick := InputEventJoypadMotion.new()
			stick.axis = STICK_BINDINGS[action][0]
			stick.axis_value = STICK_BINDINGS[action][1]
			InputMap.action_add_event(action, stick)
		if BUTTON_BINDINGS.has(action):
			var button := InputEventJoypadButton.new()
			button.button_index = BUTTON_BINDINGS[action]
			InputMap.action_add_event(action, button)
