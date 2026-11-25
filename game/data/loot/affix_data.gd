class_name AffixData
extends Resource
## Случайный аффикс предмета (CR-07, шаг 7): характеристика героя и диапазон значения.
## Вид: суффикс («Шлем силы» — name_key в родительном падеже), префикс («Пылающий клинок» — прилагательное:
## ключ name_key_M / _F / _N / _PL по роду базы, ItemBaseData.gender; _N — средний, «Пылающее кольцо») или
## проклятие — штраф проклятого
## предмета (значения отрицательные, name_key — имя проклятия: «Иссушение»).
## Пул по типу предмета и уровню: slots (пусто — любые слоты) и min_depth.
## Новый аффикс — новый .tres в data/loot/affixes/.

enum Kind { SUFFIX, PREFIX, CURSE }

@export var id: StringName
@export var name_key: String
@export var kind := Kind.SUFFIX
@export var stat: StringName
@export var min_value := 0.0
@export var max_value := 0.0
## Слоты, на которых аффикс бывает (ItemBaseData.Slot); пусто — на любых.
@export var slots: Array[int] = []
## С этого уровня глубины забега аффикс попадает в пул.
@export var min_depth := 0


func fits(base: ItemBaseData, depth: int) -> bool:
	return depth >= min_depth and (slots.is_empty() or int(base.slot) in slots)


## Имя для названия предмета: у префикса — форма по роду базы.
func display_key(base: ItemBaseData) -> String:
	return "%s_%s" % [name_key, String(base.gender).to_upper()] if kind == Kind.PREFIX else name_key
