class_name DamageNumbers
extends Node2D
## Всплывающие цифры урона над врагами (как в Diablo и Vampire Survivors). Удачный удар — крупнее
## и золотом. Все цифры рисуются одним узлом за один проход: при сотне попаданий в секунду это
## дешевле сотни Label. Источник — Events.damage_dealt хоста; game/net пересылает его клиентам.
## Отключается в настройках (Settings.show_damage_numbers).
## Надписи реакций статусов («Заморозка», «Взрыв масла») — тем же проходом, цветом реакции (шаг 2).

const LIFETIME := 0.7
const REACTION_LIFETIME := 1.1
const RISE := 18.0
const MAX_NUMBERS := 80
const FONT_SIZE := 8
const CRIT_FONT_SIZE := 11
const REACTION_FONT_SIZE := 10
const COLOR := Color(1.0, 0.95, 0.85)
const CRIT_COLOR := Color(1.0, 0.75, 0.2)

## Сколько цифр показано за всё время (для проверок).
var shown_total := 0

## [позиция, текст, возраст, время жизни, размер шрифта, цвет]
var _numbers: Array = []
var _font: Font


func _ready() -> void:
	z_index = 100
	z_as_relative = false
	# Шрифт заголовков темы (шаг 11.16: «Vault Grimoire»); без темы — встроенный.
	var theme := ThemeDB.get_project_theme()
	_font = theme.get_font(&"font", &"HeaderLabel") if theme != null and theme.has_font(&"font", &"HeaderLabel") \
			else ThemeDB.fallback_font
	Events.damage_dealt.connect(_on_damage_dealt)
	Events.status_reaction.connect(_on_status_reaction)


func _on_damage_dealt(pos: Vector2, amount: float, crit: bool) -> void:
	if not Settings.show_damage_numbers or amount <= 0.0:
		return
	var jitter := Vector2(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0))
	_push([pos + jitter, str(maxi(roundi(amount), 1)), 0.0, LIFETIME,
			CRIT_FONT_SIZE if crit else FONT_SIZE, CRIT_COLOR if crit else COLOR])
	shown_total += 1


func _on_status_reaction(pos: Vector2, reaction_id: StringName) -> void:
	for reaction: StatusReaction in DataRegistry.STATUS_REACTIONS:
		if reaction.id == reaction_id:
			_push([pos + Vector2(0, -8), tr(reaction.name_key), 0.0, REACTION_LIFETIME, REACTION_FONT_SIZE,
					reaction.color.lightened(0.25)])
			return


func _push(entry: Array) -> void:
	if _numbers.size() >= MAX_NUMBERS:
		_numbers.pop_front()
	_numbers.append(entry)


func _process(delta: float) -> void:
	if _numbers.is_empty():
		return
	for i in range(_numbers.size() - 1, -1, -1):
		var entry: Array = _numbers[i]
		entry[2] += delta
		if entry[2] >= entry[3]:
			_numbers.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for entry: Array in _numbers:
		var t: float = entry[2] / entry[3]
		var size: int = entry[4]
		var text: String = entry[1]
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos: Vector2 = entry[0] + Vector2(-width / 2.0, -RISE * t)
		var alpha := clampf((1.0 - t) * 2.0, 0.0, 1.0)
		var color: Color = entry[5]
		draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, alpha))
		draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, alpha))
