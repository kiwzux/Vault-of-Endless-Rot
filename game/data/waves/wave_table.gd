class_name WaveTable
extends Resource
## Расписание волн уровня и его босс (ФТ-09). Время — секунды от начала уровня.

## Предел одновременно живых врагов: ограничивает трафик синхронизации (НФТ-07).
@export var max_alive := 300
## Появляется ровно один раз, когда истёк таймер уровня.
@export var boss: EnemyData
@export var waves: Array[WaveEntry] = []
