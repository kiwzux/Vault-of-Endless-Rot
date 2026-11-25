class_name PassiveData
extends UpgradeData
## Пассивка: каждый уровень добавляет per_level к характеристике stat героя (см. Player.STAT_*).
## Особый stat «heal» не копится, а сразу лечит долю здоровья.
## bonus_stats — дополнительные характеристики за уровень (Проклятие: больше врагов, но и опыта с золотом).

@export var stat: StringName
@export var per_level := 0.1
@export var bonus_stats := {}
