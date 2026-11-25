class_name Minimap
extends Control
## Миникарта уровня: планировка из LevelData (её выдал CVAE) и метки поверх — герои, босс,
## порталы, Ключ, торговцы, неоткрытые сундуки, обелиски, статуя, фонтан, место Грааля, элиты.
## Картинка планировки строится при загрузке уровня и когда клетка карты сменилась (шаг 9: проломлена стена);
## метки рисуются каждый кадр по узлам контейнеров World/* — на клиентах они те же (их создают спавнеры game/net).
## Тайники (пол, недостижимый от точки появления) до пролома выглядят стеной — иначе миникарта их выдаёт.
## Шаг 11.29 — чёткая в высоком разрешении: UPSCALE пикселей на клетку, края стен скруглены (маска клеток растянута
## билинейно и обрезана посередине), по кромке пола — светлая линия, как на карте Diablo; пол — в тон биома, у стен
## темнее, с лёгким зерном; опасные клетки — свечением биома. Картинка рисуется с линейным фильтром.

const BORDER := Color(0.45, 0.33, 0.17)
const BACK := Color(0.02, 0.015, 0.01, 0.75)
const COLORS := {
	&"floor": Color(0.4, 0.34, 0.28, 0.92),
	&"wall": Color(0.09, 0.075, 0.06, 0.88),
	&"rim": Color(0.86, 0.76, 0.56, 1.0),
	&"hazard": Color(0.24, 0.42, 0.29, 0.95),
	&"void": Color(0, 0, 0, 0),
}
## Пикселей картинки на клетку карты (32 клетки → 256 px: чётко и в 2560×1440).
const UPSCALE := 8
## Полуширина кромки в долях маски (0…255): кромка — около 2 px картинки.
const RIM_BAND := 34
## Насколько тон биома (BiomeData.ambient_light) подкрашивает пол.
const BIOME_TINT := 0.4
const LOCAL_PLAYER := Color(1.0, 1.0, 1.0)
const ALLY := Color(0.45, 0.95, 0.55)
const BOSS := Color(1.0, 0.2, 0.15)
const MINI_BOSS := Color(1.0, 0.55, 0.2)
const ELITE := Color(0.45, 0.6, 1.0)
const KEY := Color(1.0, 0.85, 0.3)
const MERCHANT := Color(1.0, 0.78, 0.25)
const CHEST := Color(0.85, 0.6, 0.25)
const FOUNTAIN := Color(0.35, 0.85, 0.85)
const OBELISK := Color(0.95, 0.92, 0.78)
const STATUE := Color(0.7, 0.7, 0.75)

var world: World
var _texture: ImageTexture
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	Events.level_loaded.connect(_on_level_loaded)
	Events.level_cell_changed.connect(func(_cell: Vector2i, _tile: int) -> void: _on_level_loaded(GameState.current_level))
	if GameState.current_level != null:
		_on_level_loaded(GameState.current_level)


func has_map() -> bool:
	return _texture != null


func _on_level_loaded(level: LevelData) -> void:
	_texture = ImageTexture.create_from_image(render(level))
	queue_redraw()


