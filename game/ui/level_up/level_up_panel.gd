extends CanvasLayer
## Выбор 1 из 3 карт при повышении уровня (ФТ-10). Предложение показывается только своему игроку;
## выбор уходит хосту через UpgradeSystem.submit_choice (в сети — RPC и проверка на хосте, ФТ-16).
## В одиночной игре мир на время выбора стоит на паузе; в кооперативе мир не останавливается.
## Отложенный выбор в кооперативе (14.10.2026): окно не всплывает само — внизу HUD подсказка «R — выбрать улучшение»
## (число ждущих повышений — Player.pending_choices), игрок открывает его клавишей R, когда удобно; R или Esc —
## закрыть и выбрать позже (предложение ждёт у хоста). После выбора следующее ждущее предложение открывается сразу.
## Переброс — T (R занята отложенным выбором).
##
## Карта показывает тип (оружие, пассивка, эволюция, дар, руна) ярлыком, редкость — цветом рамки и сиянием
## (редкая +2 уровня, эпическая +3, легендарная +5), уровень «было → станет» и полосу до максимума (20 у навыка,
## 25 у пассивки), у оружия — что изменится, у пассивки — итог после взятия. Карта ступени эволюции — навык,
## ступень N из 4, что даёт ступень и когда следующая (превращение в облик — карта облика со своей ступенью). Переброс за золото (кнопка или T):
## новые 3 карты, каждый следующий переброс дороже (как в Vampire Survivors). Изгнание (кнопка под
## картой или Shift+1–3): карта не выпадет до конца забега, на её место хост кладёт другую.
## Шаг 4: карта руны — какая руна, в какой навык, гнездо N из UpgradeRules.runes_per_skill, руны навыка;
## у нового навыка и у руны с тегом — как изменятся резонансы (Synergies).
## Текст не вылезает за рамку: после раскладки все карты растут до самой длинной (но не выше экрана),
## а если и так не влезло — шрифт такой карты становится на шаг мельче (_fit_cards).

const CARD_SIZE := Vector2(196, 228)
## Значок навыка на карте, px интерфейса (шаг 11.18).
const CARD_ICON := 28.0
## Отступ колонки окна от краёв экрана, когда карты растут по тексту.
const SCREEN_PAD := 6.0
## Мельче этого шрифт карты не становится.
const MIN_FONT_SIZE := 8
## Сколько раз подгонка уменьшает шрифт, прежде чем сдаться.
const FIT_ATTEMPTS := 3
const BANISH_COLOR := Color(0.85, 0.35, 0.3)
const BAR_SIZE := Vector2(64, 5)
const WEAPON_COLOR := Color(0.85, 0.65, 0.3)
const PASSIVE_COLOR := Color(0.4, 0.6, 0.95)
const GIFT_COLOR := Color(0.62, 0.58, 0.5)
const EVOLUTION_COLOR := Color(1.0, 0.5, 0.15)
const RUNE_COLOR := Color(0.72, 0.58, 0.95)
## Цвет рамки по редкости карты (UpgradePool.Rarity); у обычной — цвет типа.
const RARITY_COLORS: Array[Color] = [Color.WHITE, Color(0.35, 0.6, 1.0), Color(0.75, 0.4, 1.0), Color(1.0, 0.6, 0.12)]
const RARITY_KEYS: PackedStringArray = ["", "CARD_RARITY_RARE", "CARD_RARITY_EPIC", "CARD_RARITY_LEGENDARY"]
const CARD_BACK := Color(0.11, 0.08, 0.06)
const TEXT_COLOR := Color(0.86, 0.8, 0.68)
const DELTA_COLOR := Color(0.55, 0.8, 1.0)
## Теги оружия под названием карты (шаг 2).
const TAG_COLOR := Color(0.7, 0.62, 0.5)
## Строка резонанса, который карта доведёт до нового порога.
const SYNERGY_TIER_COLOR := Color(1.0, 0.82, 0.35)
## Клавиши: отложенный выбор (кооператив) и переброс.
const DEFER_KEY := KEY_R
const REROLL_KEY := KEY_T
## Предложение, пришедшее так скоро после выбора, — следующее ждущее: окно открывается само, мс.
const CONTINUE_MS := 1500

