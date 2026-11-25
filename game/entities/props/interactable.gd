class_name Interactable
extends MapObject
## Интерактивная точка карты из данных (шаг 8, InteractableData): святилище, алтарь проклятий, разрушаемое,
## лор, пленник. Место решает карта CVAE (LevelFlow), что делает — данные и вид поведения.
## - святилище, алтарь проклятий, пленник — клавиша E: хост проверяет и вызывает activate (MapObject);
## - разрушаемое — касание: хост замечает героя рядом (_interact);
## - лор — клавиша E у самого игрока: текст показывается локально, хосту ничего не шлётся;
## - треснувшая стена тайника (шаг 9) — клавиша E: удар по стене; после wall_hits ударов клетка становится полом
##   (World.set_cell_tile), за ней — бонусная комната, иногда со стражей.
## used, stage и hits синхронизирует game/net (World/Props); событие для баннеров — Events.interactable_used.

enum Stage { IDLE, GUARDED, DONE }

## Стража встаёт кольцом такого радиуса вокруг клетки пленника, px.
const GUARD_RING := 44.0
const SCATTER := 10.0
## Треснувшая стена: E работает от края стены (клетка 96 px), трещины видны ближе этого, px.
const WALL_REACH := 66.0
const WALL_REVEAL := 220.0
const NO_ROOM := Vector2i(-1, -1)
## Обломки разрушаемого по виду (шаг 11.20, предметы атласа PropArt).
const DEBRIS := {&"barrel": &"debris_wood", &"coffin": &"debris_wood", &"urn": &"debris_stone",
		&"reliquary": &"debris_stone", &"hoard": &"debris_gold", &"golden_bucket": &"debris_gold"}

@export var data_id: StringName
## Лор: какая запись здесь лежит (LoreData).
@export var lore_id: StringName
## Пленник: ждёт, стража бьётся, освобождён.
@export var stage := Stage.IDLE:
	set(value):
		stage = value
		refresh_art()
		queue_redraw()
## Треснувшая стена: сколько ударов уже нанесено.
@export var hits := 0:
	set(value):
		if value > hits:
			_shake = 1.0
		hits = value
		queue_redraw()
## Треснувшая стена: середина тайника за ней (клетка; нужна хосту, чтобы поставить стражу).
var room_cell := NO_ROOM

var data: InteractableData
## Шаг 11.20: свет из данных (сфера святилища, марево алтаря проклятий) — слой поверх спрайта PropArt.
var _overlay: Node2D
var _guards: Array[Enemy] = []
var _time := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


## Фабрика для хоста и для spawn_function. null — неизвестная точка или запись (данные могли прийти по сети).
static func create(spawn: Dictionary) -> Interactable:
	var info := DataRegistry.interactable(StringName(str(spawn.get("type", ""))))
	if info == null:
		return null
	var lore := StringName(str(spawn.get("lore", "")))
	if info.kind == InteractableData.Kind.LORE and DataRegistry.lore(lore) == null:
		return null
	var node := Interactable.new()
	node.data_id = info.id
	node.lore_id = lore
	node.object_id = int(spawn.get("id", 0))
	node.requires_key = info.kind != InteractableData.Kind.BREAKABLE
	var room: Variant = spawn.get("room", NO_ROOM)
	node.room_cell = room if room is Vector2i else NO_ROOM
	return node


func _ready() -> void:
	data = DataRegistry.interactable(data_id)
	super()
	interact_radius = 14.0 if data.kind == InteractableData.Kind.BREAKABLE else 26.0
	if data.kind == InteractableData.Kind.SECRET_WALL:
		interact_radius = WALL_REACH
		z_index = 1  # трещины поверх лицевой стороны стены
	_rng.seed = hash([RunConfig.run_seed, GameState.level_index, object_id, "interactable"])
	if data.kind == InteractableData.Kind.PRISONER:
		set_physics_process(multiplayer.is_server())
	if _art != null and data.kind in [InteractableData.Kind.SHRINE, InteractableData.Kind.CURSE_ALTAR]:
		_overlay = Node2D.new()
		_overlay.draw.connect(_draw_overlay)
		add_child(_overlay)


func _process(delta: float) -> void:
	super(delta)
	_time += delta
	if data.kind in [InteractableData.Kind.SHRINE, InteractableData.Kind.CURSE_ALTAR] and not used:
		queue_redraw()
		if _overlay != null:
			_overlay.queue_redraw()
	if data.kind == InteractableData.Kind.SECRET_WALL and (_shake > 0.0 or not used):
		_shake = maxf(0.0, _shake - delta * 4.0)
		queue_redraw()


