class_name HubProp
extends Sprite2D
## Реквизит Убежища в духе Diablo (шаг 11.12): костёр, портал, стол кооператива, летопись, доска заданий —
## кадры из атласа art/gen_hub.py (res://assets/hub/hub_props.png + hub_props.json). Предмет — Sprite2D с областью
## атласа и зацикленной анимацией (огонь, свечи); точка опоры кадра — на полу под предметом, в позиции узла.
## Данные станции (тело, высота подсказки, радиус «нажать E») лежат в том же JSON: новый предмет — без правки кода.

const PATH := "res://assets/hub/hub_props.json"

static var _texture: Texture2D
static var _props := {}
static var _loaded := false

var _layout: SheetLayout
var _time := 0.0


## Есть ли у предмета кадры в атласе.
static func has_prop(prop_id: StringName) -> bool:
	_ensure_loaded()
	return _props.has(String(prop_id))


## Данные предмета из JSON: body_half [x, y], prompt_height, reach (px мира); нет — пустой словарь.
static func info(prop_id: StringName) -> Dictionary:
	_ensure_loaded()
	return _props.get(String(prop_id), {})


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if not (parsed is Dictionary):
		push_warning("HubProp: нет атласа реквизита %s (art/gen_hub.py)" % PATH)
		return
	_texture = load(PATH.get_base_dir().path_join(String(parsed["atlas"])))
	_props = parsed["props"]


## Предмет prop_id; random_phase — сдвиг анимации, чтобы одинаковые свечи не мигали в такт.
static func make(prop_id: StringName, random_phase := 0.0) -> HubProp:
	_ensure_loaded()
	var prop := HubProp.new()
	prop._time = random_phase
	if _props.has(String(prop_id)):
		prop._layout = SheetLayout.from_dict(_props[String(prop_id)])
		prop.texture = _texture
		prop.region_enabled = true
		prop.centered = false
		prop.offset = -prop._layout.anchor
		prop.scale = Vector2.ONE * prop._layout.scale
		prop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		prop.region_rect = prop._layout.region(prop._layout.frame(&"idle", 0))
	return prop


func _ready() -> void:
	set_process(_layout != null and _layout.count(&"idle") > 1)


func _process(delta: float) -> void:
	_time += delta
	region_rect = _layout.region(_layout.frame_at(&"idle", _time))