var _world: World
var _player: Player
var _gold_shown := -1
var _card_buttons: Array[Button] = []
var _banish_buttons: Array[Button] = []
## Номер предложения: подгонка прошлого прекращается, если пришло новое.
var _offer_serial := 0
## Последнее предложение хоста своему игроку, пока карта не выбрана (отложенный выбор).
var _stored: Array = []
var _chose_at := -CONTINUE_MS
## Отложенный выбор и вне кооператива (проверки).
var defer_always := false

@onready var column: VBoxContainer = $Center/Column
@onready var cards_box: HBoxContainer = %Cards
@onready var gold_label: Label = %Gold
@onready var reroll_button: Button = %RerollButton
@onready var hint_label: Label = $Center/Column/Hint


func _ready() -> void:
	hide()
	_world = World.of(self)
	Events.level_up_offered.connect(_on_level_up_offered)
	reroll_button.pressed.connect(_reroll)


## Выбор откладывается до клавиши R: в кооперативе (мир не ждёт, окно не должно всплывать посреди боя).
func deferred() -> bool:
	return Net.is_online() or defer_always


## Есть ли предложение, которое ждёт выбора (для подсказки HUD).
func has_offer() -> bool:
	return not _stored.is_empty()


## Открыть отложенное предложение (клавиша R). false — открывать нечего или окно уже открыто.
func open_offer() -> bool:
	if _stored.is_empty() or visible:
		return false
	_show_offer(_stored)
	return true


## Закрыть окно, не выбирая: предложение ждёт у хоста, R откроет его снова.
func defer_offer() -> void:
	if visible:
		hide()
		_set_paused(false)


func _on_level_up_offered(peer_id: int, cards: Array) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	_stored = cards
	if not deferred() or visible or Time.get_ticks_msec() - _chose_at < CONTINUE_MS:
		_show_offer(cards)


func _show_offer(cards: Array) -> void:
	_player = _world.local_player()
	hint_label.text = "LEVEL_UP_HINT_DEFER" if deferred() else "LEVEL_UP_HINT"
	for child in cards_box.get_children():
		cards_box.remove_child(child)
		child.queue_free()
	_card_buttons.clear()
	_banish_buttons.clear()
	var banishes_left := _player.banishes_left if _player != null else 0
	for i in cards.size():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		var card: Button
		if cards[i].has("rune"):
			card = _make_rune_card(i, cards[i])
		elif cards[i].has("skill"):
			card = _make_stage_card(i, cards[i])
		else:
			card = _make_card(i, cards[i])
		column.add_child(card)
		column.add_child(_make_banish(cards[i], banishes_left))
		cards_box.add_child(column)
		_card_buttons.append(card)
	show()
	_set_paused(true)
	_update_reroll()
	if not _world.is_ui_open(PauseMenu.PAUSE_REASON):
		_card_buttons[0].grab_focus()
	_offer_serial += 1
	_fit_cards(_offer_serial)


## Подгонка карт под текст: высоту переносимого текста контейнеры знают только после раскладки,
## поэтому карты меряются кадром позже. Все карты одной высоты — по самой длинной, но окно целиком
## остаётся на экране; не влезло и так — шрифт переполненной карты на шаг мельче, и снова замер.
func _fit_cards(serial: int) -> void:
	for attempt in FIT_ATTEMPTS + 1:
		await get_tree().process_frame
		if serial != _offer_serial or not visible or _card_buttons.is_empty():
			return
		var current := _card_buttons[0].custom_minimum_size.y
		var limit := get_viewport().get_visible_rect().size.y - 2.0 * SCREEN_PAD \
				- (column.get_combined_minimum_size().y - current)
		var need := current
		for card in _card_buttons:
			need = maxf(need, _content_height(card))
		var height := minf(need, maxf(limit, CARD_SIZE.y))
		for card in _card_buttons:
			card.custom_minimum_size.y = height
		if need <= height or attempt == FIT_ATTEMPTS:
			return
		for card in _card_buttons:
			if _content_height(card) > height:
				_shrink_fonts(card)


## Высота, которая нужна тексту карты (с полями).
func _content_height(card: Button) -> float:
	return (card.get_child(0) as Control).get_combined_minimum_size().y


