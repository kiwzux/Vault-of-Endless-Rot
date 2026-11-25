class_name ShopPanel
extends CanvasLayer
## Окно торговца (CR-14): клавиша E рядом с торговцем. Слева — товар с ценами. У торговца экипировкой описание
## товара — всплывающее окно (ItemTooltips, как в инвентаре) с ценой; зажатый Alt — рядом надетый предмет того же
## слота и разница характеристик. У торговца без экипировки (алхимик) описание — колонкой справа, как раньше.
## Торговцы только продают: лут не скупается. Действия уходят хосту через EconomySystem и проверяются там (ФТ-16).
## В одиночной игре мир на паузе; в сети — нет, и окно закрывается, если герой отошёл.

const REASON := &"shop"
const OFFER_SIZE := Vector2(230, 22)
const ICON_SIZE := 20.0
const PRICE_COLOR := Color(1.0, 0.8, 0.25)
const TOO_EXPENSIVE := Color(0.75, 0.3, 0.25)
const SOLD_COLOR := Color(0.45, 0.42, 0.38)

var merchant: Merchant
var _world: World
var _player: Player
var _gold_shown := -1
var _focus_offer := 0
## Всплывающие окна товара (торговец экипировкой); для проверок.
var tips: ItemTooltips
## Торговец продаёт экипировку: описание во всплывающих окнах, колонки описания нет.
var _item_mode := false

@onready var details: Control = $Center/Panel/Column/Row/Details
@onready var hint: Label = $Center/Panel/Column/Hint
@onready var title: Label = %Title
@onready var gold_label: Label = %Gold
@onready var greeting: Label = %Greeting
@onready var offers_box: VBoxContainer = %Offers
@onready var detail_name: Label = %DetailName
@onready var detail_type: Label = %DetailType
@onready var detail_stats: Label = %DetailStats
## Строка проклятия — отдельно и красным (шаг 7).
@onready var detail_curse: Label = %DetailCurse
@onready var detail_compare: Label = %DetailCompare
@onready var detail_price: Label = %DetailPrice