func _physics_process(delta: float) -> void:
	if data.kind == InteractableData.Kind.PRISONER:
		_watch_guards()
		return
	super(delta)


## Лор читается у самого игрока: окно с текстом, запись в «Летопись» (Events.lore_read). Остальное — как у MapObject.
func _unhandled_input(event: InputEvent) -> void:
	if data == null or data.kind != InteractableData.Kind.LORE:
		super(event)
		return
	if _world == null or not event.is_action_pressed(&"interact"):
		return
	var player := _world.local_player()
	if player != null and player.alive and in_reach(player) and not _world.input_blocked():
		get_viewport().set_input_as_handled()
		LorePanel.open(_world, DataRegistry.lore(lore_id), self)
		Events.lore_read.emit(lore_id)


# --- Хост ---

func activate(player: Player) -> bool:
	match data.kind:
		InteractableData.Kind.SHRINE:
			for p in _world.director.players_alive():
				if p == player or p.global_position.distance_to(global_position) <= data.share_radius:
					p.add_buff(data.id, data.buff_time, data.buff_stats)
			used = true
		InteractableData.Kind.CURSE_ALTAR:
			_world.waves.add_level_curse(data.curse_health, data.curse_damage, data.curse_reward)
			used = true
		InteractableData.Kind.PRISONER:
			if stage != Stage.IDLE:
				return false
			_call_guards(global_position)
			stage = Stage.GUARDED
		InteractableData.Kind.SECRET_WALL:
			hits += 1
			if hits < data.wall_hits:
				return true  # стена ещё держится: событие — только на пролом
			used = true
			stage = Stage.DONE
			_world.set_cell_tile(_world.director.world_to_cell(global_position), Palette.Tile.FLOOR)
			if room_cell != NO_ROOM and _rng.randf() < data.guard_chance:
				_call_guards(_world.director.cell_center(room_cell))
		_:
			return false
	Events.interactable_used.emit(data.id, player.peer_id(), _outcome())
	return true


## Разрушаемое: касание героя — обломки, добыча, иногда засада.
func _interact(player: Player, _delta: float) -> void:
	if data.kind != InteractableData.Kind.BREAKABLE:
		return
	used = true
	var pos := global_position
	var economy := _world.economy
	economy.drop_gold(pos, economy.roll_gold(data.gold))
	if _rng.randf() < data.potion_chance:
		_world.spawn_pickup({"kind": Pickup.Kind.POTION, "pos": pos + _scatter()})
	if _rng.randf() < data.item_chance:
		_world.loot.drop_item(pos + _scatter(), data.item_rarity)
	for i in data.xp_gems:
		_world.upgrades.drop_xp(pos + _scatter(), 1)
	if data.ambush_id != &"" and _rng.randf() < data.ambush_chance:
		var ambusher := DataRegistry.enemy(data.ambush_id)
		if ambusher != null:
			_world.waves.spawn_enemy(ambusher, pos, [], _world.waves.wave_stage())
	Events.interactable_used.emit(data.id, player.peer_id(), &"broken")


## Пленник и тайник: стража — элиты текущей волны кольцом вокруг center.
func _call_guards(center: Vector2) -> void:
	var waves := _world.waves
	for i in data.guard_count:
		var at := center + Vector2.RIGHT.rotated(TAU * i / data.guard_count) * GUARD_RING
		if _world.is_blocked(at):
			at = center
		var guard := waves.spawn_enemy(waves.pick_current_enemy(), at, waves.elite_affixes(data.guard_affixes), waves.wave_stage())
		if guard != null:
			_guards.append(guard)


## Стража перебита — пленник свободен и награждает: золото и предмет не ниже reward_rarity.
func _watch_guards() -> void:
	if stage != Stage.GUARDED:
		return
	for guard in _guards:
		if is_instance_valid(guard) and not guard.dead:
			return
	stage = Stage.DONE
	used = true
	var economy := _world.economy
	economy.drop_gold(global_position, economy.roll_gold(data.reward_gold))
	_world.loot.drop_item(global_position + _scatter(), data.reward_rarity)
	Events.interactable_used.emit(data.id, 0, &"freed")


func guards_left() -> int:
	return _guards.filter(func(g: Enemy) -> bool: return is_instance_valid(g) and not g.dead).size()


