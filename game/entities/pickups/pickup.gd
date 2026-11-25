class_name Pickup
extends Node2D
## Подбираемое: кристалл опыта, Ключ босса, предмет экипировки (CR-07), монеты и зелье в пояс (CR-14).
## Подбор считает хост. Кристалл и монеты притягиваются к живому игроку в радиусе притяжения;
## Ключ, предмет и зелье надо подобрать самому — подойти вплотную (предмет — только если в сумке
## есть место, зелье — если в поясе есть место). Магнит душ (Vacuum из Vampire Survivors) тоже надо
## подобрать самому: тогда весь опыт уровня летит к этому герою, где бы ни лежал.

## Новые виды — только в конец: число уходит в spawn-данные по сети.
enum Kind { XP, KEY, ITEM, GOLD, POTION, MAGNET }

const SCENE_PATH := "res://entities/pickups/pickup.tscn"
const FLY_SPEED := 240.0
const COLLECT_DISTANCE := 6.0
## Ключ не притягивается пассивкой «Притяжение»: к нему надо подойти.
const KEY_RADIUS := 20.0
const ITEM_RADIUS := 12.0
const GOLD_COLOR := Color(1.0, 0.8, 0.25)
const POTION_COLOR := Color(0.85, 0.15, 0.2)
const MAGNET_COLOR := Color(0.55, 0.85, 1.0)
const MAGNET_RADIUS := 16.0
## Ключ босса крупнее прочих значков: его ищут глазами.
const KEY_ICON_SCALE := 1.3
## Притянутый Магнитом душ кристалл летит быстрее: через всю карту — за несколько секунд.
const PULL_SPEED := 720.0
## Лежащее ищет подбирающего героя раз во столько тиков (шаг 5): за 3 тика герой проходит ~5 px,
## а кристаллов на земле — сотни.
const SEARCH_EVERY := 3

@export var kind := Kind.XP
@export var value := 1
## Kind.ITEM: предмет (словарь ItemRoller).
@export var item := {}

var _target: Player
var _label: Label
## Значок предмета, зелья или Ключа (шаг 11.15); null — рисунок кодом (тело-многоугольник).
var _icon: Sprite2D
## Кристалл опыта или золото из атласа объектов (шаг 11.20); null — рисунок кодом.
var _art: PropArt
var _pulled := false
var _collected := false
var _world: World
var _time := 0.0

@onready var body: Polygon2D = $Body


## Фабрика для хоста и для spawn_function. null — неизвестный вид или испорченный предмет
## (данные могли прийти по сети).
static func create(data: Dictionary) -> Pickup:
	var kind_id: int = data.get("kind", Kind.XP)
	if kind_id not in Kind.values():
		return null
	if kind_id == Kind.ITEM and not ItemRoller.is_valid(data.get("item")):
		return null
	var pickup: Pickup = load(SCENE_PATH).instantiate()
	pickup.kind = kind_id as Kind
	pickup.position = data.get("pos", Vector2.ZERO)
	pickup.value = maxi(int(data.get("value", 1)), 1)
	if kind_id == Kind.ITEM:
		pickup.item = data["item"]
	return pickup


func _ready() -> void:
	_world = World.of(self)
	match kind:
		Kind.KEY:
			if not _set_icon(DataRegistry.VISUAL.key_icon, KEY_ICON_SCALE):
				body.polygon = PackedVector2Array([
					Vector2(-6, -3), Vector2(-2, -6), Vector2(2, -3), Vector2(8, -3), Vector2(8, 0),
					Vector2(6, 0), Vector2(6, 2), Vector2(4, 2), Vector2(4, 0), Vector2(2, 0), Vector2(-2, 1),
				])
				body.color = Color(1.0, 0.8, 0.25)
		Kind.ITEM:
			if not _set_icon(ItemRoller.icon_of(item)):
				body.polygon = PackedVector2Array([Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)])
				body.color = DataRegistry.item_base(item["base"]).icon_color
			_add_item_label()
			_apply_loot_filter()
			Settings.loot_filter_changed.connect(_apply_loot_filter)
			if Settings.shows_loot(_rarity()):
				LootSound.play(self, _rarity())
			var config := DataRegistry.VISUAL
			if _rarity() >= config.loot_light_min_rarity:  # редкий лут светится цветом редкости (шаг 11.8)
				LightSources.add(self, Color(ItemRoller.rarity_color(item), config.loot_light_energy),
						config.loot_light_radius, LightSources.Rank.PROP)
		Kind.GOLD:  # шаг 11.20: монета, горсть или кучка из атласа объектов; без атласа — кружок
			_art = PropArt.attach(body, _gold_art(value))
			if _art == null:
				var r := 2.5 + minf(value / 8.0, 2.5)  # кучка побольше — монета крупнее
				var points := PackedVector2Array()
				for i in 8:
					points.append(Vector2.RIGHT.rotated(TAU * i / 8.0) * r)
				body.polygon = points
				body.color = GOLD_COLOR
				queue_redraw()
		Kind.POTION:
			if not _set_icon(DataRegistry.VISUAL.potion_icon):
				body.polygon = PackedVector2Array([
					Vector2(-1.5, -6), Vector2(1.5, -6), Vector2(1.5, -3), Vector2(4, 0), Vector2(3, 4),
					Vector2(-3, 4), Vector2(-4, 0), Vector2(-1.5, -3),
				])
				body.color = POTION_COLOR
		Kind.MAGNET:  # сфера душ: ядро и кольцо, отблеск рисует _draw
			var points := PackedVector2Array()
			for i in 10:
				points.append(Vector2.RIGHT.rotated(TAU * i / 10.0) * 4.5)
			body.polygon = points
			body.color = MAGNET_COLOR
			queue_redraw()
		_:  # шаг 11.20: гранёный кристалл опыта цвета ценности; без атласа — ромб
			_art = PropArt.attach(body, _xp_art(value))
			if _art == null:
				body.polygon = PackedVector2Array([Vector2(0, -4), Vector2(3, 0), Vector2(0, 4), Vector2(-3, 0)])
				body.color = _xp_color(value)
	set_physics_process(multiplayer.is_server())


