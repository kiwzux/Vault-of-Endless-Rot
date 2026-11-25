class_name EconomySystem
extends Node
## Хост: золото, торговцы и пояс зелий (CR-14).
## Монеты выпадают с врагов (обычный — по шансу, элита — всегда, босс и мини-босс статуи —
## гарантированная сумма EnemyData.gold) и из сундуков; подбирает их ближайший герой, «Алчность»
## увеличивает сумму. Золото тратится у торговцев (Merchant) и на переброс карт левел-апа
## (UpgradeSystem). Зелья пояса — из сундуков, с элит и у алхимика, пьются клавишей Q.
##
## Каждое действие игрока проверяет хост (ФТ-16): герой жив и стоит у торговца, золота хватает,
## товар не кончился, в сумке или поясе есть место. Отклонённое действие состояние не меняет.
## Точки подключения сети (game/net):
##  - buy_submitted / drink_submitted / chest_submitted на клиенте → RPC хосту → apply_*(sender_id, ...);
##  - Merchant.offers синхронизируется хост → все.
## Лут торговцы не скупают: подобранный предмет навсегда прибавляет свои характеристики (Player.receive_item).

signal buy_submitted(merchant_id: StringName, offer_index: int)
signal drink_submitted

## Разлёт монет вокруг точки, чтобы кучка не лежала стопкой.
const SCATTER := 12.0

@export var table: EconomyTable

var _world: World
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if table == null:
		table = DataRegistry.ECONOMY
	_world = World.of(self)
	_rng.seed = hash([RunConfig.run_seed, "gold"])


# --- Золото и зелья на земле (хост) ---

## Сумма из диапазона [мин, макс] с ростом по глубине забега; 0 — диапазон пустой.
func roll_gold(bounds: Vector2i) -> int:
	if bounds.y <= 0:
		return 0
	return roundi(_rng.randi_range(bounds.x, bounds.y) * table.gold_mult(GameState.level_index))


## Рассыпать сумму монетами не дороже max_coin_value.
func drop_gold(pos: Vector2, amount: int) -> void:
	while amount > 0:
		var coin := mini(amount, table.max_coin_value)
		amount -= coin
		_world.spawn_pickup({"kind": Pickup.Kind.GOLD, "pos": pos + _scatter(), "value": coin})


func drop_enemy_rewards(enemy: Enemy) -> void:
	var amount := roll_gold(enemy.data.gold)
	if enemy.is_elite():
		amount += roll_gold(table.elite_gold)
		if _rng.randf() < table.elite_potion_chance:
			_drop_potion(enemy.global_position)
	elif amount == 0 and _rng.randf() < table.enemy_gold_chance:
		amount = roll_gold(table.enemy_gold)
	drop_gold(enemy.global_position, roundi(amount * _world.waves.reward_mult()))  # алтарь проклятий (шаг 8)


## Сундук (CR-06): к предметам и опыту — иногда зелье. Золота в сундуке нет: за него платят.
func drop_chest_rewards(pos: Vector2) -> void:
	if _rng.randf() < table.chest_potion_chance:
		_drop_potion(pos)


## Цена следующего сундука для героя (платные сундуки, CR-14).
func chest_price(player: Player) -> int:
	return _sealed(table.chest_price(player.chests_opened))


func collect_gold(player: Player, amount: int) -> void:
	var gained := player.earn_gold(amount)
	if gained > 0:
		Events.gold_collected.emit(player.peer_id(), gained)


# --- Цены ---

func item_price(item: Dictionary) -> int:
	var rarity := clampi(int(item.get("rarity", 0)), 0, table.item_prices.size() - 1)
	return _sealed(roundi(table.item_prices[rarity] * table.price_mult(GameState.level_index)))


func goods_price(goods: GoodsData) -> int:
	return _sealed(roundi(goods.price * table.price_mult(GameState.level_index)))


func reroll_cost(player: Player) -> int:
	return _sealed(table.reroll_cost(player.rerolls))


## Цена с печатью ростовщика (шаг 12.3): сундуки, торговцы и переброс карт дороже.
func _sealed(price: int) -> int:
	return roundi(price * RunConfig.seal_mult(SealData.Stat.PRICES))