func _ready() -> void:
	hide()
	_world = World.of(self)
	tips = ItemTooltips.new()
	tips.column = offers_box
	add_child(tips)
	Events.inventory_changed.connect(func(peer_id: int) -> void:
		if visible and peer_id == multiplayer.get_unique_id():
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if visible:
		if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			close()
		return
	if event.is_action_pressed(&"interact") and not _world.input_blocked():
		var nearest := nearest_merchant()
		if nearest != null:
			get_viewport().set_input_as_handled()
			open(nearest)


## Торговец, до которого дотягивается свой живой герой; null — никого рядом.
func nearest_merchant() -> Merchant:
	var player := _world.local_player()
	if player == null or not player.alive:
		return null
	for child in _world.props.get_children():
		if child is Merchant and (child as Merchant).in_reach(player):
			return child
	return null


func open(target: Merchant) -> void:
	merchant = target
	_player = _world.local_player()
	_focus_offer = 0
	_item_mode = merchant.data.item_count > 0
	details.visible = not _item_mode
	hint.text = "SHOP_HINT_ITEMS" if _item_mode else "SHOP_HINT"
	tips.player = _player
	merchant.stock_changed.connect(_refresh)
	show()
	_world.request_pause(REASON, true)
	_refresh()


func close() -> void:
	if merchant != null and is_instance_valid(merchant) and merchant.stock_changed.is_connected(_refresh):
		merchant.stock_changed.disconnect(_refresh)
	merchant = null
	tips.hide_tips()
	hide()
	_world.request_pause(REASON, false)


func _process(_delta: float) -> void:
	if not visible:
		return
	if merchant == null or not is_instance_valid(merchant) or _player == null or not is_instance_valid(_player) \
			or not _player.alive or not merchant.in_reach(_player):
		close()
	elif _player.gold != _gold_shown:
		_refresh()


func _refresh() -> void:
	if merchant == null or _player == null:
		return
	_gold_shown = _player.gold
	title.text = tr(merchant.data.name_key)
	gold_label.text = tr("SHOP_GOLD").format({"gold": _player.gold})
	greeting.text = tr(merchant.data.greeting_key)
	if not merchant.can_deal(_player.peer_id()):  # торговец с пределом сделок: свои сделки герой исчерпал
		greeting.text = tr("MERCHANT_DEAL_DONE")
	tips.hide_tips()  # строки товара строятся заново; окно вернётся с фокусом ниже
	for child in offers_box.get_children():
		offers_box.remove_child(child)
		child.queue_free()
	for i in merchant.offers.size():
		offers_box.add_child(_offer_button(i, merchant.offers[i]))
	_show_offer(clampi(_focus_offer, 0, maxi(merchant.offers.size() - 1, 0)))
	if offers_box.get_child_count() > 0:
		(offers_box.get_child(clampi(_focus_offer, 0, offers_box.get_child_count() - 1)) as Control).grab_focus()


## Можно ли купить на взгляд клиента; окончательно решает хост.
func _can_buy(offer: Dictionary) -> bool:
	if int(offer["stock"]) <= 0 or _player.gold < int(offer["price"]) or not merchant.can_deal(_player.peer_id()):
		return false
	if offer["kind"] == Merchant.OFFER_ITEM:
		return _player.can_receive(offer["item"])
	var goods := DataRegistry.goods(offer["id"])
	if goods.effect == GoodsData.Effect.BELT_POTION:
		return _player.potions < Player.BELT_SIZE
	return true  # свёрток с предметом — всегда: сумки нет, предметы копятся


func _offer_button(index: int, offer: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = OFFER_SIZE
	var sold_out := int(offer["stock"]) <= 0
	button.disabled = not _can_buy(offer)
	button.pressed.connect(func() -> void:
		_focus_offer = index
		_world.economy.submit_buy.call_deferred(merchant.merchant_id, index))
	button.focus_entered.connect(func() -> void:
		_focus_offer = index
		_show_offer(index, button))
	button.mouse_entered.connect(_show_offer.bind(index, button))
	if _item_mode:
		button.mouse_exited.connect(func() -> void: tips.unhover(button, true))
		button.focus_exited.connect(func() -> void: tips.unhover(button, false))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4.0
	row.offset_right = -6.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	button.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = ItemIcon.FILTER
	icon.draw.connect(func() -> void:
		var rect := Rect2(Vector2.ZERO, icon.size)
		if offer["kind"] == Merchant.OFFER_ITEM:
			ItemIcon.draw_item(icon, rect, offer["item"])
		else:
			ItemIcon.draw_goods(icon, rect, DataRegistry.goods(offer["id"])))
	row.add_child(icon)

	var name_color := SOLD_COLOR
	if not sold_out:
		name_color = ItemRoller.rarity_color(offer["item"]) if offer["kind"] == Merchant.OFFER_ITEM \
				else DataRegistry.goods(offer["id"]).icon_color.lightened(0.3)
	var label := _label(merchant.offer_name(offer), name_color, 10)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	var price_text := tr("SHOP_SOLD_OUT") if sold_out else str(offer["price"])
	if not sold_out and int(offer["stock"]) > 1:
		price_text = "×%d  %s" % [offer["stock"], price_text]
	var price_color := SOLD_COLOR if sold_out else (PRICE_COLOR if _player.gold >= int(offer["price"]) else TOO_EXPENSIVE)
	row.add_child(_label(price_text, price_color, 10))
	return button


## Описание товара: у торговца экипировкой — всплывающее окно рядом с его строкой (cell), иначе — колонка справа.
func _show_offer(index: int, cell: Control = null) -> void:
	if merchant == null or index < 0 or index >= merchant.offers.size():
		_show_text("", "", "", "", "")
		return
	var offer: Dictionary = merchant.offers[index]
	var price := tr("SHOP_PRICE").format({"price": offer["price"]})
	if _item_mode:
		if cell == null:
			return
		if offer["kind"] == Merchant.OFFER_ITEM:
			tips.hover(offer["item"], cell, price)
		else:
			var item_goods := DataRegistry.goods(offer["id"])
			tips.hover_text(cell, tr(item_goods.name_key), item_goods.icon_color.lightened(0.3),
					tr("SHOP_GOODS_STOCK").format({"stock": offer["stock"]}), tr(item_goods.description_key), price)
		return
	if offer["kind"] == Merchant.OFFER_ITEM:
		_show_item(offer["item"], price)
		return
	var goods := DataRegistry.goods(offer["id"])
	detail_name.add_theme_color_override("font_color", goods.icon_color.lightened(0.3))
	_show_text(tr(goods.name_key), tr("SHOP_GOODS_STOCK").format({"stock": offer["stock"]}),
			tr(goods.description_key), "", price)


## Предмет и надетый в том же слоте — для сравнения (у кольца — то, на чьё место оно встанет).
func _show_item(item: Dictionary, price: String) -> void:
	var slot := ItemRoller.slot_of(item)
	detail_name.add_theme_color_override("font_color", ItemRoller.rarity_color(item))
	var worn: Dictionary = _player.equipment.get(_player.doll_slot_for(item), {})
	var compare := tr("SHOP_SLOT_FREE")
	if not worn.is_empty() and worn != item:
		compare = tr("SHOP_EQUIPPED").format({"name": ItemRoller.display_name(worn)}) + "\n" \
				+ "\n".join(ItemRoller.tooltip_lines(worn))
	elif worn == item:
		compare = ""
	_show_text(ItemRoller.display_name(item),
			"%s · %s" % [tr(ItemRoller.RARITY_KEYS[item["rarity"]]), tr(ItemBaseData.SLOT_KEYS[slot])],
			"\n".join(ItemRoller.bonus_lines(item)), compare, price, ItemRoller.curse_line(item))


func _show_text(item_name: String, kind_text: String, stats: String, compare: String, price: String,
		curse: String = "") -> void:
	detail_name.text = item_name
	detail_type.text = kind_text
	detail_stats.text = stats
	detail_curse.text = curse
	detail_curse.visible = curse != ""
	detail_compare.text = compare
	detail_price.text = price


func _label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # текст уже переведён через tr()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label
