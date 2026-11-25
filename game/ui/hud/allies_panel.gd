class_name AlliesPanel
extends Control
## Союзники в кооперативе (DESIGN 4): портрет героя, уровень и полоска здоровья — слева под сборкой.
## Павший союзник — серым, вместо здоровья полоска «Последнего вздоха» (сколько осталось простоять
## рядом, чтобы его поднять). Свой герой здесь не показывается: у него сферы внизу экрана.
## В одиночной игре панель пустая и места не занимает. Перерисовывается, только когда что-то изменилось.

const ROW := 20.0
const PORTRAIT := 16.0
const BAR := Vector2(70, 4)
const FRAME := Color(0.45, 0.33, 0.17)
const BACK := Color(0.06, 0.045, 0.04, 0.9)
const HEALTH := Color(0.8, 0.15, 0.12)
const REVIVE := Color(0.55, 1.0, 0.65)
const TEXT := Color(1.0, 0.94, 0.8)
const FALLEN_TEXT := Color(0.6, 0.65, 0.75)
const FONT_SIZE := 8

var world: World
var _signature := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # портрет из листа 96 px уменьшается — без мерцания пикселей


func _process(_delta: float) -> void:
	var rows := _rows()
	var signature := hash(rows)
	if signature != _signature:
		_signature = signature
		custom_minimum_size.y = ROW * rows.size()
		queue_redraw()


func allies() -> Array[Player]:
	var result: Array[Player] = []
	if world == null:
		return result
	var me := world.local_player()
	for p in world.get_players():
		if p != me and p.hero != null:
			result.append(p)
	return result


## Всё, что видно в строке союзника, — для сравнения «изменилось ли».
func _rows() -> Array:
	var rows: Array = []
	for p in allies():
		rows.append([p.peer_id(), p.hero.id, roundi(p.health), roundi(p.max_health), p.alive, p.level,
				snappedf(p.revive_progress, 0.02)])
	return rows


func _draw() -> void:
	var font := get_theme_default_font()
	var list := allies()
	for i in list.size():
		var p := list[i]
		var y := i * ROW
		var sheet := p.hero.sprite_sheet
		draw_rect(Rect2(0, y, PORTRAIT + 2.0, PORTRAIT + 2.0), FRAME)
		draw_rect(Rect2(1, y + 1, PORTRAIT, PORTRAIT), BACK)
		if sheet != null:  # голова и плечи из первого кадра покоя
			draw_texture_rect_region(sheet, Rect2(1, y + 1, PORTRAIT, PORTRAIT), p.hero.portrait_face_region(),
					Color.WHITE if p.alive else Color(0.55, 0.6, 0.75, 0.6))
		var text := "%s · %s" % [tr(p.hero.name_key), tr("HUD_LEVEL").format({"level": p.level})]
		if not p.alive:
			text += " · " + tr("HUD_ALLY_FALLEN")
		var pos := Vector2(PORTRAIT + 6.0, y + 8.0)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color.BLACK)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT if p.alive else FALLEN_TEXT)
		var bar := Rect2(PORTRAIT + 6.0, y + 12.0, BAR.x, BAR.y)
		draw_rect(bar.grow(1.0), BACK)
		var share := p.health / p.max_health if p.alive and p.max_health > 0.0 else p.revive_progress
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(share, 0.0, 1.0), bar.size.y)), HEALTH if p.alive else REVIVE)
		draw_rect(bar.grow(1.0), FRAME, false, 1.0)
