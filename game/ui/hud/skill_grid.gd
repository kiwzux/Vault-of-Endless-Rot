class_name SkillGrid
extends Control
## Навыки героя в правой панели HUD (шаг 11.7, как ячейки умений в Halls of Torment): сетка 2 × 3 по числу
## слотов (UpgradeRules.max_weapons), пустые ячейки тоже видны. В ячейке — значок навыка (шаг 11.18, атлас ItemIcon;
## у эволюции — золотая рамка в самом значке), уровень и гнёзда рун снизу: в заполненном — значок руны (шаг 11.26,
## рунный камень с ободом по редкости; без атласа — точка цветом редкости), пустое — тёмная точка.
## Ступени эволюции — золотые метки сверху слева (взятые ярко, остальные тускло).
## Наведение — подсказка с названием, уровнем, ступенью и рунами. Экипировка и резонансы — в меню (вкладки «Герой» и «Навыки»).
## Эволюция навыка (новая ступень или облик) — вспышка ячейки на FLASH_TIME и сигнал evolved (баннер HUD).
## Перерисовывается, только когда сборка изменилась (и каждый кадр, пока вспышка); данные — синхронизация героя (ФТ-14).

signal evolved(skill: SkillData, stage: int)

const COLUMNS := 2
const CELL := 30.0
const GAP := 4.0
const PIP := 4.0
## Значок руны в гнезде и шаг гнёзд по низу ячейки.
const RUNE_ICON := 8.0
const RUNE_STEP := 9.0
const EVOLUTION_BORDER := Color(1.0, 0.7, 0.25)
const FLASH_TIME := 2.5
const EMPTY_PIP := Color(0.16, 0.13, 0.1)
const STAGE_PIP := 3.0
const EMPTY_STAGE := Color(0.3, 0.22, 0.1)
## Цвет руны по редкости (как рамка карты): обычная, редкая, эпическая, легендарная.
const RUNE_COLORS: Array[Color] = [Color(0.85, 0.82, 0.75), Color(0.4, 0.6, 1.0), Color(0.75, 0.4, 1.0), Color(1.0, 0.6, 0.15)]
const FONT_SIZE := 9

var player: Player
var _cells: Array = []
var _signature := 0
var _labels: Array = []
## Ступени эволюции, что уже видны в сетке (id навыка → ступень), и время вспышки: id → секунд осталось.
var _known_stages := {}
var _flash := {}
var _watched: Player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = ItemIcon.FILTER


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player != _watched:  # новый герой (начало забега, подключение): его эволюции не «новые»
		_watched = player
		_known_stages.clear()
		for skill in skills():
			_known_stages[skill.id] = player.evolution_stage(skill.id)
	var signature := hash([player.upgrade_levels, player.runes, player.evolution_stages])
	if signature != _signature:
		_signature = signature
		_check_evolutions()
		queue_redraw()
	if not _flash.is_empty():
		for id: StringName in _flash.keys():
			_flash[id] -= delta
			if _flash[id] <= 0.0:
				_flash.erase(id)
		queue_redraw()


## Новая эволюция в сборке (облик или ступень) — вспышка ячейки и сигнал (шаг 11.18).
func _check_evolutions() -> void:
	for skill in skills():
		var stage := player.evolution_stage(skill.id)
		var fresh := (skill.is_evolution and not _known_stages.has(skill.id)) \
				or stage > int(_known_stages.get(skill.id, stage))
		_known_stages[skill.id] = stage
		if fresh:
			_flash[skill.id] = FLASH_TIME
			evolved.emit(skill, stage)


## Навыки героя по порядку взятия (не больше слотов).
func skills() -> Array[SkillData]:
	var result: Array[SkillData] = []
	if player == null or not is_instance_valid(player):
		return result
	for id: StringName in player.upgrade_levels:
		var skill := DataRegistry.upgrade(id) as SkillData
		if skill != null and player.upgrade_levels[id] > 0:
			result.append(skill)
	return result


