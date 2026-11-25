class_name LootSystem
extends Node
## Хост: выпадение предметов (CR-07). Предмет на земле — Pickup вида ITEM; подобранный навсегда прибавляет свои
## характеристики герою (Player.receive_item, 17.10.2026: предметы копятся, сумки и обмена нет — действий
## с инвентарём у игрока нет). Player.equipment, item_stats и items_collected синхронизируются хост → владелец.

## Разлёт выпавших предметов вокруг точки, чтобы они не лежали стопкой.
const SCATTER := 14.0

@export var table: LootTable

var _world: World
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if table == null:
		table = DataRegistry.LOOT_TABLE
	_world = World.of(self)
	_rng.seed = hash([RunConfig.run_seed, "loot"])


## Хост: предмет с редкостью не ниже min_rarity; Скверна забега (шаг 12.3) — чаще магические и лучше.
func drop_item(pos: Vector2, min_rarity: int = ItemRoller.Rarity.NORMAL) -> Pickup:
	var rarity := ItemRoller.roll_rarity(_rng, table, GameState.level_index, min_rarity, RunConfig.magic_find_mult())
	var item := ItemRoller.roll(_rng, rarity, GameState.level_index, table)
	return _world.spawn_pickup({"kind": Pickup.Kind.ITEM, "pos": pos + _scatter(), "item": item})


func maybe_drop(pos: Vector2, chance: float) -> void:
	if _rng.randf() < chance:
		drop_item(pos)


## Сундук: предметы по таблице, горсть кристаллов опыта (CR-06), золото и, бывает, зелье (CR-14).
func open_chest(pos: Vector2) -> void:
	for i in table.chest_items:
		drop_item(pos)
	for i in table.chest_xp_gems:
		_world.upgrades.drop_xp(pos + _scatter(), 2)
	_world.economy.drop_chest_rewards(pos)


## Награда за испытание (CR-16): редкий предмет или лучше, золото и кристаллы опыта.
func challenge_reward(pos: Vector2) -> void:
	drop_item(pos, ItemRoller.Rarity.RARE)
	var economy := _world.economy
	economy.drop_gold(pos, economy.roll_gold(economy.table.challenge_gold))
	for i in table.chest_xp_gems * 2:
		_world.upgrades.drop_xp(pos + _scatter(), 3)


## Хост: отдать предмет герою (его характеристики копятся). false — предмет испорчен, остаётся на земле.
func give(player: Player, item: Dictionary) -> bool:
	if not player.receive_item(item):
		return false
	Events.item_picked.emit(player.peer_id(), item)
	return true


func _scatter() -> Vector2:
	return Vector2(_rng.randf_range(-SCATTER, SCATTER), _rng.randf_range(-SCATTER, SCATTER))
