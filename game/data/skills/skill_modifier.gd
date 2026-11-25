class_name SkillModifier
extends Resource
## Модификатор навыка — руна (шаг 3, R4): прибавки к числам навыка, приёмы снарядов (раскол, рикошет,
## возврат), взрыв убитого врага, статусы и теги. Действует на навык, если подходит по тегам и действию
## (SkillStats.fits). Бывает встроенным (SkillData.modifiers), классовым (HeroData.class_modifiers)
## и руной забега (карты левел-апа — шаг 4). Новый модификатор — только .tres.

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

@export var id: StringName
@export var name_key: String
@export var description_key: String
@export var rarity := Rarity.COMMON
@export var icon_color := Color.WHITE
## Значок в атласе (art/gen_skill_icons.py, ItemIcon; шаг 11.26); пусто — по id руны.
@export var icon: StringName
## Подходит навыкам хотя бы с одним из этих тегов; пусто — любым.
@export var requires_tags: Array[StringName] = []
## Подходит только этим действиям (SkillAction.kind(): projectile, cone…); пусто — любым.
@export var requires_actions: Array[StringName] = []

@export_group("Numbers")
## Доли: +0.2 — на 20 % больше; у перезарядки −0.1 — на 10 % короче.
@export var damage := 0.0
@export var cooldown := 0.0
@export var area := 0.0
@export var range_bonus := 0.0
@export var duration := 0.0
@export var speed := 0.0
@export var amount := 0
@export var pierce := 0
## Прибавка к шансу удачного удара навыка и Вампиризм навыка (доля нанесённого урона).
@export var crit := 0.0
@export var lifesteal := 0.0

@export_group("Projectiles")
## При первом попадании снаряд раскалывается на split осколков веером, у каждого split_share урона.
@export var split := 0
@export var split_share := 0.5
## Снаряд отскакивает к следующему врагу ricochet раз.
@export var ricochet := 0
## Снаряд долетает до края дальности и возвращается.
@export var returns := false

@export_group("On kill")
## Убитый навыком враг взрывается: доля урона удара и радиус.
@export var kill_blast_share := 0.0
@export var kill_blast_radius := 0.0

@export_group("Statuses and tags")
@export var statuses: Array[StatusApplication] = []
## Навык получает эти теги: на него начинают действовать прибавки и модификаторы этих тегов.
@export var add_tags: Array[StringName] = []


## Имя значка в атласе: шестигранный рунный камень, обод по редкости (шаг 11.26).
func icon_name() -> StringName:
	return icon if icon != &"" else id
