class_name RunStatsView
extends VBoxContainer
## Статистика забега на экране конца забега (как в Megabonk): сводка героя — время, убийства, опыт, золото,
## элиты, боссы, полученный урон — и таблица навыков: уровень, урон, урон в секунду, убийства и доля урона
## полосой. В кооперативе ниже — строка на каждого героя отряда.
##
## Данные — Player.run_stats (RunStats.summary_of): у хоста свои, у клиента пришли синхронизацией героя.
## Таблица строится заново, только когда сводка изменилась (refresh зовут каждый кадр, пока экран открыт).

const FONT_SIZE := 8
const HEADER_SIZE := 9
const DIM := Color(0.68, 0.6, 0.48)
const BRIGHT := Color(1.0, 0.93, 0.78)
const GOLD := Color(1.0, 0.8, 0.35)
const BAR_WIDTH := 56.0
const BAR_HEIGHT := 5.0
const BAR_BACK := Color(0.12, 0.09, 0.07)
const OTHER_COLOR := Color(0.55, 0.5, 0.45)
## Колонки таблицы навыков: название, уровень, урон, урон в секунду, убийства, доля.
const SKILL_COLUMNS := ["RUN_STATS_SKILL", "RUN_STATS_LEVEL", "RUN_STATS_DAMAGE", "RUN_STATS_DPS", "RUN_STATS_KILLS",
		"RUN_STATS_SHARE"]
const PARTY_COLUMNS := ["RUN_STATS_HERO", "RUN_STATS_LEVEL", "RUN_STATS_KILLS", "RUN_STATS_DAMAGE"]


## Полоска доли урона навыка.
class ShareBar:
	extends Control
	var share := 0.0
	var color := Color.WHITE

	func _init(p_share: float, p_color: Color) -> void:
		share = clampf(p_share, 0.0, 1.0)
		color = p_color
		custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BAR_BACK)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * share, size.y)), color)


var _signature := -1


func _ready() -> void:
	add_theme_constant_override("separation", 6)


## Перестроить, если сводки героев изменились. me — свой герой, party — все герои забега.
func refresh(me: Player, party: Array[Player]) -> void:
	var sources: Array = []
	for player in party:
		sources.append([player.peer_id(), player.run_stats, player.kills, player.level])
	var signature := hash([me.peer_id() if me != null else 0, sources, TranslationServer.get_locale()])
	if signature == _signature:
		return
	_signature = signature
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if me == null:
		return
	var summary := me.run_stats
	add_child(_summary_grid(me, summary))
	add_child(_skills_grid(summary))
	if party.size() > 1:
		add_child(_party_grid(party))


## Сводка героя: пары «название — число» в 4 колонки.
func _summary_grid(me: Player, summary: Dictionary) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 1)
	var pairs := [
		["RUN_STATS_TIME", clock(float(summary.get("time", 0.0)))],
		["RUN_STATS_KILLS", short_number(me.kills)],
		["RUN_STATS_XP", short_number(int(summary.get("xp", 0)))],
		["RUN_STATS_GOLD", short_number(int(summary.get("gold", 0)))],
		["RUN_STATS_ELITES", str(int(summary.get("elites", 0)))],
		["RUN_STATS_BOSSES", str(int(summary.get("bosses", 0)))],
		["RUN_STATS_DAMAGE_DEALT", short_number(RunStats.total_damage(summary))],
		["RUN_STATS_DAMAGE_TAKEN", short_number(int(summary.get("taken", 0)))],
	]
	for pair: Array in pairs:
		grid.add_child(_label(tr(pair[0]), DIM))
		grid.add_child(_label(pair[1], BRIGHT))
	return grid


## Таблица навыков: по убыванию урона, у каждого — цвет навыка, уровень, урон, урон в секунду, убийства, доля.
func _skills_grid(summary: Dictionary) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = SKILL_COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	for key: String in SKILL_COLUMNS:
		grid.add_child(_label(tr(key), GOLD, HEADER_SIZE))
	var total := maxi(RunStats.total_damage(summary), 1)
	var rows: Array = summary.get("skills", [])
	if rows.is_empty():
		grid.add_child(_label(tr("RUN_STATS_NO_DATA"), DIM))
		for i in SKILL_COLUMNS.size() - 1:
			grid.add_child(Control.new())
		return grid
	for row: Array in rows:
		var source := String(row[0])
		var color := _source_color(source)
		var name_box := HBoxContainer.new()
		name_box.add_theme_constant_override("separation", 4)
		var swatch := ColorRect.new()
		swatch.color = color
		swatch.custom_minimum_size = Vector2(6, 6)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_box.add_child(swatch)
		name_box.add_child(_label(tr(RunStats.source_name_key(source)), BRIGHT))
		grid.add_child(name_box)
		var level := int(row[4])
		grid.add_child(_label(str(level) if level > 0 else "—", BRIGHT, FONT_SIZE, true))
		grid.add_child(_label(short_number(int(row[1])), BRIGHT, FONT_SIZE, true))
		grid.add_child(_label(short_number(roundi(RunStats.row_dps(row))), BRIGHT, FONT_SIZE, true))
		grid.add_child(_label(short_number(int(row[2])), BRIGHT, FONT_SIZE, true))
		var share := float(row[1]) / total
		var share_box := HBoxContainer.new()
		share_box.add_theme_constant_override("separation", 4)
		share_box.add_child(ShareBar.new(share, color))
		share_box.add_child(_label("%d%%" % roundi(share * 100.0), DIM))
		grid.add_child(share_box)
	return grid


## Кооператив: герой, уровень, убийства и весь урон каждого участника.
func _party_grid(party: Array[Player]) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = PARTY_COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 1)
	for key: String in PARTY_COLUMNS:
		grid.add_child(_label(tr(key), GOLD, HEADER_SIZE))
	for player in party:
		var mine := player.is_multiplayer_authority()
		var color := GOLD if mine else BRIGHT
		grid.add_child(_label(tr(player.hero.name_key), color))
		grid.add_child(_label(str(player.level), color, FONT_SIZE, true))
		grid.add_child(_label(short_number(player.kills), color, FONT_SIZE, true))
		grid.add_child(_label(short_number(RunStats.total_damage(player.run_stats)), color, FONT_SIZE, true))
	return grid


func _label(text: String, color: Color, font_size: int = FONT_SIZE, right: bool = false) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # текст уже переведён
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


static func _source_color(source: String) -> Color:
	var upgrade := DataRegistry.upgrade(StringName(source))
	return upgrade.icon_color if upgrade != null else OTHER_COLOR


## 1234 → «1234», 12 345 → «12,3 тыс.»-подобное: «12.3K» по ключам перевода (NUM_K, NUM_M, NUM_DECIMAL).
static func short_number(value: int) -> String:
	if absi(value) < 10000:
		return str(value)
	var scaled := value / 1000.0
	var suffix := TranslationServer.translate("NUM_K")
	if absi(value) >= 1000000:
		scaled = value / 1000000.0
		suffix = TranslationServer.translate("NUM_M")
	var digits := ("%.1f" % scaled) if absf(scaled) < 100.0 else str(roundi(scaled))
	return digits.replace(".", TranslationServer.translate("NUM_DECIMAL")) + suffix


## Секунды → «м:сс» (или «ч:мм:сс»).
static func clock(seconds: float) -> String:
	var total := floori(seconds)
	@warning_ignore("integer_division")
	var hours := total / 3600
	@warning_ignore("integer_division")
	var minutes := (total / 60) % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, total % 60]
	return "%d:%02d" % [minutes, total % 60]
