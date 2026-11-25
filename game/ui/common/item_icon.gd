class_name ItemIcon
extends RefCounted
## Значок предмета экипировки или товара — общий для инвентаря, окна торговца, пояса зелий, трофеев «Летописи»
## и предметов на земле (шаг 11.15): рисунок из атласа art/gen_icons.py (res://assets/icons/items.png + items.json —
## значки набора «Dark fantasy Asset Pack» и дорисованная экипировка) на тёмной клетке, рамка цвета редкости (как в
## Diablo). Какой значок у предмета — в данных (ItemBaseData.icons, UniqueItemData.icon, GoodsData.icon).
## Значка нет в атласе — силуэт слота или флакон, нарисованные кодом, как до шага 11.15.
## Атлас рисуется уменьшенным, поэтому узлу со значком нужен фильтр FILTER (у атласа есть mipmap-уровни).

const PATH := "res://assets/icons/items.json"
const FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
const EMPTY_BACK := Color(0.1, 0.08, 0.07)
const EMPTY_BORDER := Color(0.3, 0.24, 0.15)
const GLYPH := Color(0.08, 0.06, 0.05, 0.75)
const GOODS_BORDER := Color(0.72, 0.55, 0.25)

static var _texture: Texture2D
static var _cell := 64
static var _columns := 1
static var _index := {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if not (parsed is Dictionary):
		push_warning("ItemIcon: нет атласа значков %s (art/gen_icons.py)" % PATH)
		return
	_texture = load(PATH.get_base_dir().path_join(String(parsed["atlas"])))
	_cell = int(parsed["cell"])
	_columns = maxi(int(parsed["columns"]), 1)
	_index = parsed["icons"]


static func has_icon(icon: StringName) -> bool:
	_ensure_loaded()
	return _texture != null and _index.has(String(icon))


## Область значка в атласе; значка нет — пустой прямоугольник.
static func region(icon: StringName) -> Rect2:
	if not has_icon(icon):
		return Rect2()
	var i := int(_index[String(icon)])
	return Rect2((i % _columns) * _cell, (i / _columns) * _cell, _cell, _cell)


## Значок как текстура для TextureRect; значка нет — null.
static func texture(icon: StringName) -> AtlasTexture:
	if not has_icon(icon):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = _texture
	atlas.region = region(icon)
	return atlas


## Рисунок значка в rect; false — значка нет в атласе (рисует вызывающий сам).
static func draw_icon(canvas: CanvasItem, rect: Rect2, icon: StringName, tint := Color.WHITE) -> bool:
	if not has_icon(icon):
		return false
	canvas.draw_texture_rect_region(_texture, rect, region(icon), tint)
	return true


## Предмет (словарь ItemRoller) или пустой слот slot (ItemBaseData.Slot); -1 — без силуэта.
static func draw_item(canvas: CanvasItem, rect: Rect2, item: Dictionary, slot: int = -1) -> void:
	if item.is_empty():
		canvas.draw_rect(rect, EMPTY_BACK)
		canvas.draw_rect(rect, EMPTY_BORDER, false, 1.0)
		if slot >= 0:
			draw_glyph(canvas, rect, slot, Color(EMPTY_BORDER, 0.8))
		return
	var rarity := ItemRoller.rarity_color(item)
	canvas.draw_rect(rect, EMPTY_BACK.lerp(rarity, 0.12))
	draw_item_picture(canvas, rect, item)
	canvas.draw_rect(rect.grow(-0.5), rarity, false, 1.0)


## Только рисунок предмета: значок из атласа или силуэт слота на цвете базы.
static func draw_item_picture(canvas: CanvasItem, rect: Rect2, item: Dictionary, tint := Color.WHITE) -> void:
	if draw_icon(canvas, rect, ItemRoller.icon_of(item), tint):
		return
	var base := DataRegistry.item_base(item["base"])
	canvas.draw_rect(rect.grow(-1.0), base.icon_color.darkened(0.15) * tint)
	draw_glyph(canvas, rect, base.slot, GLYPH)


## Товар без экипировки: его значок, а без значка — флакон, свёрток или плод его цвета.
static func draw_goods(canvas: CanvasItem, rect: Rect2, goods: GoodsData) -> void:
	canvas.draw_rect(rect, EMPTY_BACK)
	if not draw_icon(canvas, rect, goods.icon):
		var c := rect.get_center()
		var s := rect.size.x / 16.0
		if goods.effect == GoodsData.Effect.GAMBLE:  # свёрток
			canvas.draw_rect(Rect2(c - Vector2(5, 4) * s, Vector2(10, 8) * s), goods.icon_color)
			canvas.draw_line(c + Vector2(0, -4) * s, c + Vector2(0, 4) * s, GLYPH, 1.0)
			canvas.draw_line(c + Vector2(-5, 0) * s, c + Vector2(5, 0) * s, GLYPH, 1.0)
		elif goods.effect == GoodsData.Effect.LEVEL:  # плод Древа знаний
			canvas.draw_circle(c + Vector2(0, 1) * s, 4.5 * s, goods.icon_color)
			canvas.draw_line(c + Vector2(0, -3) * s, c + Vector2(2, -6) * s, Color(0.45, 0.3, 0.15), 1.0)
		else:
			draw_flask(canvas, c, s, goods.icon_color)
	canvas.draw_rect(rect.grow(-0.5), GOODS_BORDER, false, 1.0)


## Зелье пояса: значок VisualConfig.potion_icon, без атласа — красный флакон.
static func draw_potion(canvas: CanvasItem, rect: Rect2, tint := Color.WHITE) -> void:
	if not draw_icon(canvas, rect, DataRegistry.VISUAL.potion_icon, tint):
		draw_flask(canvas, rect.get_center(), rect.size.x / 16.0, Pickup.POTION_COLOR * tint)


static func draw_flask(canvas: CanvasItem, center: Vector2, scale: float, color: Color) -> void:
	canvas.draw_rect(Rect2(center + Vector2(-1.5, -6) * scale, Vector2(3, 3) * scale), Color(0.75, 0.7, 0.6))
	canvas.draw_circle(center + Vector2(0, 1.5) * scale, 4.5 * scale, color)
	canvas.draw_circle(center + Vector2(-1.5, 0) * scale, 1.2 * scale, Color(1, 1, 1, 0.5))


## Силуэт слота: клинок, шлем, кираса, перчатка, сапог, амулет.
static func draw_glyph(canvas: CanvasItem, rect: Rect2, slot: int, color: Color) -> void:
	var c := rect.get_center()
	var s := rect.size.x / 16.0
	match slot:
		ItemBaseData.Slot.WEAPON:
			canvas.draw_line(c + Vector2(-4, 4) * s, c + Vector2(4, -4) * s, color, 2.0 * s)
			canvas.draw_line(c + Vector2(-4, 0) * s, c + Vector2(0, 4) * s, color, 1.5 * s)
		ItemBaseData.Slot.HELM:
			canvas.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-5, 3) * s, c + Vector2(-5, -1) * s, c + Vector2(0, -5) * s,
				c + Vector2(5, -1) * s, c + Vector2(5, 3) * s,
			]), color)
		ItemBaseData.Slot.ARMOR:
			canvas.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-5, -5) * s, c + Vector2(5, -5) * s, c + Vector2(4, 5) * s, c + Vector2(-4, 5) * s,
			]), color)
		ItemBaseData.Slot.GLOVES:
			canvas.draw_rect(Rect2(c + Vector2(-3, -4) * s, Vector2(6, 8) * s), color)
			canvas.draw_rect(Rect2(c + Vector2(3, -1) * s, Vector2(2, 3) * s), color)
		ItemBaseData.Slot.BOOTS:
			canvas.draw_rect(Rect2(c + Vector2(-3, -5) * s, Vector2(4, 8) * s), color)
			canvas.draw_rect(Rect2(c + Vector2(-3, 2) * s, Vector2(7, 3) * s), color)
		ItemBaseData.Slot.AMULET:
			canvas.draw_arc(c + Vector2(0, -2) * s, 4.0 * s, 0.0, PI, 10, color, 1.0)
			canvas.draw_circle(c + Vector2(0, 3) * s, 2.5 * s, color)
		ItemBaseData.Slot.RING, ItemBaseData.Slot.RING_2:
			canvas.draw_arc(c + Vector2(0, 1) * s, 3.5 * s, 0.0, TAU, 16, color, 1.6 * s)
			canvas.draw_circle(c + Vector2(0, -3) * s, 1.6 * s, color)
