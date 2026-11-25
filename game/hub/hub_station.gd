class_name HubStation
extends Node2D
## Станция Убежища (шаг 10.3): статуя класса, алтарь душ, доска заданий, летопись, врата бездны,
## стол кооператива, выход. Стоит твёрдым телом на пути героя. С шага 11.12 всё, кроме статуй, — объёмные модели
## из атласа реквизита (HubProp): тело, высота подсказки и радиус «нажать E» — из его данных. Статуя — лист героя
## в камне на постаменте, нарисованном кодом.
## Что делает станция по E, решает Sanctuary; здесь — облик и состояние (выбрана, закрыта, есть награда).

enum Kind { STATUE, ALTAR, BOARD, CHRONICLE, GATE, WAR_TABLE, EXIT }

const STONE := Color(0.36, 0.34, 0.36)
const STONE_DARK := Color(0.18, 0.16, 0.18)
const STONE_LIGHT := Color(0.52, 0.5, 0.5)
const BRONZE := Color(0.7, 0.52, 0.26)
const SOUL := Color(0.9, 0.22, 0.16)
const STATUE_TINT := Color(0.62, 0.62, 0.68)
const STATUE_LOCKED := Color(0.22, 0.22, 0.26)
const STATUE_SELECTED := Color(1.0, 0.86, 0.6)
## Статуя — тот же лист героя, но в камне: серый по яркости кадра, умноженный на tint.
## Один шейдер на все статуи; материал у каждой свой (6 статуй — 6 вызовов отрисовки, это немного).
## Статуя крупнее героя в STATUE_SCALE раз; точка опоры листа (на 3 px выше ступней) — над верхом постамента.
const STATUE_SCALE := 1.25
const STATUE_FEET := Vector2(0, -12)
const STONE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g) * tint.rgb, c.a * tint.a);
}
"""
## Твёрдое тело станции без реквизита: полуразмеры по видам, px (статуя — постамент).
const BODY_HALF := {Kind.STATUE: Vector2(11, 5)}
## Радиус «нажать E» по умолчанию, px от точки опоры (у крупного реквизита — свой, из данных).
const REACH := 34.0

var kind := Kind.ALTAR
var id: StringName
## Статуя: чей класс; закрыт ли он; стоит ли сейчас этот герой.
var hero: HeroData
var locked := false
var selected := false:
	set(value):
		selected = value
		_update_statue()
## Метка «!» над станцией: на доске есть награда.
var attention := false:
	set(value):
		attention = value
		queue_redraw()

var _time := 0.0
var _statue: Sprite2D
## Данные реквизита из атласа (HubProp.info); пусто — станция рисуется кодом.
var _prop := {}

static var _stone_shader: Shader


func _ready() -> void:
	_prop = HubProp.info(id)
	if not _prop.is_empty():
		add_child(HubProp.make(id))
	var half: Vector2 = Vector2(_prop["body_half"][0], _prop["body_half"][1]) if not _prop.is_empty() \
			else BODY_HALF.get(kind, Vector2.ZERO)
	if half != Vector2.ZERO:
		add_child(solid_body(half))
	if kind == Kind.STATUE and hero != null:
		_statue = Sprite2D.new()
		_statue.texture = hero.sprite_sheet
		var layout := SheetLayout.of(hero.sprite_sheet)
		if layout != null:
			layout.apply_to(_statue, STATUE_SCALE)
			_statue.frame = layout.frame(&"idle", 0, 0, layout.dir_index("s"))  # лицом к залу
		_statue.position = STATUE_FEET
		if _stone_shader == null:
			_stone_shader = Shader.new()
			_stone_shader.code = STONE_SHADER
		var material := ShaderMaterial.new()
		material.shader = _stone_shader
		_statue.material = material
		add_child(_statue)
		_update_statue()
	set_process(kind == Kind.BOARD)  # «!» над доской покачивается


## Твёрдое тело с полуразмерами half у точки опоры (основание предмета) — герой обходит станцию и костёр.
static func solid_body(half: Vector2) -> StaticBody2D:
	var solid := StaticBody2D.new()
	solid.collision_layer = PhysicsLayers.WORLD
	solid.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = half * 2.0
	shape.shape = rect
	shape.position = Vector2(0, -half.y)  # тело — над точкой опоры: основание предмета, а не перед ним
	solid.add_child(shape)
	return solid


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Высота станции над точкой опоры, px: над ней встаёт подсказка.
func height() -> float:
	if not _prop.is_empty():
		return float(_prop["prompt_height"])
	return 52.0 if kind == Kind.STATUE else 30.0


## Радиус «нажать E» от точки опоры, px.
func reach() -> float:
	return maxf(float(_prop.get("reach", REACH)), REACH)


func _update_statue() -> void:
	if _statue == null:
		return
	(_statue.material as ShaderMaterial).set_shader_parameter(&"tint",
			STATUE_LOCKED if locked else (STATUE_SELECTED if selected else STATUE_TINT))
	queue_redraw()


func _draw() -> void:
	if kind == Kind.STATUE:
		_draw_statue()
	if attention:
		var bob := sin(_time * 4.0) * 2.0
		draw_rect(Rect2(-2, -height() - 14 + bob, 4, 8), BRONZE)
		draw_rect(Rect2(-2, -height() - 4 + bob, 4, 3), BRONZE)


func _draw_statue() -> void:
	if selected:
		draw_circle(Vector2(0, 0), 16.0, Color(0.95, 0.7, 0.3, 0.18))
	draw_rect(Rect2(-12, -6, 24, 10), STONE_DARK)
	draw_rect(Rect2(-10, -8, 20, 4), STONE)
	draw_rect(Rect2(-12, 3, 24, 1), STONE_LIGHT)
	if locked:  # цепи крест-накрест
		for x in [-8.0, 8.0]:
			draw_line(Vector2(x, -44), Vector2(-x, -10), Color(0.4, 0.4, 0.44), 2.0)
