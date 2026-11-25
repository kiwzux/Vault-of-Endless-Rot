class_name HubHero
extends CharacterBody2D
## Герой в Убежище (шаг 10.3): ходит по залу, анимация покоя и ходьбы из листа героя (SheetLayout), 8 направлений.
## Боевой логики Player здесь нет: герой только ходит между станциями. Пока открыто окно станции, стоит (blocked).
## Шаг в Убежище быстрее, чем в бою: зал — место выбора, а не испытание.
const WALK_SPEED := 140.0
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
var hero: HeroData
var blocked := false
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


func _physics_process(_delta: float) -> void:
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
