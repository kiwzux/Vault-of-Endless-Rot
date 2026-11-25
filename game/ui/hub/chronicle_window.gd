class_name ChronicleWindow
extends HubWindow
## Летопись и Склеп трофеев (шаг 10.2–10.3): счётчики за все забеги и рекорды героев, бестиарий
## (встреченная нечисть; невстреченная — тёмный силуэт), трофеи — найденные легендарные предметы — и
## записи лора, прочитанные на картах (шаг 8).

const ICON_SIZE := Vector2(24, 24)
const BESTIARY_COLUMNS := 4


func build() -> void:
	set_title(tr("HUB_CHRONICLE_TITLE"))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 9)
	body.add_child(tabs)
	_add_tab(tabs, _records(), "HUB_TAB_RECORDS")
	_add_tab(tabs, _bestiary(), "HUB_TAB_BESTIARY")
	_add_tab(tabs, _trophies(), "HUB_TAB_TROPHIES")
	_add_tab(tabs, _lore(), "HUB_TAB_LORE")


## Записи лора (шаг 8): прочитанные — заголовок и текст, остальные — «???».
func _lore() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.add_child(HubWindow.make_label(tr("HUB_LORE_COUNT").format(
			{"found": MetaProfile.count(&"lore"), "total": DataRegistry.LORE.size()}), 9, TITLE_COLOR))
	for lore: LoreData in DataRegistry.LORE:
		if not MetaProfile.has_lore(lore.id):
			column.add_child(HubWindow.make_label("???", 9, DIM_COLOR))
			continue
		column.add_child(HubWindow.make_label(tr(lore.title_key), 10, TITLE_COLOR))
		var text := HubWindow.make_label(tr(lore.text_key), 8, TEXT_COLOR)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(HubWindow.WRAP_WIDTH - 20.0, 0)
		column.add_child(text)
	return column


func _add_tab(tabs: TabContainer, content: Control, key: String) -> void:
	var scroll := HubWindow.make_scroll(content)
	tabs.add_child(scroll)
	tabs.set_tab_title(tabs.get_tab_count() - 1, tr(key))


func _records() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	for counter in QuestData.COUNTERS:
		grid.add_child(HubWindow.make_label(tr("CHRONICLE_" + String(counter).to_upper()), 9, TEXT_COLOR))
		grid.add_child(HubWindow.make_label(str(MetaProfile.count(counter)), 9, TITLE_COLOR))
	column.add_child(grid)
	column.add_child(HubWindow.make_label(tr("HUB_HERO_RECORDS"), 10, TITLE_COLOR))
	for hero: HeroData in DataRegistry.HEROES:
		var record := MetaProfile.hero_record(hero.id)
		var text := tr("HUB_HERO_RECORD").format({"name": tr(hero.name_key), "runs": record.runs,
				"victories": record.victories, "depth": record.best_depth, "kills": record.best_kills})
		column.add_child(HubWindow.make_label(text, 8, TEXT_COLOR if record.runs > 0 else DIM_COLOR))
	return column


func _bestiary() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = BESTIARY_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	for enemy: EnemyData in DataRegistry.ENEMIES:
		var met := MetaProfile.seen(enemy.id)
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(98, 0)
		var icon := TextureRect.new()
		icon.texture = enemy_icon(enemy.id)
		icon.custom_minimum_size = ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # кадр 96 px в маленькой клетке
		icon.modulate = Color.WHITE if met > 0 else Color(0, 0, 0, 0.8)
		cell.add_child(icon)
		var name_text := "%s ×%d" % [tr(enemy.name_key), met] if met > 0 else "???"
		var label := HubWindow.make_label(name_text, 7, (Color(0.95, 0.5, 0.4) if enemy.is_boss else TEXT_COLOR) if met > 0 else DIM_COLOR)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(70, 0)
		cell.add_child(label)
		grid.add_child(cell)
	return grid


func _trophies() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_child(HubWindow.make_label(tr("HUB_TROPHIES_COUNT").format(
			{"found": MetaProfile.count(&"trophies"), "total": DataRegistry.UNIQUE_ITEMS.size()}), 9, TITLE_COLOR))
	for unique: UniqueItemData in DataRegistry.UNIQUE_ITEMS:
		var found := MetaProfile.has_trophy(unique.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()  # значок легендарки (шаг 11.15); не найдена — тёмный силуэт, как в бестиарии
		icon.texture = ItemIcon.texture(ItemRoller.icon_of({"base": unique.base.id, "unique": unique.id, "stats": unique.stats}))
		icon.custom_minimum_size = ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = ItemIcon.FILTER
		icon.modulate = Color.WHITE if found else Color(0, 0, 0, 0.8)
		row.add_child(icon)
		var label := HubWindow.make_label(tr(unique.name_key) if found else "???", 9,
				Color(0.95, 0.6, 0.25) if found else DIM_COLOR)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		column.add_child(row)
	return column


## Первый кадр покоя врага из общего атласа (EnemyArt); нет листа — пусто.
static func enemy_icon(id: StringName) -> Texture2D:
	if not EnemyArt.has_sheet(id):
		return null
	var layout := EnemyArt.sheet(id)
	var icon := AtlasTexture.new()
	icon.atlas = EnemyArt.texture
	icon.region = layout.region(layout.frame(&"idle", 0))
	return icon