func _draw() -> void:
	if kind == Kind.ITEM:
		_draw_item()
	elif kind == Kind.GOLD and _art == null:
		draw_circle(Vector2.ZERO, 6.0, Color(GOLD_COLOR, 0.15))
	elif kind == Kind.MAGNET:
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		draw_circle(body.position, 11.0 + 3.0 * pulse, Color(MAGNET_COLOR, 0.12 + 0.1 * pulse))
		draw_arc(body.position, 7.5, _time * 2.0, _time * 2.0 + TAU * 0.7, 16, Color(1, 1, 1, 0.8), 1.2)
		draw_circle(body.position, 1.8, Color(1, 1, 1, 0.9))


## Предмет (шаг 7): отблеск цветом редкости, как в Diablo; редкий сияет ярче, легендарный — столб света,
## проклятый — пульсирующее тёмно-красное сияние. Со значком (шаг 11.15) под предметом — тень, без значка — рамка
## цвета редкости. Скрытый фильтром лута — без сияния (значок полупрозрачный, _apply_loot_filter).
func _draw_item() -> void:
	var c := ItemRoller.rarity_color(item)
	var rarity := _rarity()
	if _icon != null:
		draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.45))
		draw_set_transform(Vector2.ZERO)
	if not Settings.shows_loot(rarity):
		if _icon == null:
			draw_rect(Rect2(-6, -6, 12, 12), Color(c, 0.35), false, 1.0)
		return
	if _icon == null:
		draw_rect(Rect2(-7, -7, 14, 14), c, false, 1.5)
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	match rarity:
		ItemRoller.Rarity.RARE:
			draw_circle(Vector2.ZERO, 14.0, Color(c, 0.18))
		ItemRoller.Rarity.LEGENDARY:
			draw_circle(Vector2.ZERO, 16.0, Color(c, 0.2 + 0.1 * pulse))
			for i in 6:  # столб света: чем выше, тем прозрачнее
				var width := 6.0 - i * 0.6
				draw_rect(Rect2(-width / 2.0, -10.0 - i * 9.0, width, 9.0), Color(c.lightened(0.2), (0.45 - i * 0.07) * (0.7 + 0.3 * pulse)))
		ItemRoller.Rarity.CURSED:
			draw_circle(Vector2.ZERO, 13.0 + 3.0 * pulse, Color(0.35, 0.02, 0.08, 0.35))
			draw_arc(Vector2.ZERO, 10.0 + 2.0 * pulse, _time, _time + TAU * 0.6, 12, Color(c, 0.8), 1.0)
		_:
			draw_circle(Vector2.ZERO, 12.0, Color(c, 0.12))


func _rarity() -> int:
	return int(item.get("rarity", 0))


## Свет предмета (LightMap): скрытый фильтром лута не светит.
func light_scale() -> float:
	return 1.0 if Settings.shows_loot(_rarity()) else 0.0


func _apply_loot_filter() -> void:
	var shown := Settings.shows_loot(_rarity())
	if _label != null:
		_label.visible = shown
	body.modulate = Color.WHITE if shown else Color(1, 1, 1, 0.45)
	set_process(_rarity() >= ItemRoller.Rarity.LEGENDARY and shown)
	queue_redraw()


