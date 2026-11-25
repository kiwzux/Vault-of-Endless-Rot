class_name HubWindow
extends PanelContainer
## Окно станции Убежища (шаг 10.3): рамка темы, заголовок, содержимое и кнопка «Закрыть». Открывает его
## Sanctuary по E у станции, закрывает Esc или кнопка; пока окно открыто, герой стоит. Содержимое строит
## наследник в build() при каждом открытии — так окно всегда показывает свежий профиль.

signal closed

const TITLE_COLOR := Color(0.95, 0.78, 0.4)
const TEXT_COLOR := Color(0.86, 0.8, 0.68)
const DIM_COLOR := Color(0.55, 0.5, 0.42)
const GOOD_COLOR := Color(0.6, 0.9, 0.55)
const SOUL_COLOR := Color(0.9, 0.32, 0.25)
const WINDOW_SIZE := Vector2(440, 300)
## Ширина текста с переносом: без неё метка при первой раскладке считает высоту по нулевой ширине.
const WRAP_WIDTH := 400.0

var sanctuary: Sanctuary
var body: VBoxContainer
var _title: Label


func _init() -> void:
	visible = false
	# Окно в центре экрана и растёт в обе стороны: содержимое со скроллом его не раздвигает.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WINDOW_SIZE.x / 2.0
	offset_right = WINDOW_SIZE.x / 2.0
	offset_top = -WINDOW_SIZE.y / 2.0
	offset_bottom = WINDOW_SIZE.y / 2.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = make_label("", 14, TITLE_COLOR)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "HUB_CLOSE"
	close.add_theme_font_size_override("font_size", 9)
	close.pressed.connect(close_window)
	header.add_child(close)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	column.add_child(body)


func open() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	build()
	show()
	_focus_first.call_deferred()


func close_window() -> void:
	if visible:
		hide()
		closed.emit()


## Наследник: заголовок (set_title) и содержимое в body.
func build() -> void:
	pass


## Обновить содержимое, не закрывая окна (после покупки, получения награды).
func refresh() -> void:
	if visible:
		open()


func set_title(text: String) -> void:
	_title.text = text


func _focus_first() -> void:
	var owner_now := get_viewport().gui_get_focus_owner()
	if owner_now != null and is_ancestor_of(owner_now):
		return  # окно уже поставило фокус само (Врата — на «В бой»)
	var target := _first_focusable(body)
	if target != null:
		target.grab_focus()


func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is BaseButton and not (child as BaseButton).disabled and (child as Control).visible:
			return child
		var inner := _first_focusable(child)
		if inner != null:
			return inner
	return null


## Строка без автоперевода: текст уже прошёл tr().
static func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func make_scroll(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


## Портрет — первый кадр покоя из листа героя (HeroData.portrait_region); crop — часть кадра.
static func portrait(hero: HeroData, crop: Rect2 = Rect2()) -> Texture2D:
	var icon := AtlasTexture.new()
	icon.atlas = hero.sprite_sheet
	var frame := hero.portrait_region()
	icon.region = Rect2(frame.position + crop.position, crop.size) if crop.has_area() else frame
	return icon


## Карточка класса: имя, портрет, описание, характеристики (окно Врат, статуи Зала героев).
static func hero_card(hero: HeroData) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var picture := TextureRect.new()
	picture.texture = portrait(hero)
	picture.custom_minimum_size = Vector2(64, 64)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # кадр 96 px в рамке 64 — дробный масштаб
	row.add_child(picture)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(make_label(tr_static(hero.name_key), 13, TITLE_COLOR))
	var description := make_label(tr_static(hero.description_key), 9, TEXT_COLOR)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(220, 0)
	info.add_child(description)
	var weapon := DataRegistry.upgrade(hero.starting_weapon)
	var lines := PackedStringArray([
		tr_static("HUB_STAT_HEALTH").format({"value": roundi(hero.max_health)}),
		tr_static("HUB_STAT_SPEED").format({"value": roundi(hero.move_speed)}),
		tr_static("HUB_STAT_WEAPON").format({"name": tr_static(weapon.name_key) if weapon != null else "—"}),
	])
	if hero.max_mana > 0.0:
		lines.insert(1, tr_static("HUB_STAT_MANA").format({"value": roundi(hero.max_mana)}))
	info.add_child(make_label("\n".join(lines), 9, Color(0.6, 0.7, 0.95)))
	row.add_child(info)
	return row


## tr() из статической функции.
static func tr_static(key: String) -> String:
	return TranslationServer.translate(key)