func _draw() -> void:
	_cells.clear()
	_labels.clear()
	var slot_style := get_theme_stylebox(&"panel", &"SlotPanel")
	var list := skills()
	var slots := maxi(DataRegistry.UPGRADE_RULES.max_weapons, list.size())
	for i in slots:
		@warning_ignore("integer_division")
		var rect := Rect2((i % COLUMNS) * (CELL + GAP), (i / COLUMNS) * (CELL + GAP), CELL, CELL)
		draw_style_box(slot_style, rect)
		if i < list.size():
			_draw_skill(rect, list[i])
	var font := get_theme_default_font()
	for label: Array in _labels:
		draw_string_outline(font, label[0], label[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color.BLACK)
	for label: Array in _labels:
		draw_string(font, label[0], label[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 0.95, 0.8))


func _draw_skill(rect: Rect2, skill: SkillData) -> void:
	var inner := rect.grow(-2.0)
	if not ItemIcon.draw_icon(self, inner, skill.icon_name()):  # без атласа — знак цветом навыка, как до шага 11.18
		var color := skill.icon_color
		draw_rect(inner, color.darkened(0.55))
		var c := inner.get_center() - Vector2(0, 2)
		var r := inner.size.x * 0.32
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)
		if skill.is_evolution:
			draw_rect(rect.grow(-1.0), EVOLUTION_BORDER, false, 1.5)
	if _flash.has(skill.id):
		_draw_flash(rect, 1.0 - _flash[skill.id] / FLASH_TIME)
	var level: int = player.upgrade_levels[skill.id]
	var text := str(level)
	var w := get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	_labels.append([Vector2(rect.end.x - w - 3.0, rect.position.y + 11.0), text])
	var socketed: Array = player.runes.get(skill.id, [])
	for i in DataRegistry.UPGRADE_RULES.runes_per_skill:
		var slot := Rect2(rect.position + Vector2(2.0 + i * RUNE_STEP, CELL - RUNE_ICON - 1.5), Vector2(RUNE_ICON, RUNE_ICON))
		var pip := Rect2(slot.get_center() + Vector2(-PIP, -PIP) * 0.5 + Vector2(0, 1.0), Vector2(PIP, PIP))
		var rune := DataRegistry.skill_modifier(StringName(str(socketed[i]))) if i < socketed.size() else null
		if rune == null:
			draw_rect(pip, EMPTY_PIP)
		elif not ItemIcon.draw_icon(self, slot, rune.icon_name()):
			draw_rect(pip, RUNE_COLORS[clampi(rune.rarity, 0, RUNE_COLORS.size() - 1)])
	var stage := player.evolution_stage(skill.id)
	var stages := DataRegistry.UPGRADE_RULES.evolution_stages
	for i in stages:
		var mark := Rect2(rect.position + Vector2(4.0 + i * (STAGE_PIP + 1.0), 4.0), Vector2(STAGE_PIP, STAGE_PIP))
		draw_rect(mark, EVOLUTION_BORDER if i < stage else EMPTY_STAGE)
	var tip := "%s · %s" % [tr(skill.name_key), tr("UPGRADE_LEVEL").format({"level": level})]
	if stage > 0:
		tip += "\n" + tr("SKILL_EVOLUTION_STAGE").format({"stage": UpgradePool.stage_name(stage),
				"max": UpgradePool.stage_name(stages)})
	var names := PackedStringArray()
	for id: Variant in socketed:
		var rune := DataRegistry.skill_modifier(StringName(str(id)))
		if rune != null:
			names.append(tr(rune.name_key))
	if not names.is_empty():
		tip += "\n" + tr("CARD_RUNES").format({"list": ", ".join(names)})
	_cells.append([rect, tip])


## Вспышка эволюции (t: 0 → 1): золотое сияние поверх значка и расходящиеся кольца, к концу гаснет.
func _draw_flash(rect: Rect2, t: float) -> void:
	var fade := 1.0 - t
	var pulse := 0.5 + 0.5 * sin(t * TAU * 4.0)
	draw_rect(rect, Color(1.0, 0.85, 0.4, 0.45 * fade * pulse))
	var c := rect.get_center()
	for k in 2:
		var phase := fmod(t * 2.0 + k * 0.5, 1.0)
		draw_arc(c, CELL * 0.5 + phase * 18.0, 0.0, TAU, 32, Color(1.0, 0.8, 0.3, (1.0 - phase) * fade), 2.0)
	draw_rect(rect.grow(1.0 + 2.0 * pulse), Color(EVOLUTION_BORDER, fade), false, 2.0)


func _get_tooltip(at_position: Vector2) -> String:
	for cell: Array in _cells:
		if (cell[0] as Rect2).has_point(at_position):
			return cell[1]
	return ""
