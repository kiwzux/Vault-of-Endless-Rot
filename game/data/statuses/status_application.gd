class_name StatusApplication
extends Resource
## Попытка наложить статус ударом (шаг 2): какой, с каким шансом, сколько стаков и с какой силой.
## Лежит в данных навыка (SkillData.on_hit); дальше — в модификаторах навыков и аффиксах предметов.

@export var status: StringName
@export_range(0.0, 1.0) var chance := 1.0
@export var stacks := 1
## Множитель силы: урона со временем и замедления (Пурга холоднее Кольца холода).
@export var potency := 1.0
## Своя длительность, с; 0 — из StatusEffectData.
@export var duration := 0.0
