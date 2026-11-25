class_name SkillVfx
extends RefCounted
## Облик навыков героя (шаг 11.21): анимированные спрайты атласа эффектов art/gen_vfx.py (res://assets/vfx/vfx.png +
## vfx.json) — снаряды, взрывы, волны аур, взмахи, цепи, лучи, зоны, удары с неба, ловушки, рывки, вспышки выстрела
## и попадания по восьми стихиям. Эффект выбирается по виду снаряда или следа и стихии навыка (pick): у навыка
## с готовым действием и стихией облик появляется сам, без правки кода. Стихия — первый тег навыка вида ELEMENT
## (TagDef.Kind) или SkillData.fx_element.
##
## По сети уходит только id навыка (SkillRuntime): стихию, эволюцию и цвет каждый участник берёт из данных навыка.
## Атлас хранит цвет с предумножением на прозрачность — в одной картинке и свечение, и плотные предметы, поэтому
## рисуется материалом BLEND_MODE_PREMULT_ALPHA, а оттенок и прозрачность задаются через tint.
## Нет атласа или эффекта — снаряд и след рисуют себя кодом, как до шага 11.21.

const PATH := "res://assets/vfx/vfx.json"
## Стихия, если у навыка её нет, и запасная, если у эффекта нет варианта для стихии навыка.
const DEFAULT_ELEMENT := &"physical"


## Анимация атласа: кадры в ряд от origin, точка опоры, радиус круга в кадре (взрыв, зона, печать), px листа.
class Clip:
	var origin := Vector2.ZERO
	var size := Vector2.ONE
	var count := 1
	var fps := 1.0
	var anchor := Vector2.ZERO
	var loop := true
	var radius := 0.0

	func region(index: int) -> Rect2:
		return Rect2(origin + Vector2(size.x * clampi(index, 0, count - 1), 0.0), size)

	## Кадр по времени: зацикленная идёт по кругу, разовая останавливается на последнем.
	func index_at(time: float) -> int:
		var i := int(time * fps)
		return posmod(i, count) if loop else mini(maxi(i, 0), count - 1)

	## Кадр по доле прошедшего (0…1) у разового эффекта.
	func index_of(progress: float) -> int:
		return clampi(int(progress * count), 0, count - 1)

	## Длительность разового эффекта, с.
	func duration() -> float:
		return count / maxf(fps, 0.01)


## Что нужно облику от навыка: стихия, эволюция ли он (золотой блеск) и цвет следа.
class Look:
	var element := DEFAULT_ELEMENT
	var evolved := false
	var color := Color.WHITE


