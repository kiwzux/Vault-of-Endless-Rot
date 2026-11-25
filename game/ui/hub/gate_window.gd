class_name GateWindow
extends HubWindow
## Врата бездны (шаг 10.3): герой, таланты которого уйдут в забег, переключатель «Хардкор», печати Скверны
## (шаг 12.3: сумма и награда, кнопка — окно печатей SealsWindow) и спуск.
## Забег начинается так же, как раньше из меню хаба: RunConfig.start_new_run → сцена уровня.

const HEAT_COLOR := Color(0.78, 0.45, 1.0)

var hardcore_toggle: CheckButton
var seals_button: Button


## «Скверна 7: души +70 %, редкий лут +28 %»; печатей нет — «Печати Скверны не наложены».
static func heat_text(chosen: Dictionary) -> String:
	var heat := SealData.heat_of(chosen)
	if heat <= 0:
		return tr_static("HUB_SEALS_NONE")
	var balance := DataRegistry.BALANCE
	return tr_static("HUB_SEALS_TOTAL").format({"heat": heat, "souls": roundi(balance.heat_souls_per_point * heat * 100.0),
			"loot": roundi(balance.heat_magic_find_per_point * heat * 100.0)})


func build() -> void:
	set_title(tr("HUB_GATE_TITLE"))
	body.add_child(HubWindow.hero_card(sanctuary.hero))
	var talents := MetaProfile.talents_for(sanctuary.hero)
	var ranks := 0
	for id: StringName in talents:
		ranks += int(talents[id])
	body.add_child(HubWindow.make_label(tr("HUB_GATE_TALENTS").format({"ranks": ranks}), 9, TEXT_COLOR))
	hardcore_toggle = CheckButton.new()
	hardcore_toggle.text = "HARDCORE"
	hardcore_toggle.button_pressed = sanctuary.hardcore
	body.add_child(hardcore_toggle)
	var hint := HubWindow.make_label(tr("HARDCORE_DESC"), 8, Color(0.85, 0.25, 0.18))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(WRAP_WIDTH, 0)
	hint.visible = sanctuary.hardcore
	body.add_child(hint)
	hardcore_toggle.toggled.connect(func(on: bool) -> void:
		sanctuary.hardcore = on
		hint.visible = on)
	var seals_row := HBoxContainer.new()
	seals_row.add_theme_constant_override("separation", 6)
	var heat := HubWindow.make_label(heat_text(sanctuary.seals), 9, HEAT_COLOR)
	heat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	seals_row.add_child(heat)
	seals_button = Button.new()
	seals_button.text = "HUB_SEALS_OPEN"
	seals_button.add_theme_font_size_override("font_size", 9)
	seals_button.pressed.connect(func() -> void:
		close_window()
		sanctuary.open_window(&"seals"))
	seals_row.add_child(seals_button)
	body.add_child(seals_row)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	var start := Button.new()
	start.text = "START_RUN"
	start.add_theme_color_override("font_color", Color(1, 0.88, 0.55))
	start.size_flags_horizontal = Control.SIZE_SHRINK_END
	start.pressed.connect(sanctuary.start_run)
	body.add_child(start)
	start.grab_focus.call_deferred()