func _process(delta: float) -> void:
	if kind == Kind.ITEM:  # сияние легендарного и проклятого
		_time += delta
		queue_redraw()
		return
	if kind == Kind.KEY or kind == Kind.POTION or kind == Kind.MAGNET:
		_time += delta
		body.position.y = sin(_time * 4.0) * 2.0
		if kind == Kind.MAGNET:
			queue_redraw()


func _physics_process(delta: float) -> void:
	var started := PerfProbe.begin()
	_follow(delta)
	PerfProbe.add(&"pickups", started)


func _follow(delta: float) -> void:
	if _collected:
		return
	var search := (Engine.get_physics_frames() + get_instance_id()) % SEARCH_EVERY == 0
	if kind == Kind.ITEM or kind == Kind.POTION or kind == Kind.MAGNET:
		var taker := _find_collector() if search else null
		if taker != null:
			_target = taker
			_collect()
		return
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		_pulled = false
		_target = _find_collector() if search else null
		if _target == null:
			return
	global_position = global_position.move_toward(_target.global_position, (PULL_SPEED if _pulled else FLY_SPEED) * delta)
	if global_position.distance_to(_target.global_position) <= COLLECT_DISTANCE:
		_collect()


func _find_collector() -> Player:
	for p in _world.director.players_alive():
		var reach := p.pickup_radius()
		if kind == Kind.KEY:
			reach = KEY_RADIUS
		elif kind == Kind.ITEM:
			reach = ITEM_RADIUS
			if not p.can_receive(item):
				continue
		elif kind == Kind.POTION:
			reach = ITEM_RADIUS
			if p.potions >= Player.BELT_SIZE:
				continue
		elif kind == Kind.MAGNET:
			reach = MAGNET_RADIUS
		if global_position.distance_to(p.global_position) <= reach:
			return p
	return null


func _collect() -> void:
	match kind:
		Kind.XP:
			_world.upgrades.grant_xp(_target, value)
		Kind.KEY:
			_world.flow.on_key_collected(_target)
		Kind.ITEM:
			if not _world.loot.give(_target, item):
				return
		Kind.GOLD:
			_world.economy.collect_gold(_target, value)
		Kind.POTION:
			if _target.potions >= Player.BELT_SIZE:
				return
			_target.potions += 1
		Kind.MAGNET:
			for node in _world.pickups.get_children():
				if node is Pickup:
					(node as Pickup).attract(_target)
	_collected = true
	queue_free()


## Хост: предел кристаллов на земле (UpgradeSystem.drop_xp) — опыт нового кристалла добавляется к этому.
## false — кристалл уже летит к герою или подобран. Цвет крупного кристалла меняется только у хоста:
## клиенту value не нужен — опыт начисляет хост.
func absorb(amount: int) -> bool:
	if kind != Kind.XP or _collected or (_target != null and is_instance_valid(_target)):
		return false
	value += amount
	body.color = _xp_color(value)
	if _art != null:
		_art.set_prop(_xp_art(value))
	return true


## Магнит душ: кристалл опыта летит к герою, где бы ни лежал. with_gold — и золото (победа над боссом уровня).
func attract(player: Player, with_gold: bool = false) -> void:
	if (kind == Kind.XP or with_gold and kind == Kind.GOLD) and not _collected:
		_target = player
		_pulled = true


func _add_item_label() -> void:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = ItemRoller.display_name(item)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", ItemRoller.rarity_color(item))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.size = Vector2(120, 12)
	label.position = Vector2(-60, -20)
	LightMap.lift_label(label)
	add_child(label)
	_label = label


## Значок из атласа предметов (ItemIcon) вместо рисунка кодом: дочерний спрайт тела — качается вместе с ним.
## false — значка нет в атласе.
func _set_icon(icon: StringName, size_scale := 1.0) -> bool:
	var texture := ItemIcon.texture(icon)
	if texture == null:
		return false
	_icon = Sprite2D.new()
	_icon.texture = texture
	_icon.texture_filter = ItemIcon.FILTER
	_icon.scale = Vector2.ONE * DataRegistry.VISUAL.ground_icon_size * size_scale / texture.get_width()
	body.add_child(_icon)
	return true


## Кристалл опыта в атласе объектов (шаг 11.20): синий, зелёный, красный — пороги те же, что у цвета.
static func _xp_art(amount: int) -> StringName:
	return &"xp_3" if amount >= 5 else (&"xp_2" if amount >= 2 else &"xp_1")


## Золото: монета, горсть, кучка.
static func _gold_art(amount: int) -> StringName:
	return &"gold_3" if amount >= 12 else (&"gold_2" if amount >= 4 else &"gold_1")


static func _xp_color(amount: int) -> Color:
	if amount >= 5:
		return Color(0.9, 0.3, 0.3)
	if amount >= 2:
		return Color(0.35, 0.85, 0.45)
	return Color(0.35, 0.6, 1.0)
