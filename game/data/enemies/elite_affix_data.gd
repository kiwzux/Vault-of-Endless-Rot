class_name EliteAffixData
extends Resource
## Аффикс элиты-«чемпиона» в стиле Diablo. Эффекты складываются, если у элиты несколько аффиксов.
## Числа: Быстрый, Каменная кожа, Взрывной, Вампир. Поведения (шаг 6): Огненный (горящий след),
## Ледяной (морозная вспышка вокруг), Телепортирующийся (перенос к герою), Призыватель (подручные).
## Каждое поведение предупреждает о себе телеграфом (Projectile «warn» или круг взрыва), кроме следа:
## он виден сам. Новый аффикс — новый .tres в data/enemies/elite_affixes/; логика — Enemy._tick_affixes.

@export var id: StringName
@export var name_key: String
## Цвет телеграфов и следов поведения; подпись элиты остаётся общей.
@export var color := Color(0.6, 0.75, 1.0)
@export var speed_mult := 1.0
@export var damage_taken_mult := 1.0
## Доля нанесённого вплотную урона, которую элита возвращает себе здоровьем.
@export var lifesteal := 0.0
## Урон взрыва после смерти (с задержкой — успеть отойти); 0 — не взрывается.
@export var explode_damage := 0.0

@export_group("Fire trail")
## Огненный след: пятно огня через каждые trail_step px пути; живёт trail_time с и жжёт героя внутри
## на trail_damage каждые 0,5 с (до множителя урона элиты). 0 — следа нет.
@export var trail_damage := 0.0
@export var trail_step := 26.0
@export var trail_time := 3.0
@export var trail_radius := 12.0

@export_group("Frost nova")
## Морозная вспышка: раз в nova_interval с вокруг элиты растёт круг-предупреждение (nova_windup с), затем
## урон nova_damage и холод — герой замедлен (Player.chill). 0 — вспышки нет.
@export var nova_interval := 0.0
@export var nova_radius := 56.0
@export var nova_damage := 0.0
@export var nova_windup := 1.0

@export_group("Teleport")
## Перенос к герою: раз в blink_interval с на месте прибытия (blink_distance от героя) горит метка
## blink_windup с, элита стоит; затем переносится. 0 — не переносится.
@export var blink_interval := 0.0
@export var blink_windup := 0.6
@export var blink_distance := 36.0
@export var blink_min_range := 90.0

@export_group("Summon")
## Призыв: раз в summon_interval с вокруг элиты загораются summon_count меток (0,6 с), из них встают
## подручные — тот же вид врага без аффиксов со здоровьем ×summon_health. 0 — не призывает.
@export var summon_interval := 0.0
@export var summon_count := 2
@export var summon_health := 0.4
