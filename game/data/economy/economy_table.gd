class_name EconomyTable
extends Resource
## Экономика забега (CR-14): золото с врагов, сундуков и боссов, зелья пояса, цены торговцев,
## цена переброса карт левел-апа. Суммы золота растут с глубиной на gold_per_level за уровень,
## цены — на price_per_level.

@export_group("Gold")
## Обычный враг: шанс выронить монеты и их сумма [мин, макс].
@export var enemy_gold_chance := 0.05
@export var enemy_gold := Vector2i(1, 3)
## Элита-«чемпион» роняет золото всегда.
@export var elite_gold := Vector2i(8, 15)
## Награда за испытание (Алтарь испытания, Проклятый тотем, CR-16).
@export var challenge_gold := Vector2i(40, 80)
@export var gold_per_level := 0.25
## Крупная сумма рассыпается монетами не дороже этой: кучка золота видна издалека.
@export var max_coin_value := 20

@export_group("Potions")
## Пояс зелий в духе Diablo: столько зелий у героя в начале забега.
@export var start_potions := 1
@export var chest_potion_chance := 0.35
@export var elite_potion_chance := 0.1

@export_group("Chests")
## Платные сундуки (как в Megabonk): цена первого и множитель каждого следующего, у каждого героя свои.
## Глубина на цену не влияет.
@export var chest_price_base := 100
@export var chest_price_growth := 1.5

@export_group("Prices")
## Цена предмета по редкости: обычный, магический, редкий, легендарный, проклятый (шаг 7).
@export var item_prices := PackedInt32Array([20, 55, 150, 450, 250])
@export var price_per_level := 0.2
## Переброс карт левел-апа: первый стоит reroll_base, каждый следующий — на reroll_base дороже.
@export var reroll_base := 10
## «Загадочный свёрток» (азарт, как у торговца Гиди в Diablo): веса редкостей предмета.
@export var gamble_weights := PackedFloat32Array([0, 60, 32, 8, 10])


func gold_mult(depth: int) -> float:
	return 1.0 + gold_per_level * depth


func price_mult(depth: int) -> float:
	return 1.0 + price_per_level * depth


## Цена сундука, когда герой уже открыл opened_before сундуков: 100, 150, 225, 338 …
func chest_price(opened_before: int) -> int:
	return roundi(chest_price_base * pow(chest_price_growth, opened_before))


func reroll_cost(rerolls_done: int) -> int:
	return reroll_base * (rerolls_done + 1)
