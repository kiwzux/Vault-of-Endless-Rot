class_name SkillData
extends UpgradeData
## Навык (шаг 3, R4): базовое действие (SkillAction) + теги + встроенные модификаторы + рост по уровням.
## Срабатывает сам по перезарядке (ФТ-08, автоатака) и занимает слот (Kind.WEAPON, до
## UpgradeRules.max_weapons). Новый навык из готовых действий и модификаторов — только новый .tres.
##
## Числа в момент срабатывания собирает SkillStats: уровень навыка, модификаторы (свои, классовые,
## руны забега) и характеристики героя (Мощь, Удача, Размах, Залп, Спешка).

const MIN_COOLDOWN := 0.15

## Что делает навык: снаряд, конус, аура, цепь, орбита, удар с неба, зона, луч, рывок, призыв, ловушка.
@export var action: SkillAction
## Теги (TagDef): стихия и форма — по ним работают прибавки «по тегу», сопротивления и модификаторы.
@export var tags: Array[StringName] = []
## Статусы, которые накладывает каждое попадание.
@export var on_hit: Array[StatusApplication] = []
## Встроенные модификаторы (руны), действуют всегда.
@export var modifiers: Array[SkillModifier] = []

@export_group("Scaling")
@export var damage := 10.0
@export var damage_per_level := 3.0
@export var cooldown := 1.0
@export var cooldown_per_level := -0.05
## Дальность поиска цели; у ауры, конуса и орбиты — их радиус (с Размахом героя).
@export var attack_range := 160.0
@export var range_per_level := 0.0
## Количество: снаряды, прыжки цепи, сферы, метеоры, зоны, ловушки, призванные.
@export var amount := 1
## Уровни, на которых amount растёт на 1.
@export var amount_levels := PackedInt32Array()
## Сколько врагов снаряд прошивает сверх первого.
@export var pierce := 0
@export var pierce_levels := PackedInt32Array()
## Радиус области: взрыв, зона, ловушка; 0 — нет.
@export var area := 0.0
@export var area_per_level := 0.0
## Длительность: орбита, зона, луч, призыв, ловушка, с.
@export var duration := 0.0
@export var duration_per_level := 0.0

@export_group("Look")
## Вид снаряда или следа вместо стандартного для действия: fireball, ember, smite, dagger, spear,
## sickle, acid, bolt; у орбиты — bats, flames.
@export var fx_kind: StringName
@export var fx_color := Color.WHITE
## Стихия облика (шаг 11.21, SkillVfx): fire, cold, lightning, poison, blood, dark, holy, physical. Пусто — первый
## тег-стихия навыка.
@export var fx_element: StringName

@export_group("Evolution")
## Облик эволюции: ступень эволюции UpgradeRules.evolution_transform_stage превращает навык в него
## (ступени — каждые UpgradeRules.evolution_step уровней навыка, UpgradePool). null — у навыка только ступени.
@export var evolution: SkillData
## Эволюция заменяет базовый навык и берёт его уровень, руны и ступени; впервые выпадает только картой эволюции.
@export var is_evolution := false


func damage_at(level: int) -> float:
	return damage + damage_per_level * (level - 1)


func cooldown_at(level: int) -> float:
	return maxf(MIN_COOLDOWN, cooldown + cooldown_per_level * (level - 1))


func range_at(level: int) -> float:
	return attack_range + range_per_level * (level - 1)


func amount_at(level: int) -> int:
	return amount + _count_reached(amount_levels, level)


func pierce_at(level: int) -> int:
	return pierce + _count_reached(pierce_levels, level)


func area_at(level: int) -> float:
	return area + area_per_level * (level - 1)


func duration_at(level: int) -> float:
	return duration + duration_per_level * (level - 1)


static func _count_reached(levels: PackedInt32Array, level: int) -> int:
	var n := 0
	for l in levels:
		if level >= l:
			n += 1
	return n
