class_name TalentsWindow
extends HubWindow
## Алтарь душ (CR-04, шаг 10.3): таланты выбранного героя за души, ранги-«камни», сброс талантов класса.
## Герой — тот, что стоит в Убежище (выбран у статуи Зала героев).

const PIP_SIZE := Vector2(6, 8)
const PIP_GAP := 2.0
const PIP_ON := Color(0.95, 0.72, 0.28)
const PIP_OFF := Color(0.22, 0.17, 0.12)
const PIP_BORDER := Color(0.5, 0.36, 0.18)
const GLOBAL_COLOR := Color(0.95, 0.78, 0.4)
const CLASS_COLOR := Color(0.86, 0.8, 0.68)

## Талант, на котором стоит фокус: после покупки фокус возвращается на ту же строку.
var _focus_talent: StringName = &""
var _detail: Label
var _rows: VBoxContainer


func build() -> void:
	var hero := sanctuary.hero
	set_title(tr("HUB_ALTAR_TITLE").format({"hero": tr(hero.name_key)}))
	var souls := HubWindow.make_label(tr("HUB_SOULS").format({"souls": MetaProfile.souls}), 11, SOUL_COLOR)
	body.add_child(souls)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	body.add_child(HubWindow.make_scroll(_rows))
	var focus_target: Control = null
	var any_class_rank := false
	for talent in DataRegistry.talents_for(hero):
		var row := _talent_row(talent, hero)
		_rows.add_child(row)
		if talent.id == _focus_talent:
			focus_target = row.get_child(row.get_child_count() - 1)
		if not talent.is_global() and MetaProfile.rank(talent, hero) > 0:
			any_class_rank = true
	_detail = HubWindow.make_label(tr("HUB_TALENT_HINT"), 9, Color(0.7, 0.64, 0.52))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(WRAP_WIDTH, 30)
	body.add_child(_detail)
	var respec := Button.new()
	respec.text = "HUB_RESPEC"
	respec.add_theme_font_size_override("font_size", 9)
	respec.size_flags_horizontal = Control.SIZE_SHRINK_END
	respec.disabled = not any_class_rank
	respec.pressed.connect(_on_respec_pressed)
	body.add_child(respec)
	if focus_target != null:
		focus_target.grab_focus.call_deferred()


func _talent_row(talent: TalentData, hero: HeroData) -> HBoxContainer:
	var rank := MetaProfile.rank(talent, hero)
	var cost := MetaProfile.next_cost(talent, hero)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.mouse_entered.connect(_show_talent.bind(talent))

	var icon := ColorRect.new()
	icon.color = talent.icon_color
	icon.custom_minimum_size = Vector2(8, 8)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var title := HubWindow.make_label(tr(talent.name_key), 10, GLOBAL_COLOR if talent.is_global() else CLASS_COLOR)
	title.custom_minimum_size = Vector2(104, 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(title)

	var pips := Control.new()
	pips.custom_minimum_size = Vector2(talent.max_rank * (PIP_SIZE.x + PIP_GAP), PIP_SIZE.y)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.draw.connect(func() -> void:
		for i in talent.max_rank:
			var rect := Rect2(Vector2(i * (PIP_SIZE.x + PIP_GAP), 0), PIP_SIZE)
			pips.draw_rect(rect, PIP_ON if i < rank else PIP_OFF)
			pips.draw_rect(rect, PIP_BORDER, false, 1.0))
	row.add_child(pips)

	var button := Button.new()
	button.custom_minimum_size = Vector2(92, 0)
	button.add_theme_font_size_override("font_size", 10)
	button.text = tr("HUB_UPGRADE").format({"souls": cost}) if cost > 0 else tr("HUB_MAXED")
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.disabled = cost <= 0 or MetaProfile.souls < cost
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(_upgrade.bind(talent))
	button.focus_entered.connect(_show_talent.bind(talent))
	button.mouse_entered.connect(_show_talent.bind(talent))
	row.add_child(button)
	return row


func _show_talent(talent: TalentData) -> void:
	var rank := MetaProfile.rank(talent, sanctuary.hero)
	_detail.text = "%s — %s\n%s" % [
		tr(talent.name_key),
		tr("HUB_TALENT_RANK").format({"rank": rank, "max": talent.max_rank}),
		tr(talent.description_key).format({"value": rank_value(talent)}),
	]


## Прибавка за один ранг в виде для текста: проценты — ×100.
static func rank_value(talent: TalentData) -> String:
	var def := DataRegistry.stat_def(talent.stat)
	var value := talent.per_rank * (100.0 if def != null and def.is_percent() else 1.0)
	return ("%.1f" % value).trim_suffix(".0")


func _upgrade(talent: TalentData) -> void:
	_focus_talent = talent.id
	if MetaProfile.upgrade(talent, sanctuary.hero):
		sanctuary.refresh_status()
		refresh.call_deferred()  # кнопка ещё в обработке сигнала


func _on_respec_pressed() -> void:
	var refund := MetaProfile.respec(sanctuary.hero)
	sanctuary.show_notice(tr("HUB_RESPEC_DONE").format({"souls": refund}))
	sanctuary.refresh_status()
	refresh.call_deferred()
