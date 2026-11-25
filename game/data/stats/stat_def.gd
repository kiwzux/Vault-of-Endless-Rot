class_name StatDef
extends Resource
## Характеристика героя (шаг 2, R2): подпись в подсказках, формат числа, предел действующего значения
## и может ли она выпасть на предмете. Одна точка правды для предметов, пассивок, талантов, листа героя
## и проверки предметов, пришедших по сети. Что характеристика делает — в коде (Player, Enemy, системы).
##
## Характеристика «по тегу» — id вида «might:fire»: та же характеристика, но действует только на удары
## с этим тегом (TagDef). Отдельный StatDef ей не нужен: подпись и формат берутся у базовой.

enum Format { FLAT, PERCENT }

@export var id: StringName
## Строка подсказки с {value}: «+{value}% урона».
@export var line_key: String
@export var format := Format.PERCENT
## Предел действующего значения (Уклонение — 0.5); 0 — без предела.
@export var cap := 0.0
## Бывает на предметах (аффикс или встроенная характеристика базы): только такие пропускает проверка
## предметов из сети (ItemRoller.is_valid).
@export var on_items := false
## Действует целая часть (Залп): в подсказке — округление вниз.
@export var whole := false


func is_percent() -> bool:
	return format == Format.PERCENT


## Действующее значение с учётом предела.
func capped(value: float) -> float:
	return minf(value, cap) if cap > 0.0 else value
