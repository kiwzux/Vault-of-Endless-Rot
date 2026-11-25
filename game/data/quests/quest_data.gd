class_name QuestData
extends Resource
## Задание Доски заданий в Убежище (шаг 10, расширение CR-04): цель по «Летописи» (MetaProfile) и
## награда — открытие класса или навыка и/или души. Награду забирают в Убежище.
## Что закрыто, задаёт само задание: класс или навык, который стоит в unlock хотя бы одного задания,
## закрыт, пока это задание не выполнено и награда не получена (DataRegistry.quest_for_unlock).
## Новое задание — новый .tres в data/quests/, без правки кода.

## Счётчики «Летописи» (MetaProfile.count). depth — лучший результат, остальные копятся за все забеги.
const COUNTERS: Array[StringName] = [
	&"runs", &"victories", &"hardcore_victories", &"kills", &"levels", &"depth", &"bosses", &"chests",
	&"revives", &"trophies", &"bestiary", &"lore", &"rescued", &"secrets", &"heat",
]

@export var id: StringName
## Порядок на доске (DataRegistry сортирует по нему).
@export var order := 0
@export var name_key: String
## Текст цели; {target} — нужное значение счётчика.
@export var description_key: String
@export var counter: StringName
@export var target := 1
## Что открывает: id героя (HeroData) или навыка (UpgradeData); пусто — только души.
@export var unlock: StringName
@export var reward_souls := 0