## Картинка планировки UPSCALE × размер карты: маски клеток (проходимо, не пустота, опасно) растягиваются
## билинейно (C++), дальше — один проход по байтам: пустота прозрачна, середина маски — кромка, выше — пол, ниже — стена.
static func render(level: LevelData) -> Image:
	var n := level.size
	var walk := Image.create_empty(n, n, false, Image.FORMAT_L8)
	var inside := Image.create_empty(n, n, false, Image.FORMAT_L8)
	var lava := Image.create_empty(n, n, false, Image.FORMAT_L8)
	var spawn := level.find_first(Palette.Tile.PLAYER_SPAWN)
	var reach := LevelValidator.bfs(level, spawn) if spawn != LevelData.INVALID_CELL else PackedInt32Array()
	for y in n:
		for x in n:
			var cell := Vector2i(x, y)
			var id := level.get_tile(cell)
			var hidden := not reach.is_empty() and Palette.is_passable(id) and reach[level.index_of(cell)] < 0
			var open := Palette.is_passable(id) and not hidden
			walk.set_pixel(x, y, Color.WHITE if open else Color.BLACK)
			inside.set_pixel(x, y, Color.BLACK if id == Palette.Tile.VOID else Color.WHITE)
			lava.set_pixel(x, y, Color.WHITE if open and id == Palette.Tile.HAZARD else Color.BLACK)
	var px := n * UPSCALE
	for mask: Image in [walk, inside, lava]:
		mask.resize(px, px, Image.INTERPOLATE_BILINEAR)
	var w := walk.get_data()
	var ins := inside.get_data()
	var hz := lava.get_data()
	var biome := LevelLights.biome_of(level)
	var floor_color: Color = COLORS[&"floor"]
	var hazard_color: Color = COLORS[&"hazard"]
	if biome != null:
		var tint := Color(biome.ambient_light.r, biome.ambient_light.g, biome.ambient_light.b)
		floor_color = floor_color.lerp(tint * 0.75, BIOME_TINT)
		floor_color.a = COLORS[&"floor"].a
		if biome.hazard_light.a > 0.0:
			hazard_color = Color(biome.hazard_light.r, biome.hazard_light.g, biome.hazard_light.b).lerp(floor_color, 0.35)
	var rim: Color = COLORS[&"rim"]
	var wall: Color = COLORS[&"wall"]
	var out := PackedByteArray()
	out.resize(px * px * 4)
	for i in px * px:
		if ins[i] < 128:
			continue  # пустота за краем карты — прозрачна
		var v := w[i]
		var c: Color
		if v >= 128 + RIM_BAND:
			# Пол: у стены темнее (тень кромки), лёгкое зерно — от номера пикселя, у всех одинаковое.
			var shade := clampf(float(v - 128) / 110.0, 0.6, 1.0)
			var grain := float(((i * 2654435761) >> 20) & 15) / 15.0 * 0.08 - 0.04
			c = (hazard_color if hz[i] >= 128 else floor_color) * (shade + grain)
			c.a = floor_color.a
		elif v >= 128 - RIM_BAND:
			c = rim
		else:
			c = wall
		var o := i * 4
		out[o] = int(clampf(c.r, 0.0, 1.0) * 255.0)
		out[o + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
		out[o + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
		out[o + 3] = int(clampf(c.a, 0.0, 1.0) * 255.0)
	return Image.create_from_data(px, px, false, Image.FORMAT_RGBA8, out)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect.grow(2.0), BORDER)
	draw_rect(rect, BACK)
	var level := GameState.current_level
	if _texture == null or level == null or world == null:
		return
	draw_texture_rect(_texture, rect, false)  # линейный фильтр: картинка уже в UPSCALE раз детальнее клеток
	var scale := size.x / float(level.size * Palette.tile_size())
	var blink := 0.6 + 0.4 * sin(_time * 6.0)

	for node in world.props.get_children():
		var p := (node as Node2D).global_position * scale
		if node is Portal:
			var gate := node as Portal
			var c := Portal.MODE_COLORS[gate.mode] if gate.active else Portal.IDLE_COLOR.lightened(0.3)
			_ring(p, 3.0, c)
			if gate.active:
				draw_arc(p, 5.0 + 2.0 * blink, 0.0, TAU, 16, Color(c, 0.6), 1.0)
		elif node is Merchant:
			_diamond(p, 3.0, MERCHANT)
		elif node is Chest and not (node as Chest).used:
			_square(p, 1.5, CHEST)
		elif node is Obelisk and not (node as Obelisk).used:
			_square(p, 1.5, OBELISK)
		elif node is Statue and not (node as Statue).used:
			_square(p, 1.5, STATUE)
		elif node is ChallengeAltar and (not (node as ChallengeAltar).used or (node as ChallengeAltar).active):
			_square(p, 1.5, ChallengeAltar.RUNE if (node as ChallengeAltar).kind == ChallengeAltar.TRIAL \
					else ChallengeAltar.CURSE_FLAME)
		elif node is Fountain:
			_square(p, 1.5, FOUNTAIN)
		elif node is GrailSite and not (node as GrailSite).used:
			_diamond(p, 2.5, KEY)
	for node in world.pickups.get_children():
		if node is Pickup and (node as Pickup).kind == Pickup.Kind.KEY:
			_diamond((node as Pickup).global_position * scale, 2.5, Color(KEY, blink))
	for node in world.enemies.get_children():
		var e := node as Enemy
		if e == null or e.dead or e.ally or e.data == null:
			continue
		if e.data.is_boss:
			_dot(e.global_position * scale, 3.0, BOSS)
			draw_arc(e.global_position * scale, 4.5, 0.0, TAU, 16, Color(BOSS, blink), 1.0)
		elif e.data.loot_rarity >= 0:
			_dot(e.global_position * scale, 2.5, MINI_BOSS)
		elif e.is_elite():
			_dot(e.global_position * scale, 1.5, ELITE)
	var me := world.local_player()
	for p in world.get_players():
		if p != me:
			_dot(p.global_position * scale, 2.0, ALLY if p.alive else Color(ALLY, 0.4))
	if me != null:
		_dot(me.global_position * scale, 2.5, LOCAL_PLAYER)
		draw_arc(me.global_position * scale, 3.5, 0.0, TAU, 12, Color(0, 0, 0, 0.8), 1.0)


func _dot(p: Vector2, r: float, c: Color) -> void:
	draw_circle(p, r, c)


func _square(p: Vector2, r: float, c: Color) -> void:
	draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), c)


func _diamond(p: Vector2, r: float, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), c)
	draw_polyline(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)]), Color(0, 0, 0, 0.7), 1.0)


func _ring(p: Vector2, r: float, c: Color) -> void:
	draw_circle(p, r, Color(c, 0.35))
	draw_arc(p, r, 0.0, TAU, 12, c, 1.5)
