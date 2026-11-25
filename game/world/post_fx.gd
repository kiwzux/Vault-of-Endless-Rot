class_name PostFx
extends Node2D
## Лёгкие пост-эффекты (шаг 11.10; техзадание, разделы 1 и 8): виньетка, красные края при ране своего героя
## и пульс при малом здоровье, хроматическая аберрация при ударе на малом здоровье. Отключаются в настройках
## (Settings.post_effects). Рисуется поверх мира в его координатах — на экран под камерой: над картой света (z 93),
## под подписями (LightMap.LABEL_Z) и цифрами урона; интерфейс (HUD) — отдельный слой поверх. Виньетка — одна
## текстура на экран; аберрация читает копию экрана (hint_screen_texture), поэтому видна только доли секунды.
## Только у себя: по сети ничего не идёт. Числа — VisualConfig (группа Post).

const Z := 93
const ABERRATION_Z := 99
const SHADER := preload("res://world/aberration.gdshader")

## Пульс раны и аберрации, 1 → 0.
var hurt := 0.0
var aberration := 0.0

static var _vignette: Texture2D

var _cooldown := 0.0
var _time := 0.0
var _rect := Rect2()
var _shift: Node2D
var _material: ShaderMaterial
var _world: World


func _ready() -> void:
	_world = World.of(self)
	z_index = Z
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	process_priority = 100  # после камеры героя, как LightMap
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_shift = Node2D.new()
	_shift.z_index = ABERRATION_Z
	_shift.z_as_relative = false
	_shift.material = _material
	_shift.visible = false
	_shift.draw.connect(func() -> void: _shift.draw_rect(_rect, Color.WHITE))
	add_child(_shift)
	Settings.graphics_changed.connect(_apply_settings)
	Events.level_loaded.connect(func(_level: LevelData) -> void: reset())
	_apply_settings()


func _apply_settings() -> void:
	visible = Settings.post_effects
	set_process(Settings.post_effects)
	if not Settings.post_effects:
		reset()


func reset() -> void:
	hurt = 0.0
	aberration = 0.0
	_shift.visible = false


## Рана своего героя (Juice.hero_hurt); health_share — сколько здоровья осталось.
func hero_hurt(health_share: float) -> void:
	if not Settings.post_effects:
		return
	hurt = 1.0
	var config := DataRegistry.VISUAL
	if health_share < config.low_health and _cooldown <= 0.0:
		aberration = 1.0
		_cooldown = config.aberration_cooldown


func _process(delta: float) -> void:
	var config := DataRegistry.VISUAL
	var viewport := get_viewport()
	_rect = viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	_time += delta
	_cooldown -= delta
	hurt = maxf(hurt - delta / config.hurt_pulse_time, 0.0)
	aberration = maxf(aberration - delta / config.aberration_time, 0.0)
	_shift.visible = aberration > 0.0
	if _shift.visible:
		_material.set_shader_parameter(&"amount", config.aberration * aberration)
		_shift.queue_redraw()
	queue_redraw()


func _draw() -> void:
	var config := DataRegistry.VISUAL
	var color := config.vignette
	var me := _world.local_player() if _world != null else null
	if me != null and me.alive and me.max_health > 0.0 and me.health < me.max_health * config.low_health:
		color = color.lerp(config.low_health_vignette, 0.5 + 0.5 * sin(_time * 4.0))  # сердце стучит
	if hurt > 0.0:
		color = color.lerp(config.hurt_vignette, hurt)
	draw_texture_rect(vignette_texture(), _rect, false, color)


## Края темнеют к углам; середина игрового поля между панелями HUD чистая.
static func vignette_texture() -> Texture2D:
	if _vignette == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 0.75, 1.0])  # за 1 (углы) — как на краю
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 1)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 128
		texture.height = 72
		_vignette = texture
	return _vignette
