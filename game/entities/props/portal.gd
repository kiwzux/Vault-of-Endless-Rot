class_name Portal
extends Node2D
## Портал. NEXT — на метке EXIT: потухший, пока босс не убит; Ключ босса (ФТ-09) его зажигает,
## вход ведёт на следующий уровень (ФТ-07). После финального босса появляются два портала (CR-08):
## FINISH — завершить забег победой, CONTINUE — «Бесконечная гниль», следующий круг.
## Вход решает LevelFlow на хосте; active и mode синхронизирует game/net.
## Открытый портал видно издалека: столб света и подпись; путь к нему показывают миникарта
## и стрелка у края экрана (HUD). Облик (шаг 11.20) — каменная арка с черепом из атласа объектов (PropArt):
## потухшая тлеет, открытая — вихрь цвета вида.

enum Mode { NEXT, CONTINUE, FINISH }

const RADIUS := 12.0
const BEAM_HEIGHT := 70.0
const IDLE_COLOR := Color(0.35, 0.3, 0.42)
const MODE_COLORS: Array[Color] = [Color(0.75, 0.4, 1.0), Color(0.45, 0.85, 0.3), Color(1.0, 0.8, 0.35)]
const MODE_KEYS: PackedStringArray = ["PORTAL_NEXT", "PORTAL_CONTINUE", "PORTAL_FINISH"]

@export var mode := Mode.NEXT
@export var active := false:
	set(value):
		active = value
		if _label != null:
			_label.visible = active
		if _art != null:
			_art.set_prop(_art_id())
		queue_redraw()

## Предметы атласа объектов по виду (шаг 11.20): потухшая арка и вихрь цвета вида.
const ART_IDS: Array[StringName] = [&"portal_next", &"portal_continue", &"portal_finish"]

var _spin := 0.0
var _label: Label
## Арка портала из атласа (PropArt); null — портал рисуется кодом.
var _art: PropArt


func _art_id() -> StringName:
	return ART_IDS[mode] if active else &"portal"


func _ready() -> void:
	_art = PropArt.attach(self, _art_id())
	_label = Label.new()
	_label.text = MODE_KEYS[mode]  # ключ — Label переведёт сам
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", MODE_COLORS[mode])
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	_label.size = Vector2(120, 12)
	_label.position = Vector2(-60, -(_art.height() + 8.0) if _art != null else -RADIUS - 16.0)
	_label.visible = active
	LightMap.lift_label(_label)
	add_child(_label)


## Свет портала (LightMap, шаг 11.8): потухший едва тлеет.
func light_scale() -> float:
	return 1.0 if active else 0.3


func _process(delta: float) -> void:
	_spin += delta * (3.0 if active else 0.5)
	queue_redraw()


func _draw() -> void:
	var c := MODE_COLORS[mode] if active else IDLE_COLOR
	if active:  # столб света: видно поверх стен и толпы
		var pulse := 0.5 + 0.5 * sin(_spin * 1.5)
		draw_rect(Rect2(-RADIUS * 0.6, -BEAM_HEIGHT, RADIUS * 1.2, BEAM_HEIGHT), Color(c, 0.12 + 0.08 * pulse))
		draw_rect(Rect2(-RADIUS * 0.25, -BEAM_HEIGHT, RADIUS * 0.5, BEAM_HEIGHT), Color(c.lightened(0.4), 0.2 + 0.1 * pulse))
	if _art != null:  # арка и вихрь — спрайт (шаг 11.20); столб света позади него
		return
	draw_circle(Vector2.ZERO, RADIUS, Color(c, 0.25 if active else 0.12))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, c, 2.0)
	for i in 3:
		var a := _spin + TAU * i / 3.0
		draw_arc(Vector2.ZERO, RADIUS * 0.6, a, a + 1.2, 8, Color(c, 0.8), 1.5)
