class_name LightMap
extends Node2D
## Освещение уровня (шаг 11.8; техзадание, раздел 1: тёмный фон и точечный свет факелов, заклинаний, свечей).
## Карта света — маленький буфер (SubViewport) с текселем light_texel px мира (VisualConfig): буфер очищается
## в тьму биома (BiomeData.ambient_light), поверх сложением ложатся пятна света — радиальный градиент на каждый
## источник. Узел рисует буфер поверх мира с умножением: сцена × свет. Сотня источников — сотня спрайтов
## в буфере ~180×110 одним пакетом и один проход умножения на экран; теней от стен нет.
## Источники: подвижные (LightSources: герои, атаки, объекты карты, лут) и неподвижные (LevelLights: огонь
## на тайлах, опасные клетки). Каждый участник считает свет сам из того, что у него уже есть: по сети ничего не идёт.
## Низкое качество эффектов (Settings.effects_quality) выключает карту: уровень освещён целиком.

## Поверх мира, но под цифрами урона (DamageNumbers, z 100). Подписи над объектами — LABEL_Z, над светом.
const Z := 90
const LABEL_Z := 95

## Сколько источников нарисовано в последнем кадре и сколько неподвижных на уровне (для проверок).
var drawn := 0
var static_count := 0

static var _spot: Texture2D

var _buffer: SubViewport
var _canvas: Node2D
## Прямоугольник мира под картой света: экран с запасом, выровненный по текселю — свет не дрожит при сдвиге камеры.
var _rect := Rect2()
var _texel := 0
var _static := LevelLights.new()
var _ambient := Color.WHITE
## Подвижные источники кадра по рангам LightSources.Rank.
var _dynamic: Array = [[], [], []]
var _time := 0.0


## Подписать узел интерфейса в мире (подсказка у объекта, имя предмета) над картой света: тьма его не глушит.
static func lift_label(label: CanvasItem) -> void:
	label.z_as_relative = false
	label.z_index = LABEL_Z


func _ready() -> void:
	z_index = Z
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	process_priority = 100  # после камеры героя: прямоугольник экрана этого кадра
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material = multiply
	_buffer = SubViewport.new()
	_buffer.disable_3d = true
	_buffer.transparent_bg = true  # очищается в ноль; тьму биома кладёт первый прямоугольник
	_buffer.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	_buffer.size = Vector2i(8, 8)
	add_child(_buffer)
	_canvas = Node2D.new()
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_canvas.material = additive
	_canvas.draw.connect(_draw_lights)
	_buffer.add_child(_canvas)
	Events.level_loaded.connect(_on_level_loaded)
	Events.level_cell_changed.connect(_on_level_cell_changed)
	Settings.graphics_changed.connect(_apply_quality)
	_apply_quality()
	if GameState.current_level != null:
		_on_level_loaded(GameState.current_level)


func _on_level_loaded(level: LevelData) -> void:
	_static = LevelLights.collect(level)
	static_count = _static.size()
	var biome := LevelLights.biome_of(level)
	_ambient = biome.ambient_light if biome != null else Color.WHITE


## Проломлена стена тайника: огонь на тайлах вокруг клетки мог смениться (кромки стен).
func _on_level_cell_changed(_cell: Vector2i, _tile: int) -> void:
	_on_level_loaded(GameState.current_level)


func _apply_quality() -> void:
	_texel = DataRegistry.VISUAL.light_texel(Settings.effects_quality)
	var on := _texel > 0
	visible = on
	set_process(on)
	_buffer.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func is_on() -> bool:
	return _texel > 0


func _process(delta: float) -> void:
	var started := PerfProbe.begin()
	_time += delta
	var viewport := get_viewport()
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	var texel := float(_texel)
	var margin := Vector2.ONE * DataRegistry.VISUAL.light_margin
	var from := ((view.position - margin) / texel).floor() * texel
	var to := ((view.end + margin) / texel).ceil() * texel
	_rect = Rect2(from, to - from)
	var size := Vector2i((_rect.size / texel).round())
	if _buffer.size != size:
		_buffer.size = size
	_dynamic = LightSources.collect()
	_canvas.queue_redraw()
	queue_redraw()
	PerfProbe.add(&"lights", started)


func _draw() -> void:
	draw_texture_rect(_buffer.get_texture(), _rect, false)


## Буфер: тьма биома, затем пятна — герои и объекты, огонь уровня, атаки (по пределу max_lights).
func _draw_lights() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(_buffer.size)), _ambient)
	var config := DataRegistry.VISUAL
	var budget := config.max_lights(Settings.effects_quality)
	drawn = 0
	for rank in [LightSources.Rank.HERO, LightSources.Rank.PROP]:
		for light: Array in _dynamic[rank]:
			if drawn >= budget:
				return
			_spot_at(light[0], light[2], light[1])
	var wave := _time * config.flicker_speed
	for i in _static.size():
		if drawn >= budget:
			return
		var pulse := 1.0 + config.flicker * sin(wave + _static.phases[i])
		_spot_at(_static.positions[i], _static.radii[i], _static.colors[i] * pulse)
	for light: Array in _dynamic[LightSources.Rank.ATTACK]:
		if drawn >= budget:
			return
		_spot_at(light[0], light[2], light[1])


func _spot_at(at: Vector2, radius: float, color: Color) -> void:
	if at.x + radius < _rect.position.x or at.y + radius < _rect.position.y \
			or at.x - radius > _rect.end.x or at.y - radius > _rect.end.y:
		return
	var inv := 1.0 / _texel
	var r := radius * inv
	color.a = 1.0
	_canvas.draw_texture_rect(spot(), Rect2((at - _rect.position) * inv - Vector2(r, r), Vector2(r, r) * 2.0), false, color)
	drawn += 1


## Пятно света: ровное в середине, к краю мягко спадает до нуля.
static func spot() -> Texture2D:
	if _spot == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		_spot = texture
	return _spot