## Товар торговца на уровень: предметы не ниже item_min_rarity и товары из данных. Сид — от сида
## забега, номера уровня и торговца: один код забега даёт одинаковый товар.
func make_stock(merchant: MerchantData) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([RunConfig.run_seed, GameState.level_index, merchant.id, "stock"])
	var depth := GameState.level_index
	var loot_table := _world.loot.table
	var offers: Array = []
	for i in merchant.item_count:
		var rarity := ItemRoller.roll_rarity(rng, loot_table, depth, merchant.item_min_rarity, RunConfig.magic_find_mult())
		var item := ItemRoller.roll(rng, rarity, depth, loot_table)
		offers.append({"kind": Merchant.OFFER_ITEM, "item": item, "price": item_price(item), "stock": 1})
	for goods: GoodsData in merchant.goods:
		offers.append({"kind": Merchant.OFFER_GOODS, "id": goods.id, "price": goods_price(goods), "stock": goods.stock})
	return offers


func find_merchant(merchant_id: StringName) -> Merchant:
	for child in _world.props.get_children():
		if child is Merchant and child.merchant_id == merchant_id:
			return child
	return null


# --- Действия игрока ---

## Вызывает окно торговца своего игрока.
func submit_buy(merchant_id: StringName, offer_index: int) -> void:
	if multiplayer.is_server():
		apply_buy(multiplayer.get_unique_id(), merchant_id, offer_index)
	else:
		buy_submitted.emit(merchant_id, offer_index)


## Вызывает герой своего игрока по клавише Q.
func submit_drink() -> void:
	if multiplayer.is_server():
		apply_drink(multiplayer.get_unique_id())
	else:
		drink_submitted.emit()


## Хост: купить товар offer_index. false — отклонено, состояние не менялось (ФТ-16).
func apply_buy(peer_id: int, merchant_id: StringName, offer_index: int) -> bool:
	var merchant := find_merchant(merchant_id) if multiplayer.is_server() else null
	var player := _trader(peer_id, merchant)
	if player == null or offer_index < 0 or offer_index >= merchant.offers.size():
		return false
	var offer: Dictionary = merchant.offers[offer_index]
	var price: int = offer["price"]
	if int(offer["stock"]) <= 0 or player.gold < price or not merchant.can_deal(peer_id):
		return false
	if offer["kind"] == Merchant.OFFER_ITEM:
		if not player.can_receive(offer["item"]):
			return false
		player.spend_gold(price)
		player.receive_item(offer["item"])
	elif not _deliver_goods(player, DataRegistry.goods(offer["id"]), price):
		return false
	merchant.take_one(offer_index)
	merchant.record_deal(peer_id)
	Events.trade_completed.emit(peer_id, merchant_id)
	return true


func apply_drink(peer_id: int) -> bool:
	var player := _world.find_player(peer_id) if multiplayer.is_server() else null
	return player != null and player.drink_potion()


## Товар без экипировки: сначала проверка, что его можно отдать, потом оплата.
func _deliver_goods(player: Player, goods: GoodsData, price: int) -> bool:
	if goods == null:
		return false
	match goods.effect:
		GoodsData.Effect.BELT_POTION:
			if player.potions >= Player.BELT_SIZE:
				return false
			player.spend_gold(price)
			player.potions += 1
		GoodsData.Effect.BUFF:
			player.spend_gold(price)
			player.add_buff(goods.id, goods.duration, goods.stats)
		GoodsData.Effect.LEVEL:
			player.spend_gold(price)
			_world.upgrades.grant_xp(player, Player.xp_to_next(player.level) - player.xp, false)
		GoodsData.Effect.GAMBLE:
			var depth := GameState.level_index
			var item := ItemRoller.roll(_rng, _rng.rand_weighted(table.gamble_weights), depth, _world.loot.table)
			if not player.can_receive(item):
				return false
			player.spend_gold(price)
			player.receive_item(item)
			Events.item_picked.emit(player.peer_id(), item)
		_:
			return false
	return true


## Хост: герой, который может торговать с этим торговцем, — жив и стоит рядом. null — нельзя.
func _trader(peer_id: int, merchant: Merchant) -> Player:
	if merchant == null:
		return null
	var player := _world.find_player(peer_id)
	if player == null or not player.alive or not merchant.in_reach(player):
		return null
	return player


func _drop_potion(pos: Vector2) -> void:
	_world.spawn_pickup({"kind": Pickup.Kind.POTION, "pos": pos + _scatter()})


func _scatter() -> Vector2:
	return Vector2(_rng.randf_range(-SCATTER, SCATTER), _rng.randf_range(-SCATTER, SCATTER))
