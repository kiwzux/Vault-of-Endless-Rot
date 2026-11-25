class_name UniqueItemData
extends Resource
## Легендарный (оранжевый) предмет (CR-07, шаг 7): своё имя, фиксированные характеристики и легендарная руна —
## модификатор навыков (SkillModifier), который действует на все подходящие навыки героя, пока предмет надет
## (Player.skill_modifiers): «огненные навыки поджигают», «снаряды рикошетят», «убитые взрываются».
## В словаре предмета он — ключ «unique» (имя ключа прежнее: по нему работают сеть и трофеи «Летописи»).
## Новая легендарка — новый .tres в data/loot/uniques/, руна — встроенный в него ресурс.

@export var id: StringName
@export var name_key: String
@export var base: ItemBaseData
## Характеристика героя (Player.STAT_*) → значение.
@export var stats := {}
## Легендарная руна; null — только характеристики.
@export var modifier: SkillModifier
## Свой значок (атлас art/gen_icons.py, ItemIcon); пусто — значок базы.
@export var icon: StringName
