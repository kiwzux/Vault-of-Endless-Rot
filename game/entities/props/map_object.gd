class_name MapObject
extends Node2D
## Объект карты HoMM3 на метке LevelData (CR-06): ИИ решает, где он стоит, игровой код — что он делает.
## Два вида срабатывания:
##  - касание (фонтан, обелиск, место Грааля): хост сам замечает живого игрока в радиусе и вызывает _interact();
##  - клавиша E (requires_key: платный сундук, испытания): свой герой стоит рядом и жмёт E →
##    World.submit_interact → хост проверяет и вызывает activate(). Над объектом — подсказка.
## used — состояние хоста, game/net синхронизирует его клиентам; object_id — номер объекта на уровне.
## Облик (шаг 11.20) — спрайт PropArt из атласа art/gen_props.py по art_id(); код рисует только то, что меняется
## в игре (кольцо времени испытания, свет святилища), и прежний облик, если предмета нет в атласе.

const PROMPT_COLOR := Color(0.95, 0.9, 0.75)

@export var used := false:
	set(value):
		used = value
		refresh_art()
		queue_redraw()
@export var object_id := 0

var interact_radius := 16.0
## Срабатывает по клавише E, а не касанием. Задаётся в _init наследника.
var requires_key := false
var _world: World
var _prompt: Label
## Облик из атласа объектов (шаг 11.20, PropArt); null — объект рисует себя кодом.
var _art: PropArt


func _ready() -> void:
	_world = World.of(self)
	z_index = -1
	var id := art_id()
	if id != &"":
		_art = PropArt.attach(self, id, randf() * 4.0)
	set_physics_process(multiplayer.is_server() and not requires_key)
	if requires_key:
		_prompt = Label.new()
		_prompt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # текст уже переведён через tr()
		_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_prompt.add_theme_font_size_override("font_size", 8)
		_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
		_prompt.add_theme_constant_override("outline_size", 3)
		_prompt.size = Vector2(160, 12)
		_prompt.position = Vector2(-80, -maxf(36.0, _art.height() + 12.0) if _art != null else -36.0)
		LightMap.lift_label(_prompt)
		add_child(_prompt)


func _physics_process(delta: float) -> void:
	if used:
		return
	for p in _world.director.players_alive():
		if in_reach(p):
			_interact(p, delta)
			return
	_idle(delta)


func _process(_delta: float) -> void:
	if _prompt == null or _world == null:
		return
	var player := _world.local_player()
	_prompt.visible = not used and player != null and player.alive
	if _prompt.visible:
		var near := in_reach(player)
		_prompt.text = prompt_text(player, near)
		_prompt.add_theme_color_override("font_color", prompt_color(player))
		_prompt.modulate.a = 1.0 if near else 0.65


func _unhandled_input(event: InputEvent) -> void:
	if not requires_key or used or _world == null or not event.is_action_pressed(&"interact"):
		return
	var player := _world.local_player()
	if player != null and player.alive and in_reach(player) and not _world.input_blocked():
		get_viewport().set_input_as_handled()
		_world.submit_interact(object_id)


func in_reach(player: Player) -> bool:
	return global_position.distance_to(player.global_position) <= interact_radius


## Хост, касание: живой игрок в радиусе.
func _interact(_player: Player, _delta: float) -> void:
	pass


## Никого рядом.
func _idle(_delta: float) -> void:
	pass


## Хост, клавиша E: проверки World.apply_interact пройдены. false — объект отказал (не хватает золота).
func activate(_player: Player) -> bool:
	return false


## Подсказка над объектом для своего героя; near — стоит ли он рядом.
func prompt_text(_player: Player, _near: bool) -> String:
	return ""


func prompt_color(_player: Player) -> Color:
	return PROMPT_COLOR


## Предмет атласа объектов для нынешнего состояния (шаг 11.20); пусто — облика из атласа нет.
func art_id() -> StringName:
	return &""


## Состояние сменилось (used, у наследников — стадия, активность): другой предмет атласа.
func refresh_art() -> void:
	if _art != null:
		var id := art_id()
		_art.visible = id != &""
		if id != &"":
			_art.set_prop(id)


## Свет объекта (LightMap, шаг 11.8): использованный гаснет.
func light_scale() -> float:
	return DataRegistry.VISUAL.used_light_share if used else 1.0