func _outcome() -> StringName:
	match data.kind:
		InteractableData.Kind.SHRINE: return &"shrine"
		InteractableData.Kind.CURSE_ALTAR: return &"cursed"
		InteractableData.Kind.PRISONER: return &"guards"
		InteractableData.Kind.SECRET_WALL: return &"secret"
	return &"used"


func _scatter() -> Vector2:
	return Vector2(_rng.randf_range(-SCATTER, SCATTER), _rng.randf_range(-SCATTER, SCATTER))


# --- Подсказка и облик ---

func prompt_text(_player: Player, near: bool) -> String:
	var title := tr(data.name_key)
	match data.kind:
		InteractableData.Kind.SHRINE:
			var lines := PackedStringArray()
			for stat: StringName in data.buff_stats:
				lines.append(ItemRoller.stat_line(stat, data.buff_stats[stat]))
			var effect := tr("SHRINE_EFFECT").format({"stats": ", ".join(lines), "time": roundi(data.buff_time)})
			return tr("INTERACT_PROMPT").format({"name": title, "effect": effect}) if near else title
		InteractableData.Kind.CURSE_ALTAR:
			var effect := tr("CURSE_ALTAR_EFFECT").format({"health": roundi(data.curse_health * 100),
					"reward": roundi(data.curse_reward * 100)})
			return tr("INTERACT_PROMPT").format({"name": title, "effect": effect}) if near else title
		InteractableData.Kind.PRISONER:
			if stage == Stage.GUARDED:
				return tr("PRISONER_FIGHT")
			return tr("INTERACT_PROMPT").format({"name": title, "effect": tr("PRISONER_EFFECT")}) if near else title
		InteractableData.Kind.LORE:
			var lore := DataRegistry.lore(lore_id)
			return tr("LORE_PROMPT").format({"title": tr(lore.title_key)}) if near else ""
		InteractableData.Kind.SECRET_WALL:
			var effect := tr("SECRET_WALL_EFFECT").format({"hits": hits, "total": data.wall_hits})
			return tr("INTERACT_PROMPT").format({"name": title, "effect": effect}) if near else ""
	return ""


func prompt_color(_player: Player) -> Color:
	return data.color.lightened(0.3) if data.kind != InteractableData.Kind.LORE else PROMPT_COLOR


## Предмет атласа объектов по виду точки и состоянию (шаг 11.20); тайник в стене — только трещины кодом.
func art_id() -> StringName:
	match data.kind:
		InteractableData.Kind.SHRINE:
			return &"shrine_used" if used else &"shrine"
		InteractableData.Kind.CURSE_ALTAR:
			return &"curse_altar_used" if used else &"curse_altar"
		InteractableData.Kind.BREAKABLE:
			var look := data.look if data.look != &"" else &"barrel"
			return DEBRIS.get(look, &"debris_wood") if used else look
		InteractableData.Kind.LORE:
			var lore := DataRegistry.lore(lore_id)
			return StringName("lore_" + String(lore.look if lore != null else &"inscription"))
		InteractableData.Kind.PRISONER:
			return &"prisoner_open" if stage == Stage.DONE else &"prisoner"
	return &""


## Свет поверх спрайта: сфера святилища цвета из данных, марево над алтарём проклятий.
func _draw_overlay() -> void:
	if used:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	if data.kind == InteractableData.Kind.SHRINE:
		var orb := Vector2(0, -22.5)
		_overlay.draw_circle(orb, 9.0 + 2.0 * pulse, Color(data.color, 0.16))
		_overlay.draw_circle(orb, 3.2 + 0.4 * pulse, data.color)
		_overlay.draw_circle(orb + Vector2(-0.9, -1.0), 1.0, Color(1, 1, 1, 0.85))
	else:
		_overlay.draw_circle(Vector2(0, -12), 14.0 + 3.0 * pulse, Color(data.color, 0.12))


func _draw() -> void:
	if data == null or (_art != null and data.kind != InteractableData.Kind.SECRET_WALL):
		return
	match data.kind:
		InteractableData.Kind.SHRINE: _draw_shrine()
		InteractableData.Kind.CURSE_ALTAR: _draw_curse_altar()
		InteractableData.Kind.BREAKABLE: _draw_breakable()
		InteractableData.Kind.LORE: _draw_lore()
		InteractableData.Kind.PRISONER: _draw_prisoner()
		InteractableData.Kind.SECRET_WALL: _draw_secret_wall()