func _shrink_fonts(card: Button) -> void:
	for node in card.find_children("*", "Label", true, false):
		var label := node as Label
		var font_size := label.get_theme_font_size(&"font_size")
		if font_size > MIN_FONT_SIZE:
			label.add_theme_font_size_override(&"font_size", font_size - 1)


## Для проверок: текст каждой карты помещается в её рамку, а карты — на экран.
func cards_fit() -> bool:
	var screen := get_viewport().get_visible_rect()
	for card in _card_buttons:
		if _content_height(card) > card.size.y + 0.5 or not screen.encloses(card.get_global_rect()):
			return false
	return not _card_buttons.is_empty()


func _process(_delta: float) -> void:
	if visible and _player != null and is_instance_valid(_player) and _player.gold != _gold_shown:
		_update_reroll()


func _update_reroll() -> void:
	if _player == null or not is_instance_valid(_player):
		reroll_button.hide()
		return
	var cost := _world.economy.reroll_cost(_player)
	_gold_shown = _player.gold
	gold_label.text = tr("SHOP_GOLD").format({"gold": _player.gold})
	reroll_button.text = tr("LEVEL_UP_REROLL").format({"cost": cost})
	reroll_button.disabled = _player.gold < cost
	reroll_button.show()


func _make_card(index: int, card: Dictionary) -> Button:
	var upgrade := DataRegistry.upgrade(card["id"])
	var from: int = card.get("from", 0)
	var to: int = card["level"]
	var rarity: int = card.get("rarity", UpgradePool.Rarity.COMMON)
	var evolution: bool = card.get("evolution", false)
	var frame_color := RARITY_COLORS[rarity] if rarity > UpgradePool.Rarity.COMMON else _kind_color(upgrade, evolution)
	var column := VBoxContainer.new()
	var button := _card_shell(column, frame_color, evolution or rarity >= UpgradePool.Rarity.EPIC, upgrade.id)

	var tag := tr(_kind_key(upgrade, evolution))
	if rarity > UpgradePool.Rarity.COMMON:
		tag += " · " + tr(RARITY_KEYS[rarity])
	var stage: int = card.get("stage", 0)
	if evolution and stage > 0:
		tag += " · " + _stage_text(stage)
	column.add_child(_label(tag, frame_color.lightened(0.2), 9))
	# Шаг 11.18: значок рядом с названием; у эволюции — «базовый навык → эволюция», крупнее.
	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_constant_override("separation", 4)
	var base := DataRegistry.evolution_base(upgrade.id) if evolution else null
	if base != null:
		title.add_child(_icon_rect(base.icon_name(), CARD_ICON * 0.75))
		title.add_child(_label("→", EVOLUTION_COLOR, 14))
	title.add_child(_icon_rect(upgrade.icon_name(), CARD_ICON * (1.15 if evolution else 1.0)))
	var name_label := _label("%d. %s" % [index + 1, tr(upgrade.name_key)], upgrade.icon_color.lightened(0.15), 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_child(name_label)
	column.add_child(title)
	var weapon_tags := _tag_line(upgrade)
	if weapon_tags != "":
		column.add_child(_label(weapon_tags, TAG_COLOR, 8))
	column.add_child(_level_row(_level_text(upgrade, from, to, rarity, evolution), upgrade.max_level, from, to, frame_color))

	var description := _label(tr(upgrade.description_key), TEXT_COLOR, 10)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(description)
	var lines := _change_lines(upgrade, from, to, evolution)
	if evolution and stage > 0:
		lines.append(_stage_bonus(stage))
	if not lines.is_empty():
		var changes := _label("\n".join(lines), DELTA_COLOR, 9)
		changes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(changes)
	var skill := upgrade as SkillData
	if skill != null and from == 0 and not evolution:
		_add_synergy_lines(column, skill.id, DataRegistry.tag_mask(skill.tags))
	return button


## Карта руны (шаг 4): руна, навык, гнездо N из runes_per_skill, описание руны и руны, что уже в навыке.
func _make_rune_card(index: int, card: Dictionary) -> Button:
	var rune := DataRegistry.skill_modifier(StringName(str(card["rune"])))
	var skill := DataRegistry.upgrade(StringName(str(card["skill"]))) as SkillData
	var rarity: int = clampi(int(card.get("rarity", 0)), 0, RARITY_COLORS.size() - 1)
	var frame_color := RARITY_COLORS[rarity] if rarity > UpgradePool.Rarity.COMMON else RUNE_COLOR
	var column := VBoxContainer.new()
	var button := _card_shell(column, frame_color, rarity >= UpgradePool.Rarity.EPIC, StringName(str(card["id"])))
	if rune == null or skill == null:
		return button  # данные с хоста не сошлись с каталогом: карта пустая, но выбор всё равно проверит хост

	var tag := tr("CARD_KIND_RUNE")
	if rarity > UpgradePool.Rarity.COMMON:
		tag += " · " + tr(RARITY_KEYS[rarity])
	column.add_child(_label(tag, frame_color.lightened(0.2), 9))
	# Шаг 11.26: значок руны (рунный камень, обод по редкости) рядом с названием, навык — маленьким значком.
	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_constant_override("separation", 4)
	title.add_child(_icon_rect(rune.icon_name(), CARD_ICON))
	var name_label := _label("%d. %s" % [index + 1, tr(rune.name_key)], rune.icon_color.lightened(0.15), 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_child(name_label)
	column.add_child(title)
	var target := HBoxContainer.new()
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_theme_constant_override("separation", 3)
	target.add_child(_icon_rect(skill.icon_name(), CARD_ICON * 0.5))
	var target_label := _label(tr("CARD_RUNE_TARGET").format({"skill": tr(skill.name_key)}), skill.icon_color.lightened(0.2), 9)
	target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target.add_child(target_label)
	column.add_child(target)
	var slots := DataRegistry.UPGRADE_RULES.runes_per_skill
	var from: int = card.get("from", 0)
	var to: int = card["level"]
	column.add_child(_level_row(tr("CARD_RUNE_SLOT").format({"slot": to, "max": slots}), slots, from, to, frame_color))

	var description := _label(tr(rune.description_key), TEXT_COLOR, 10)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(description)
	var socketed: Array = _player.runes.get(skill.id, []) if _player != null and is_instance_valid(_player) else []
	if not socketed.is_empty():
		var line := _label(tr("CARD_RUNES").format({"list": ", ".join(_rune_names(socketed))}), DELTA_COLOR, 9)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(line)
	if not rune.add_tags.is_empty():
		_add_synergy_lines(column, skill.id, DataRegistry.tag_mask(skill.tags) | DataRegistry.tag_mask(rune.add_tags))
	return button


## Карта ступени эволюции: навык, ступень N из evolution_stages, прибавки ступени и когда следующая.
func _make_stage_card(index: int, card: Dictionary) -> Button:
	var skill := DataRegistry.upgrade(StringName(str(card["skill"]))) as SkillData
	var rules := DataRegistry.UPGRADE_RULES
	var column := VBoxContainer.new()
	var button := _card_shell(column, EVOLUTION_COLOR, true, StringName(str(card["id"])))
	if skill == null:
		return button  # данные с хоста не сошлись с каталогом: выбор всё равно проверит хост
	var from: int = card.get("from", 0)
	var stage: int = card["level"]

	column.add_child(_label(tr("CARD_KIND_EVOLUTION") + " · " + _stage_text(stage), EVOLUTION_COLOR.lightened(0.2), 9))
	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_constant_override("separation", 4)
	title.add_child(_icon_rect(skill.icon_name(), CARD_ICON * 1.15))
	var name_label := _label("%d. %s" % [index + 1, tr(skill.name_key)], skill.icon_color.lightened(0.15), 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_child(name_label)
	column.add_child(title)
	var weapon_tags := _tag_line(skill)
	if weapon_tags != "":
		column.add_child(_label(weapon_tags, TAG_COLOR, 8))
	column.add_child(_level_row(_stage_text(stage), rules.evolution_stages, from, stage, EVOLUTION_COLOR))

	var description := _label(tr("CARD_EVOLUTION_DESC").format({"step": rules.evolution_step}), TEXT_COLOR, 10)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(description)
	var lines := PackedStringArray([_stage_bonus(stage)])
	if stage < rules.evolution_stages:
		var next_level := rules.evolution_step * (stage + 1)
		if UpgradePool.is_transform(skill, stage + 1):
			lines.append(tr("CARD_EVOLUTION_NEXT_FORM").format({"stage": UpgradePool.stage_name(stage + 1),
					"level": next_level, "name": tr(skill.evolution.name_key)}))
		else:
			lines.append(tr("CARD_EVOLUTION_NEXT").format({"level": next_level}))
	var changes := _label("\n".join(lines), DELTA_COLOR, 9)
	changes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(changes)
	return button


## «Ступень II из IV».
func _stage_text(stage: int) -> String:
	return tr("CARD_EVOLUTION_STAGE").format({"stage": UpgradePool.stage_name(stage),
			"max": UpgradePool.stage_name(DataRegistry.UPGRADE_RULES.evolution_stages)})


## Что даёт ступень stage: «Урон +25 % · перезарядка −6 % · область +10 %», на каждой второй — и количество.
func _stage_bonus(stage: int) -> String:
	var rules := DataRegistry.UPGRADE_RULES
	var text := tr("CARD_EVOLUTION_BONUS").format({"damage": roundi(rules.evolution_damage * 100.0),
			"cooldown": roundi(rules.evolution_cooldown * 100.0), "area": roundi(rules.evolution_area * 100.0)})
	if rules.evolution_amount_every > 0 and stage % rules.evolution_amount_every == 0:
		text += " · " + tr("CARD_EVOLUTION_AMOUNT")
	return text


## Кнопка-карта с рамкой и колонкой для содержимого; нажатие — выбор card_id.
func _card_shell(column: VBoxContainer, frame_color: Color, glow: bool, card_id: StringName) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	_style_card(button, frame_color, glow)
	button.pressed.connect(_choose.bind(card_id))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	button.add_child(margin)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	return button


## Строка уровня с полосой до максимума.
func _level_row(text: String, max_level: int, from: int, to: int, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var level_label := _label(text, Color(0.95, 0.78, 0.4), 10)
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(level_label)
	if max_level > 1:
		row.add_child(_level_bar(max_level, from, to, color))
	return row


## Как карта изменит резонансы героя: «Резонанс «Огонь»: 1 → 2»; новый порог — ярче и со звездой.
func _add_synergy_lines(column: VBoxContainer, skill_id: StringName, new_mask: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	for gain: Array in Synergies.gains(_player.upgrade_levels, _player.runes, skill_id, new_mask):
		var synergy: SynergyData = gain[0]
		var tier_up := synergy.tier_for(gain[2]) > synergy.tier_for(gain[1])
		var key := "CARD_SYNERGY_TIER" if tier_up else "CARD_SYNERGY"
		var text := tr(key).format({"tag": Synergies.tag_name(synergy), "from": gain[1], "to": gain[2]})
		var tag := DataRegistry.tag(synergy.tag)
		var color := SYNERGY_TIER_COLOR if tier_up else (tag.color if tag != null else TAG_COLOR)
		column.add_child(_label(text, color, 9))


func _rune_names(ids: Array) -> PackedStringArray:
	var names := PackedStringArray()
	for id: Variant in ids:
		var rune := DataRegistry.skill_modifier(StringName(str(id)))
		if rune != null:
			names.append(tr(rune.name_key))
	return names


## Кнопка изгнания под картой; у эволюции и дара она неактивна (их изгнать нельзя).
func _make_banish(card: Dictionary, banishes_left: int) -> Button:
	var button := Button.new()
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.text = tr("LEVEL_UP_BANISH").format({"left": banishes_left})
	button.tooltip_text = tr("LEVEL_UP_BANISH_RUNE_TIP" if card.has("rune") else "LEVEL_UP_BANISH_TIP")
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_color_override("font_color", BANISH_COLOR)
	button.add_theme_color_override("font_hover_color", BANISH_COLOR.lightened(0.3))
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = banishes_left <= 0 or not UpgradePool.can_banish(card["id"], card.get("evolution", false))
	button.pressed.connect(_banish.bind(_banish_buttons.size(), StringName(card["id"])))
	_banish_buttons.append(button)
	return button


func _level_text(upgrade: UpgradeData, from: int, to: int, rarity: int, evolution: bool) -> String:
	if evolution:
		return tr("UPGRADE_EVOLUTION") + " · " + tr("UPGRADE_LEVEL").format({"level": to})
	if upgrade.kind == UpgradeData.Kind.FILLER:
		var times := UpgradePool.levels_for(rarity)
		return tr("UPGRADE_ANY_TIMES") if times == 1 else tr("UPGRADE_TIMES").format({"times": times})
	if from == 0:
		return tr("UPGRADE_NEW") if to == 1 else tr("UPGRADE_NEW") + " · " + tr("UPGRADE_LEVEL").format({"level": to})
	return tr("UPGRADE_LEVEL_UP").format({"from": from, "to": to})


## Что даст карта: у нового оружия — его характеристики, у взятого — изменения, у пассивки — итог.
func _change_lines(upgrade: UpgradeData, from: int, to: int, evolution: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	var weapon := upgrade as SkillData
	if weapon != null:
		if from == 0 or evolution:
			# Одной строкой: на карте нового навыка остаётся место для строки резонанса (шаг 4).
			lines.append(tr("CARD_STAT_DAMAGE").format({"value": _num(weapon.damage_at(to))}) + " · "
					+ tr("CARD_STAT_COOLDOWN").format({"value": _num(weapon.cooldown_at(to))}))
			var applies := status_line(weapon.on_hit)
			if applies != "":
				lines.append(applies)
			if not weapon.modifiers.is_empty():
				var names := PackedStringArray()
				for mod: SkillModifier in weapon.modifiers:
					names.append(tr(mod.name_key))
				lines.append(tr("CARD_RUNES").format({"list": ", ".join(names)}))
			return lines
		for line in [
			_delta("CARD_DELTA_DAMAGE", weapon.damage_at(from), weapon.damage_at(to)),
			_delta("CARD_DELTA_COOLDOWN", weapon.cooldown_at(from), weapon.cooldown_at(to)),
			_delta("CARD_DELTA_AMOUNT", weapon.amount_at(from), weapon.amount_at(to)),
			_delta("CARD_DELTA_PIERCE", weapon.pierce_at(from), weapon.pierce_at(to)),
			_delta("CARD_DELTA_RANGE", weapon.range_at(from), weapon.range_at(to)),
			_delta("CARD_DELTA_RANGE", weapon.area_at(from), weapon.area_at(to)),
		]:
			if line != "":
				lines.append(line)
		return lines
	var passive := upgrade as PassiveData
	if passive != null and upgrade.kind == UpgradeData.Kind.PASSIVE and to > 1:
		var total := ItemRoller.stat_line(passive.stat, passive.per_level * to)
		if total != "":
			lines.append(tr("CARD_TOTAL").format({"line": total}))
	return lines


## Теги оружия одной строкой: «Огонь · Снаряд · Область»; у остальных карт — пусто.
static func _tag_line(upgrade: UpgradeData) -> String:
	var weapon := upgrade as SkillData
	if weapon == null:
		return ""
	var names := PackedStringArray()
	for item in DataRegistry.tags_in(DataRegistry.tag_mask(weapon.tags)):
		names.append(TranslationServer.translate(item.name_key))
	return " · ".join(names)


## Статусы оружия: «Накладывает: Горение 50%, Холод»; пусто — не накладывает.
static func status_line(applications: Array) -> String:
	var parts := PackedStringArray()
	for app: StatusApplication in applications:
		var status := DataRegistry.status(app.status)
		if status == null:
			continue
		var text := TranslationServer.translate(status.name_key)
		if app.chance < 1.0:
			text += " %d%%" % roundi(app.chance * 100.0)
		parts.append(text)
	if parts.is_empty():
		return ""
	return TranslationServer.translate("CARD_APPLIES").format({"list": ", ".join(parts)})


## Строка «было → станет»; пустая, если характеристика не меняется.
func _delta(key: String, from: float, to: float) -> String:
	return "" if is_equal_approx(from, to) else tr(key).format({"from": _num(from), "to": _num(to)})


static func _num(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")


func _kind_key(upgrade: UpgradeData, evolution: bool) -> String:
	if evolution:
		return "CARD_KIND_EVOLUTION"
	match upgrade.kind:
		UpgradeData.Kind.WEAPON:
			return "CARD_KIND_WEAPON"
		UpgradeData.Kind.PASSIVE:
			return "CARD_KIND_PASSIVE"
	return "CARD_KIND_GIFT"


func _kind_color(upgrade: UpgradeData, evolution: bool) -> Color:
	if evolution:
		return EVOLUTION_COLOR
	match upgrade.kind:
		UpgradeData.Kind.WEAPON:
			return WEAPON_COLOR
		UpgradeData.Kind.PASSIVE:
			return PASSIVE_COLOR
	return GIFT_COLOR


func _style_card(button: Button, color: Color, glow: bool) -> void:
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = CARD_BACK.lightened(0.06 if state != "normal" else 0.0)
		style.border_color = color if state == "normal" else color.lightened(0.35)
		style.set_border_width_all(3 if glow else 2)
		style.border_width_top = 6  # полоса цвета редкости или типа карты
		if glow:
			style.shadow_color = Color(color, 0.5)
			style.shadow_size = 5
		button.add_theme_stylebox_override(state, style)


## Полоса уровня до максимума: взятые уровни, новые (ярче) и оставшиеся.
func _level_bar(max_level: int, from: int, to: int, color: Color) -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = BAR_SIZE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(func() -> void:
		var rect := Rect2(Vector2.ZERO, bar.size)
		bar.draw_rect(rect, Color(0.05, 0.04, 0.03))
		bar.draw_rect(Rect2(rect.position, Vector2(rect.size.x * to / max_level, rect.size.y)), color.lightened(0.3))
		bar.draw_rect(Rect2(rect.position, Vector2(rect.size.x * from / max_level, rect.size.y)), Color(0.85, 0.65, 0.3))
		bar.draw_rect(rect, Color(0.45, 0.33, 0.17), false, 1.0))
	return bar


## Значок навыка или пассивки из атласа (шаг 11.18); нет в атласе — пустое место того же размера.
func _icon_rect(icon: StringName, side: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = ItemIcon.texture(icon)
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.texture_filter = ItemIcon.FILTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # текст уже переведён через tr()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _choose(card_id: StringName) -> void:
	hide()
	_set_paused(false)
	_stored = []
	_chose_at = Time.get_ticks_msec()
	Sound.play_ui(&"magic")  # выбор карты навыка или руны (шаг 11.13)
	# Отложенно: хост сразу может прислать следующее предложение, а эта кнопка ещё в обработке сигнала.
	_world.upgrades.submit_choice.call_deferred(card_id)


func _reroll() -> void:
	if visible and not reroll_button.disabled:
		_world.upgrades.submit_reroll.call_deferred()


## Хост пришлёт карты заново (одна заменена); до тех пор повторно изгнать нельзя.
func _banish(index: int, card_id: StringName) -> void:
	if not visible or index >= _banish_buttons.size() or _banish_buttons[index].disabled:
		return
	for button in _banish_buttons:
		button.disabled = true
	_world.upgrades.submit_banish.call_deferred(card_id)


## Esc при открытом окне в кооперативе — «выбрать позже» (раньше, чем его заберёт меню паузы).
func _input(event: InputEvent) -> void:
	if visible and deferred() and event.is_action_pressed(&"ui_cancel") \
			and not _world.is_ui_open(PauseMenu.PAUSE_REASON):
		get_viewport().set_input_as_handled()
		defer_offer()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not visible:
		# Отложенный выбор: R открывает ждущее предложение, если не открыто другое окно (меню, инвентарь, торговец).
		if event.physical_keycode == DEFER_KEY and deferred() and has_offer() and not _world.input_blocked():
			get_viewport().set_input_as_handled()
			open_offer()
		return
	if _world.is_ui_open(PauseMenu.PAUSE_REASON):
		return
	if event.physical_keycode == DEFER_KEY and deferred():
		get_viewport().set_input_as_handled()
		defer_offer()
		return
	if event.physical_keycode == REROLL_KEY:
		get_viewport().set_input_as_handled()
		_reroll()
		return
	var index: int = event.physical_keycode - KEY_1
	if index < 0 or index >= _card_buttons.size():
		return
	get_viewport().set_input_as_handled()
	if event.shift_pressed:
		_banish_buttons[index].pressed.emit()
	else:
		_card_buttons[index].pressed.emit()


## Пауза только в одиночной игре: в сети остальные игроки продолжают бой.
func _set_paused(paused: bool) -> void:
	_world.request_pause(&"level_up", paused)
