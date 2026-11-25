class_name Chest
extends MapObject
## Сундук (CR-06, CR-07): платный, как в Megabonk. Герой подходит и жмёт E — хост списывает цену и
## открывает сундук: предметы по таблице весов LootTable, кристаллы опыта, иногда зелье.
## Цена своя у каждого героя: первый сундук — EconomyTable.chest_price_base, каждый следующий
## дороже в chest_price_growth раз (100 → 150 → 225 …). Золота не хватает — сундук не открывается.

const LOCKED := Color(0.85, 0.3, 0.25)
const AFFORDABLE := Color(1.0, 0.82, 0.3)
## Мимик (шаг 8): враг, которым становится сундук-мимик.
const MIMIC_ID := &"mimic"

## Хост: это мимик — по E оживает и бросается на героя (золото не списывается). Клиентам не сообщается:
## выглядит и подписан как обычный сундук. Награда за убитого мимика — вдвое против сундука (EnemyData).
var mimic := false


func _init() -> void:
	requires_key = true


func _ready() -> void:
	super()
	interact_radius = 24.0


func activate(player: Player) -> bool:
	if mimic:
		used = true
		var waves := _world.waves
		waves.spawn_enemy(DataRegistry.enemy(MIMIC_ID), global_position, [], waves.wave_stage())
		Events.interactable_used.emit(MIMIC_ID, player.peer_id(), &"mimic")
		return true
	var price := _world.economy.chest_price(player)
	if not player.spend_gold(price):
		return false
	used = true
	player.chests_opened += 1
	_world.loot.open_chest(global_position)
	Events.chest_opened.emit(player.peer_id(), price)
	return true


func prompt_text(player: Player, near: bool) -> String:
	var price := _world.economy.chest_price(player)
	return tr("CHEST_PROMPT").format({"price": price}) if near else tr("CHEST_PRICE").format({"price": price})


func prompt_color(player: Player) -> Color:
	return AFFORDABLE if player.gold >= _world.economy.chest_price(player) else LOCKED


func art_id() -> StringName:
	return &"chest_open" if used else &"chest"


func _draw() -> void:
	if _art != null:
		return
	var wood := Color(0.45, 0.28, 0.12)
	var gold := Color(0.9, 0.72, 0.3)
	if used:
		draw_rect(Rect2(-8, -2, 16, 8), wood.darkened(0.3))
		draw_rect(Rect2(-8, -9, 16, 4), wood.darkened(0.1))
	else:
		draw_rect(Rect2(-8, -6, 16, 12), wood)
		draw_rect(Rect2(-8, -1, 16, 2), gold)
		draw_rect(Rect2(-2, -2, 4, 4), gold)