func _draw_shrine() -> void:
	var stone := Color(0.42, 0.4, 0.42)
	draw_rect(Rect2(-9, -4, 18, 8), stone.darkened(0.3))
	draw_rect(Rect2(-5, -22, 10, 19), stone)
	draw_rect(Rect2(-7, -25, 14, 4), stone.lightened(0.15))
	var glow := data.color if not used else Color(0.3, 0.3, 0.32)
	var pulse := 0.5 + 0.5 * sin(_time * 3.0) if not used else 0.0
	draw_circle(Vector2(0, -14), 3.5 + pulse, glow)
	if not used:
		draw_circle(Vector2(0, -14), 10.0 + 2.0 * pulse, Color(glow, 0.18))


func _draw_curse_altar() -> void:
	var stone := Color(0.22, 0.16, 0.18)
	draw_rect(Rect2(-12, -10, 24, 12), stone)
	draw_rect(Rect2(-14, -13, 28, 4), stone.lightened(0.15))
	draw_circle(Vector2(0, -16), 4.0, Color(0.85, 0.82, 0.72))  # череп
	draw_rect(Rect2(-2, -17, 1, 2), Color.BLACK)
	draw_rect(Rect2(1, -17, 1, 2), Color.BLACK)
	if not used:
		var pulse := 0.5 + 0.5 * sin(_time * 2.0)
		draw_circle(Vector2(0, -6), 18.0 + 3.0 * pulse, Color(data.color, 0.16))
		for x in [-10.0, 10.0]:
			draw_line(Vector2(x, -13), Vector2(x, -22 - 3.0 * pulse), data.color, 1.5)


func _draw_breakable() -> void:
	var c := data.color
	if used:
		for piece: Rect2 in [Rect2(-7, 1, 5, 3), Rect2(2, 2, 6, 2), Rect2(-2, -2, 4, 3), Rect2(5, -3, 3, 3)]:
			draw_rect(piece, c.darkened(0.4))
		return
	match data.look:
		&"urn":
			draw_colored_polygon(PackedVector2Array([Vector2(-3, -12), Vector2(3, -12), Vector2(6, -6), Vector2(5, 2),
					Vector2(-5, 2), Vector2(-6, -6)]), c)
			draw_rect(Rect2(-4, -14, 8, 2), c.darkened(0.3))
			draw_line(Vector2(-5, -5), Vector2(5, -5), c.lightened(0.3), 1.0)
		&"coffin":
			draw_colored_polygon(PackedVector2Array([Vector2(-4, -14), Vector2(4, -14), Vector2(7, -9), Vector2(5, 4),
					Vector2(-5, 4), Vector2(-7, -9)]), c)
			draw_line(Vector2(0, -12), Vector2(0, -4), c.lightened(0.4), 1.0)
			draw_line(Vector2(-3, -9), Vector2(3, -9), c.lightened(0.4), 1.0)
		&"hoard":  # груда золота с кубком
			draw_colored_polygon(PackedVector2Array([Vector2(-13, 3), Vector2(-8, -5), Vector2(-1, -9), Vector2(7, -6),
					Vector2(13, 3)]), c.darkened(0.25))
			for coin: Vector2 in [Vector2(-8, 0), Vector2(-3, -5), Vector2(3, -3), Vector2(8, 0), Vector2(0, 1), Vector2(-5, 2)]:
				draw_circle(coin, 2.0, c)
				draw_circle(coin + Vector2(-0.5, -0.5), 0.8, c.lightened(0.5))
			draw_rect(Rect2(1, -15, 5, 4), c.lightened(0.15))  # кубок
			draw_rect(Rect2(3, -11, 1, 3), c.darkened(0.2))
			draw_circle(Vector2(-6, -8), 1.6, Color(0.8, 0.2, 0.25))  # самоцвет
		&"reliquary":  # серебряный ларец с сиянием
			var pulse := 0.5 + 0.5 * sin(_time * 2.5)
			draw_circle(Vector2(0, -6), 12.0 + 2.0 * pulse, Color(c, 0.15))
			draw_rect(Rect2(-8, -10, 16, 11), c.darkened(0.35))
			draw_rect(Rect2(-9, -13, 18, 4), c)
			draw_rect(Rect2(-1, -10, 2, 6), Color(0.95, 0.85, 0.4))
			draw_line(Vector2(-8, -4), Vector2(8, -4), c.lightened(0.3), 1.0)
		_:
			draw_rect(Rect2(-6, -12, 12, 14), c)
			for y in [-10.0, -3.0]:
				draw_rect(Rect2(-6, y, 12, 1.5), Color(0.3, 0.3, 0.32))


