class_name PropArt
extends Sprite2D
## Облик объекта карты в стиле игры (шаг 11.20): порталы, сундуки, статуя, испытания, фонтан, обелиск, торговцы,
## святилища, разрушаемое, лор, клетка пленника, кристаллы опыта и золото — кадры из атласа art/gen_props.py
## (res://assets/props/props.png + props.json), объёмные модели как реквизит Убежища. Спрайт с областью атласа и
## зацикленной анимацией; точка опоры кадра — на полу под предметом, в позиции узла.
## Состояние объекта — другой предмет атласа (chest → chest_open): set_prop. Предмета нет в атласе — объект рисует
## себя кодом, как до шага 11.20 (has_prop).

const PATH := "res://assets/props/props.json"

static var _texture: Texture2D
static var _props := {}
static var _layouts := {}
static var _loaded := false

var prop_id: StringName
var _layout: SheetLayout
var _time := 0.0


static func has_prop(id: StringName) -> bool:
	_ensure_loaded()
	return _props.has(String(id))


## Свет предмета из атласа (предметы обстановки с огнём, шаг 11.29): [цвет "#rrggbb", энергия, радиус px мира,
## x, y — точка от опоры px мира]; у предмета без огня — пусто.
static func light_of(id: StringName) -> Array:
	_ensure_loaded()
	var entry: Variant = _props.get(String(id), {}).get("light")
	return entry if entry is Array and (entry as Array).size() == 5 else []


static func layout_of(id: StringName) -> SheetLayout:
	_ensure_loaded()
	if not _layouts.has(id) and _props.has(String(id)):
		_layouts[id] = SheetLayout.from_dict(_props[String(id)])
	return _layouts.get(id)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if not (parsed is Dictionary):
		push_warning("PropArt: нет атласа объектов %s (art/gen_props.py)" % PATH)
		return
	_texture = load(PATH.get_base_dir().path_join(String(parsed["atlas"])))
	_props = parsed["props"]


## Спрайт предмета id, дочерний узел parent; null — предмета нет в атласе. random_phase — сдвиг анимации,
## чтобы одинаковые предметы не мигали в такт.
static func attach(parent: Node, id: StringName, random_phase := 0.0) -> PropArt:
	if not has_prop(id):
		return null
	var art := PropArt.new()
	art._time = random_phase
	art.texture = _texture
	art.region_enabled = true
	art.centered = false
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.set_prop(id)
	parent.add_child(art)
	return art


## Сменить предмет (состояние объекта); нет такого в атласе — прежний остаётся.
func set_prop(id: StringName) -> void:
	var layout := layout_of(id)
	if layout == null or id == prop_id:
		return
	prop_id = id
	_layout = layout
	offset = -layout.anchor
	scale = Vector2.ONE * layout.scale
	region_rect = layout.region(layout.frame_at(&"idle", _time))
	set_process(layout.count(&"idle") > 1)


## Высота предмета над полом, px мира: над ней — подписи.
func height() -> float:
	return _layout.height * _layout.scale if _layout != null else 0.0


func _process(delta: float) -> void:
	_time += delta
	region_rect = _layout.region(_layout.frame_at(&"idle", _time))
