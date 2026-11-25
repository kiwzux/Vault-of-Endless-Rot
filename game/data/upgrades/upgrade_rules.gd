class_name UpgradeRules
extends Resource
## Правила опыта и карт левел-апа (ФТ-10, CR-15). Оружие занимает слоты, пассивки — нет: копятся без предела
## числа, у каждой до 25 уровней; у навыка — до 20 уровней и 4 ступени эволюции. Редкость карты (как в Megabonk) решает, сколько уровней она даёт сразу.
## Шаг 4: карты рун и сродство класса.

@export var max_weapons := 6
## Редкость: обычная, редкая, эпическая, легендарная — вес выпадения и сколько уровней даёт карта.
@export var rarity_weights := PackedFloat32Array([100.0, 10.0, 3.0, 0.8])
@export var rarity_levels := PackedInt32Array([1, 2, 3, 5])
## «Удача» героя повышает шанс редких карт: вес редких ×(1 + luck_factor × шанс удачного удара).
@export var luck_factor := 2.0

@export_group("Experience")
## Кривая опыта и рост кристаллов — в BalanceConfig (data/balance/balance.tres).
## Магнит душ (Vacuum из Vampire Survivors): шанс выпасть с элиты и с обычного врага.
@export var magnet_elite_chance := 0.025
@export var magnet_enemy_chance := 0.0002

@export_group("Variety")
## Антиповтор: множитель веса карты из прошлого предложения, позапрошлого и т. д.
@export var repeat_weights := PackedFloat32Array([0.15, 0.45])
## Изгнание (Vampire Survivors): столько карт за забег можно убрать из выпадения насовсем.
@export var banishes := 3
## Сродство класса (шаг 4): навыки с тегами класса (HeroData.affinity_tags) выпадают во столько раз чаще.
@export var affinity_weight := 2.0

@export_group("Evolution")
## Ступени эволюции навыка: каждые evolution_step уровней навыка (5, 10, 15, 20) — карта следующей ступени,
## всего evolution_stages. Ступень evolution_transform_stage у навыка с обликом эволюции (SkillData.evolution)
## превращает его в этот облик. Карта ступени выпадает в обычных предложениях — не дожидаясь, пока всё вкачано;
## в одном предложении не больше evolution_cards_per_offer таких карт.
@export var evolution_step := 5
@export var evolution_stages := 4
@export var evolution_transform_stage := 2
@export var evolution_cards_per_offer := 1
## Что даёт каждая ступень навыку: урон +доля, перезарядка −доля, область +доля; +1 к количеству на каждой
## evolution_amount_every-й ступени.
@export var evolution_damage := 0.25
@export var evolution_cooldown := 0.06
@export var evolution_area := 0.1
@export var evolution_amount_every := 2

@export_group("Runes")
## Карты рун (шаг 4): руна забега в навык героя. Появляются с этого уровня героя.
@export var rune_unlock_level := 3
## Шанс, что в предложении одна карта — руна (вместо обычной). Запасные карты руны заменяют всегда.
@export var rune_card_chance := 0.35
## Сколько рун забега помещается в навык (встроенные руны навыка не в счёт).
@export var runes_per_skill := 3
## Вес выпадения руны по её редкости: обычная, редкая, эпическая, легендарная. «Удача» героя повышает
## вес редких так же, как у карт (luck_factor).
@export var rune_rarity_weights := PackedFloat32Array([100.0, 40.0, 14.0, 4.0])
