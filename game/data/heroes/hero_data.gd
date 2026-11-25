class_name HeroData
extends Resource
## Описание героя. Тексты — ключи таблицы переводов (НФТ-08).

@export var id: StringName
## Порядок показа в хабе (DataRegistry сортирует по нему).
@export var order := 0
@export var name_key: String
@export var description_key: String
@export var max_health := 100.0
@export var move_speed := 90.0
@export var starting_weapon: StringName
## leadership / necromancy / mana_shield — см. Player и HeroPassiveSystem.
@export var passive: StringName
## Мана есть только у героев, которым она нужна (Мана-щит); 0 — сфера маны пустая.
@export var max_mana := 0.0
@export var mana_regen := 0.0
## Лист кадров 96 px из объёмной модели (art/gen_heroes.py, шаг 11.3), раскладка — рядом в .json (SheetLayout):
## покой, ходьба, удар стоя и удар на ходу; герой смотрит вправо.
@export var sprite_sheet: Texture2D

@export_group("Class trait")
## Черта класса из данных (шаг 3): прибавки к характеристикам на весь забег (Player.STAT_*)…
@export var base_stats := {}
## …и модификаторы, которые действуют на все подходящие навыки героя (Пиромания: огненные навыки
## поджигают). Пассивки Лидерство, Некромантия и Мана-щит живут в коде (passive).
@export var class_modifiers: Array[SkillModifier] = []
## Сродство класса (шаг 4): навыки хотя бы с одним из этих тегов выпадают в левел-апе чаще
## (UpgradeRules.affinity_weight).
@export var affinity_tags: Array[StringName] = []


## Область портрета в листе — первый кадр покоя лицом к камере (блок "s", шаг 11.11; у листа без направлений —
## первый кадр).
func portrait_region() -> Rect2:
	var layout := SheetLayout.of(sprite_sheet)
	return layout.region(layout.frame(&"idle", 0, 0, layout.dir_index("s"))) if layout != null else Rect2()


## Крупный план для маленьких портретов (панель союзников): голова и плечи из первого кадра покоя —
## квадрат в верхней середине кадра (фигура стоит по середине кадра, голова — в верхней трети).
func portrait_face_region() -> Rect2:
	var frame := portrait_region()
	var side := frame.size.x * 0.46
	return Rect2(frame.position + Vector2((frame.size.x - side) / 2.0, frame.size.y * 0.17), Vector2(side, side))