func _draw_lore() -> void:
	var lore := DataRegistry.lore(lore_id)
	match lore.look if lore != null else &"inscription":
		&"book":
			draw_rect(Rect2(-2, -10, 4, 12), Color(0.3, 0.2, 0.12))
			draw_rect(Rect2(-9, -14, 8, 6), Color(0.85, 0.78, 0.6))
			draw_rect(Rect2(1, -14, 8, 6), Color(0.8, 0.72, 0.55))
		&"corpse":
			draw_colored_polygon(PackedVector2Array([Vector2(-10, 0), Vector2(8, -2), Vector2(10, 2), Vector2(-9, 3)]),
					Color(0.4, 0.32, 0.25))
			draw_circle(Vector2(-11, 0), 3.0, Color(0.85, 0.82, 0.72))
			draw_rect(Rect2(2, -6, 5, 4), Color(0.85, 0.78, 0.6))  # записка
		_:
			draw_rect(Rect2(-8, -18, 16, 20), Color(0.38, 0.36, 0.4))
			for y in [-14.0, -10.0, -6.0]:
				draw_line(Vector2(-5, y), Vector2(5, y), Color(0.75, 0.65, 0.4), 1.0)


func _draw_prisoner() -> void:
	var iron := Color(0.35, 0.33, 0.32)
	draw_circle(Vector2(0, -6), 4.0, Color(0.8, 0.65, 0.5))  # пленник
	draw_rect(Rect2(-3, -3, 6, 8), Color(0.45, 0.35, 0.28))
	if stage == Stage.DONE:
		draw_rect(Rect2(-12, 4, 24, 2), iron)
		return
	for x in [-10.0, -5.0, 0.0, 5.0, 10.0]:
		draw_line(Vector2(x, -16), Vector2(x, 5), iron, 1.5)
	draw_rect(Rect2(-12, -18, 24, 3), iron)
	draw_rect(Rect2(-12, 4, 24, 2), iron)


## Треснувшая стена: тонкие трещины по лицевой стороне (их больше с каждым ударом), заметнее, когда свой герой
## рядом; после пролома — угловатые обломки на месте стены.
func _draw_secret_wall() -> void:
	var half := Palette.tile_size() / 2.0
	var stone := data.color
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([object_id, "cracks"])
	if used:
		for i in 7:
			var at := Vector2(rng.randf_range(-half * 0.6, half * 0.6), rng.randf_range(-half * 0.2, half * 0.6))
			var r := rng.randf_range(2.5, 5.0)
			var rock := PackedVector2Array()
			for k in 5:
				rock.append(at + Vector2.RIGHT.rotated(TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)) * r * rng.randf_range(0.7, 1.2))
			draw_colored_polygon(rock, stone.darkened(rng.randf_range(0.15, 0.45)))
			rock.append(rock[0])
			draw_polyline(rock, Color(0.08, 0.07, 0.06, 0.8), 0.6)
		return
	var player := _world.local_player() if _world != null else null
	var near := 0.0 if player == null else clampf(1.0 - global_position.distance_to(player.global_position) / WALL_REVEAL, 0.0, 1.0)
	var alpha := 0.3 + 0.6 * near
	var origin := Vector2(rng.randf_range(-6.0, 6.0), half * 0.25) + Vector2(sin(_time * 70.0), cos(_time * 53.0)) * 1.5 * _shake
	var branches := 3 + hits * 2
	for b in branches:
		var p := origin
		var angle := TAU * b / branches + rng.randf_range(-0.5, 0.5)
		for s in rng.randi_range(3, 5):
			var q := p + Vector2.RIGHT.rotated(angle + rng.randf_range(-0.7, 0.7)) * rng.randf_range(3.0, 6.0)
			draw_line(p, q, Color(0.06, 0.05, 0.04, alpha), 0.8)
			p = q
	if _shake > 0.0:  # пыль от удара
		for i in 6:
			var at := origin + Vector2(rng.randf_range(-half * 0.6, half * 0.6), half * 0.3 - _shake * rng.randf_range(6.0, 20.0))
			draw_circle(at, 1.0 + 1.5 * _shake, Color(stone, 0.45 * _shake))