static var texture: Texture2D
static var material: CanvasItemMaterial
## Пиксель листа в мире, px.
static var scale := 0.5
static var _clips := {}
static var _picks := {}
static var _looks := {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if not (parsed is Dictionary):
		push_warning("SkillVfx: нет атласа эффектов %s (art/gen_vfx.py)" % PATH)
		return
	texture = load(PATH.get_base_dir().path_join(String(parsed["atlas"])))
	if texture == null:
		return
	scale = float(parsed.get("scale", 0.5))
	material = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var all: Dictionary = parsed["fx"]
	for id: String in all:
		var d: Dictionary = all[id]
		var clip := Clip.new()
		clip.origin = Vector2(d["origin"][0], d["origin"][1])
		clip.size = Vector2(d["frame"][0], d["frame"][1])
		clip.count = maxi(int(d.get("count", 1)), 1)
		clip.fps = maxf(float(d.get("fps", 1.0)), 0.01)
		clip.anchor = Vector2(d["anchor"][0], d["anchor"][1])
		clip.loop = bool(d.get("loop", true))
		clip.radius = float(d.get("radius", 0.0))
		_clips[StringName(id)] = clip


static func available() -> bool:
	_ensure_loaded()
	return texture != null


static func clip(id: StringName) -> Clip:
	_ensure_loaded()
	return _clips.get(id)


## Эффект семейства family для стихии element: «family_element», затем «family» (снаряд одного вида),
## затем «family_fallback». null — такого нет: рисуется код.
static func pick(family: String, element: StringName, fallback: StringName = DEFAULT_ELEMENT) -> Clip:
	_ensure_loaded()
	var key := "%s|%s|%s" % [family, element, fallback]
	if _picks.has(key):
		return _picks[key]
	var found: Clip = _clips.get(StringName("%s_%s" % [family, element]))
	if found == null:
		found = _clips.get(StringName(family))
	if found == null:
		found = _clips.get(StringName("%s_%s" % [family, fallback]))
	_picks[key] = found
	return found


## Облик навыка id; null — нет такого навыка (у врагов и в проверках без данных).
static func look_of(skill_id: StringName) -> Look:
	if skill_id == &"":
		return null
	if _looks.has(skill_id):
		return _looks[skill_id]
	var data := DataRegistry.upgrade(skill_id) as SkillData
	var look: Look = null
	if data != null:
		look = Look.new()
		look.element = element_of(data)
		look.evolved = data.is_evolution
		look.color = data.fx_color
	_looks[skill_id] = look
	return look


## Стихия навыка: своя (fx_element) или первый тег-стихия.
static func element_of(data: SkillData) -> StringName:
	if data.fx_element != &"":
		return data.fx_element
	for id in data.tags:
		var tag := DataRegistry.tag(id)
		if tag != null and tag.kind == TagDef.Kind.ELEMENT:
			return id
	return DEFAULT_ELEMENT


## Оттенок для материала с предумножением: color (обычно белый) с прозрачностью alpha.
static func tint(alpha: float, color := Color.WHITE) -> Color:
	var a := clampf(alpha, 0.0, 1.0)
	return Color(color.r * a, color.g * a, color.b * a, a)


## Кадр index клипа c: точка опоры — в pos, поворот rot, размер size (1 — как в атласе).
static func draw(ci: CanvasItem, c: Clip, index: int, pos: Vector2, rot := 0.0, size := 1.0, modulate := Color.WHITE) -> void:
	var k := scale * size
	if rot != 0.0:
		ci.draw_set_transform(pos, rot, Vector2(k, k))
		ci.draw_texture_rect_region(texture, Rect2(-c.anchor, c.size), c.region(index), modulate)
		ci.draw_set_transform(Vector2.ZERO)
	else:
		ci.draw_texture_rect_region(texture, Rect2(pos - c.anchor * k, c.size * k), c.region(index), modulate)


## Кадр круглого эффекта (взрыв, волна, зона, печать), подогнанный под радиус radius px мира.
static func draw_round(ci: CanvasItem, c: Clip, index: int, pos: Vector2, radius: float, rot := 0.0, modulate := Color.WHITE) -> void:
	var circle := c.radius if c.radius > 0.0 else c.size.x / 2.0
	draw(ci, c, index, pos, rot, radius / (circle * scale), modulate)


## Полоса взмаха c на секторе: от хвоста a_tail к голове a_head (рад), между радиусами r_in и r_out px мира;
## верх полосы (v = 0) — внешний край.
static func draw_arc_strip(ci: CanvasItem, c: Clip, index: int, center: Vector2, a_tail: float, a_head: float, r_in: float,
		r_out: float, modulate := Color.WHITE, segments := 14) -> void:
	var region := c.region(index)
	var tex_size := texture.get_size()
	var v_top := region.position.y / tex_size.y
	var v_bottom := region.end.y / tex_size.y
	var colors := PackedColorArray([modulate, modulate, modulate, modulate])
	var prev_out := Vector2.ZERO
	var prev_in := Vector2.ZERO
	var prev_u := 0.0
	for i in segments + 1:
		var k := float(i) / segments
		var dir := Vector2.from_angle(lerpf(a_tail, a_head, k))
		var outer := center + dir * r_out
		var inner := center + dir * r_in
		var u := (region.position.x + region.size.x * k) / tex_size.x
		if i > 0:
			ci.draw_primitive(PackedVector2Array([prev_out, outer, inner, prev_in]), colors,
					PackedVector2Array([Vector2(prev_u, v_top), Vector2(u, v_top), Vector2(u, v_bottom), Vector2(prev_u, v_bottom)]),
					texture)
		prev_out = outer
		prev_in = inner
		prev_u = u


## Полоса или плитка c, натянутая на четырёхугольник: from → to по длине (u), half — полуширина (v), px мира.
## u0…u1 — какая часть полосы по длине (плитки цепи и луча берут её целиком).
static func draw_quad(ci: CanvasItem, c: Clip, index: int, from: Vector2, to: Vector2, half: float, modulate := Color.WHITE,
		u0 := 0.0, u1 := 1.0) -> void:
	var along := to - from
	if along.length_squared() < 0.01:
		return
	var normal := along.orthogonal().normalized() * half
	var region := c.region(index)
	var tex_size := texture.get_size()
	var uv0 := (region.position + Vector2(region.size.x * u0, 0.0)) / tex_size
	var uv1 := (region.position + Vector2(region.size.x * u1, region.size.y)) / tex_size
	ci.draw_primitive(PackedVector2Array([from - normal, to - normal, to + normal, from + normal]),
			PackedColorArray([modulate, modulate, modulate, modulate]),
			PackedVector2Array([uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]), texture)
