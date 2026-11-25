class_name UpgradeData
extends Resource
## Карта улучшения для левел-апа (ФТ-10). Тексты — ключи таблицы переводов (НФТ-08).

## FILLER — запасные карты без предела уровня: ими добивается выбор до 3 карт,
## когда обычные улучшения закончились.
enum Kind { WEAPON, PASSIVE, FILLER }

@export var id: StringName
@export var kind := Kind.PASSIVE
@export var name_key: String
@export var description_key: String
## 0 — без предела (только для FILLER).
@export var max_level := 5
@export var icon_color := Color.WHITE
## Значок в атласе (art/gen_skill_icons.py, ItemIcon); пусто — по виду и id: skill_<id> у навыков, passive_<id> у
## пассивок и даров.
@export var icon: StringName


func is_maxed(level: int) -> bool:
	return max_level > 0 and level >= max_level


## Имя значка в атласе (шаг 11.18).
func icon_name() -> StringName:
	if icon != &"":
		return icon
	return StringName(("skill_" if kind == Kind.WEAPON else "passive_") + String(id))
