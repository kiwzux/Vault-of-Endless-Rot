class_name Merchant
extends Node2D
## Торговец (CR-14) — объект карты в контейнере World/Props. Встаёт рядом с объектом, который
## поставила модель (LevelFlow), и торгует, когда герой подошёл и нажал E (окно ShopPanel).
## Товар — offers: словари из простых типов
##   {"kind": OFFER_ITEM, "item": предмет ItemRoller, "price": int, "stock": int} или
##   {"kind": OFFER_GOODS, "id": GoodsData.id, "price": int, "stock": int};
## game/net синхронизирует его хост → все, меняет его только хост (EconomySystem.apply_buy).

signal stock_changed

const OFFER_ITEM := &"item"
const OFFER_GOODS := &"goods"
## Торговать можно, стоя не дальше этого.
const TRADE_RADIUS := 36.0
## Предел товара от другого участника сессии: защищает от испорченных данных.
const MAX_OFFERS := 16
const WOOD := Color(0.42, 0.27, 0.13)
const CLOTH := Color(0.92, 0.86, 0.7)

@export var merchant_id: StringName
@export var offers: Array = []:
	set(value):
		offers = value
		stock_changed.emit()

## Торговец с пределом сделок (MerchantData.deals_per_player): кто уже заключил сделку (peer id по разу за
## сделку). Хост → все: окно торговца показывает, что сделки исчерпаны. При deals_per_player = 0 не используется.
@export var dealt: Array = []:
	set(value):
		dealt = value
		stock_changed.emit()

var data: MerchantData

var _world: World
var _prompt: Label
## Лавка из атласа объектов (шаг 11.20, PropArt: merchant_<id>); null — лавка рисуется кодом цветом robe_color.
var _art: PropArt


## Фабрика для хоста и для spawn_function. null — неизвестный торговец (данные могли прийти по сети).
static func create(spawn: Dictionary) -> Merchant:
	var info := DataRegistry.merchant(StringName(str(spawn.get("merchant", ""))))
	if info == null:
		return null
	var merchant := Merchant.new()
	merchant.merchant_id = info.id
	merchant.offers = sanitize_offers(spawn.get("offers", []))
	return merchant


## Только корректные предложения: цена и запас — неотрицательные целые, предмет и товар существуют.
static func sanitize_offers(raw: Variant) -> Array:
	var result: Array = []
	if not (raw is Array):
		return result
	for offer: Variant in raw:
		if result.size() >= MAX_OFFERS:
			break
		if not (offer is Dictionary):
			continue
		var price: Variant = offer.get("price")
		var stock: Variant = offer.get("stock")
		if not (price is int and stock is int) or price < 0 or stock < 0:
			continue
		var kind: Variant = offer.get("kind")
		if kind == OFFER_ITEM and ItemRoller.is_valid(offer.get("item")):
			result.append(offer)
		elif kind == OFFER_GOODS and DataRegistry.goods(StringName(str(offer.get("id", "")))) != null:
			result.append(offer)
	return result


func _ready() -> void:
	data = DataRegistry.merchant(merchant_id)
	_world = World.of(self)
	_art = PropArt.attach(self, StringName("merchant_" + String(merchant_id)), randf() * 4.0)
	add_child(_make_label(data.name_key, Color(1.0, 0.85, 0.45), -(_art.height() + 10.0) if _art != null else -40.0))
	_prompt = _make_label("TRADE_PROMPT", Color(0.95, 0.95, 0.85), 10.0)
	_prompt.hide()
	add_child(_prompt)


func _process(_delta: float) -> void:
	var player := _world.local_player() if _world != null else null
	_prompt.visible = player != null and player.alive and in_reach(player)


func in_reach(player: Player) -> bool:
	return global_position.distance_to(player.global_position) <= TRADE_RADIUS


func offer_name(offer: Dictionary) -> String:
	if offer.get("kind") == OFFER_ITEM:
		return ItemRoller.display_name(offer["item"])
	var goods := DataRegistry.goods(offer.get("id", &""))
	return tr(goods.name_key) if goods != null else ""


## Может ли герой peer_id заключить ещё одну сделку (MerchantData.deals_per_player).
func can_deal(peer_id: int) -> bool:
	var info := data if data != null else DataRegistry.merchant(merchant_id)
	return info.deals_per_player <= 0 or dealt.count(peer_id) < info.deals_per_player


## Хост: сделка заключена (массив пересобирается целиком — так его видит синхронизатор).
func record_deal(peer_id: int) -> void:
	var info := data if data != null else DataRegistry.merchant(merchant_id)
	if info.deals_per_player > 0:
		var copy := dealt.duplicate()
		copy.append(peer_id)
		dealt = copy


## Хост: продан один экземпляр. Массив пересобирается целиком — так его видит синхронизатор.
func take_one(index: int) -> void:
	var copy := offers.duplicate(true)
	copy[index]["stock"] = maxi(int(copy[index]["stock"]) - 1, 0)
	offers = copy


func _make_label(text: String, color: Color, y: float) -> Label:
	var label := Label.new()
	label.text = text  # ключ — Label переведёт сам
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.size = Vector2(140, 12)
	label.position = Vector2(-70, y)
	LightMap.lift_label(label)
	return label


## Лавка под навесом: торговец за прилавком, на прилавке товар.
func _draw() -> void:
	if _art != null:
		return
	var robe := data.robe_color if data != null else Color.WHITE
	draw_circle(Vector2(0, 6), 16.0, Color(0, 0, 0, 0.25))
	draw_line(Vector2(-14, -24), Vector2(-14, 6), WOOD, 2.0)
	draw_line(Vector2(14, -24), Vector2(14, 6), WOOD, 2.0)
	for i in 4:
		draw_rect(Rect2(-16 + i * 8, -28, 8, 6), robe if i % 2 == 0 else CLOTH)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5, -8), Vector2(5, -8), Vector2(7, 0), Vector2(-7, 0),
	]), robe.darkened(0.2))
	draw_circle(Vector2(0, -12), 3.5, Color(0.85, 0.7, 0.55))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-4.5, -12), Vector2(0, -19), Vector2(4.5, -12),
	]), robe.darkened(0.35))
	draw_rect(Rect2(-13, -1, 26, 6), WOOD)
	draw_rect(Rect2(-13, -1, 26, 1.5), WOOD.lightened(0.3))
	draw_circle(Vector2(-8, -3), 2.0, Color(0.85, 0.2, 0.25))
	draw_circle(Vector2(-3, -3), 2.0, Color(0.3, 0.6, 0.95))
	draw_rect(Rect2(4, -5, 5, 4), Color(1.0, 0.8, 0.3))
