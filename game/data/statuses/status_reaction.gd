class_name StatusReaction
extends Resource
## Реакция статусов (шаг 2): на враге уже есть requires (не меньше min_stacks стаков), и на него ложится
## trigger — срабатывает эффект. Горение по маслу — взрыв; пятый стак холода — заморозка; пятый стак
## кровотечения — кровоизлияние. requires == trigger — порог стаков одного эффекта.

@export var id: StringName
@export var name_key: String
@export var requires: StringName
@export var trigger: StringName
@export var min_stacks := 1
## Снять requires после срабатывания.
@export var consume := true

@export_group("Burst")
## Урон = урон удара-триггера × burst_share × стаки requires; 0 — без урона.
@export var burst_share := 0.0
## Радиус взрыва; 0 — урон только по самому врагу.
@export var burst_radius := 0.0
@export var burst_tags: Array[StringName] = []

@export_group("Status")
## Наложить этот эффект (заморозка); пусто — нет.
@export var apply_status: StringName
@export var color := Color.WHITE
