class_name StatusEffectData
extends Resource
## Статусный эффект на враге (шаг 2, R3): горение, яд, кровотечение, замедление, холод, заморозка,
## оглушение, порча, страх, масло. Поведение задают числа здесь; накладывает, тикает и снимает эффекты
## StatusSystem на хосте. Новый эффект из этих свойств — только новый .tres.
##
## Стаки: каждое наложение добавляет стаки (до max_stacks) и продлевает эффект. Урон со временем:
## dot_share — доля урона удара, наложившего эффект, в секунду за стак; силу стака задаёт сильнейшее
## наложение. Контроль боссы терпят слабее: замедление, оглушение и страх × (1 − boss_resist).

@export var id: StringName
@export var name_key: String
## Теги урона эффекта (горение — fire): по ним работают сопротивления врага.
@export var tags: Array[StringName] = []
@export var max_stacks := 1
@export var duration := 3.0

@export_group("Damage over time")
@export var dot_share := 0.0
@export var tick_interval := 0.5

@export_group("Control")
## Доля скорости, которую теряет враг (× сила наложения); действует сильнейшее замедление.
@export var slow := 0.0
## Враг стоит на месте и не атакует (оглушение, заморозка).
@export var stun := false
## Враг бежит от героев и не атакует.
@export var fear := false
## Враг получает больше урона: доля за стак (порча).
@export var vulnerability_per_stack := 0.0
@export_range(0.0, 1.0) var boss_resist := 0.0

@export_group("Look")
@export var color := Color.WHITE
## Бит 1–7 во флагах снимка врага: клиенты видят эффект оттенком; 0 — не показывать. Эффекты с одним
## битом выглядят одинаково (холод и замедление).
@export_range(0, 7) var visual_bit := 0
## Чей оттенок виден, если на враге несколько эффектов: больше — важнее.
@export var tint_priority := 0


func is_control() -> bool:
	return slow > 0.0 or stun or fear
