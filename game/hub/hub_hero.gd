class_name HubHero
extends CharacterBody2D
## Герой в Убежище (шаг 10.3): ходит по залу, анимация покоя и ходьбы из листа героя (SheetLayout), 8 направлений.
## Боевой логики Player здесь нет: герой только ходит между станциями. Пока открыто окно станции, стоит (blocked).
## В кооперативе (14.10.2026) герои других участников — тоже HubHero с remote: без ввода, камеры и столкновений,
## плавно догоняют присланную позицию (Net.hub_state_received), над головой — подпись.

## Шаг в Убежище быстрее, чем в бою: зал — место выбора, а не испытание.
const WALK_SPEED := 140.0
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
## Чужой герой догоняет присланную позицию за ~1/FOLLOW с; дальше TELEPORT_DISTANCE — сразу встаёт на место.
const FOLLOW := 12.0
const TELEPORT_DISTANCE := 160.0

var hero: HeroData
var blocked := false
## Герой другого участника кооператива: его ведёт сеть, а не клавиатура.
var remote := false
## Куда идёт чужой герой (последняя присланная позиция).
var target := Vector2.ZERO
## Подпись над чужим героем («Игрок 2»).
var tag := ""

var _layout: SheetLayout
var _anim_time := 0.0
## Пройденный путь, px: кадр ходьбы — путь / шаг листа (как у Player).
var _walked := 0.0
var _last_position := Vector2.ZERO
## Куда смотрит (8 направлений, шаг 11.11): угол на экране и блок листа. В зале герой встречает игрока лицом.
var _facing := 90.0
var _dir := 0

@onready var body: Sprite2D = $Body
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	set_hero(hero if hero != null else DataRegistry.HEROES[0])
	if remote:
		camera.enabled = false
		collision_layer = 0
		collision_mask = 0
		target = position
		var label := Label.new()
		label.text = tag
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
		label.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.02))
		label.add_theme_constant_override("outline_size", 3)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(80, 12)
		label.position = Vector2(-40, -body.get_rect().size.y * body.scale.y - 4.0)
		add_child(label)


## Сменить облик: герой встаёт у статуи другим классом.
func set_hero(p_hero: HeroData) -> void:
	hero = p_hero
	body.texture = hero.sprite_sheet
	_layout = SheetLayout.of(hero.sprite_sheet)
	if _layout != null:
		_layout.apply_to(body)
		_dir = _layout.facing(_facing, body.flip_h)[0]
		body.frame = _layout.frame(ANIM_IDLE, 0, 0, _dir)


func set_camera_limits(bounds: Rect2i) -> void:
	camera.limit_left = bounds.position.x
	camera.limit_top = bounds.position.y
	camera.limit_right = bounds.end.x
	camera.limit_bottom = bounds.end.y


func _physics_process(delta: float) -> void:
	if remote:
		var before := position
		position = target if position.distance_to(target) > TELEPORT_DISTANCE \
				else position.lerp(target, minf(FOLLOW * delta, 1.0))
		velocity = (position - before) / maxf(delta, 0.001)  # для анимации ходьбы
		return
	var direction := Vector2.ZERO
	if not blocked:
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = direction * WALK_SPEED
	move_and_slide()


func _process(delta: float) -> void:
	if _layout == null:
		return
	_anim_time += delta
	var step := position - _last_position
	_last_position = position
	var moving := velocity.length() > 1.0
	if moving:
		_walked += step.length()
		_facing = SheetLayout.turn(_facing, velocity)
		var facing := _layout.facing(_facing, body.flip_h)
		_dir = facing[0]
		body.flip_h = facing[1]
		body.frame = _layout.frame(ANIM_WALK, int(_walked / _layout.world_stride()), 0, _dir)
	else:
		body.frame = _layout.frame_at(ANIM_IDLE, _anim_time, _dir)
