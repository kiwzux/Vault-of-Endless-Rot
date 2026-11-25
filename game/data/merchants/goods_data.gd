class_name GoodsData
extends Resource
## Товар торговца, кроме экипировки (CR-14). Тексты — ключи таблицы переводов (НФТ-08).

## BELT_POTION — зелье в пояс (пьётся клавишей Q); BUFF — эликсир, временный бафф как у фонтана;
## LEVEL — плод Древа знаний (HoMM3): сразу новый уровень героя; GAMBLE — загадочный свёрток:
## случайный предмет по весам EconomyTable.gamble_weights (азарт, как у торговца Гиди в Diablo).
enum Effect { BELT_POTION, BUFF, LEVEL, GAMBLE }

@export var id: StringName
@export var name_key: String
@export var description_key: String
@export var effect := Effect.BELT_POTION
## Цена на первом уровне забега; дальше растёт на EconomyTable.price_per_level за уровень.
@export var price := 20
## Сколько штук у торговца на уровне.
@export var stock := 1
## BUFF: длительность, с, и характеристики героя (Player.STAT_*).
@export var duration := 0.0
@export var stats := {}
@export var icon_color := Color.WHITE
## Значок товара (атлас art/gen_icons.py, ItemIcon); пусто — флакон цвета icon_color, нарисованный кодом.
@export var icon: StringName
