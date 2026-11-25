class_name WaveEntry
extends Resource
## Одна волна таблицы: пока идёт [start_time, end_time) секунд уровня, каждые interval секунд
## появляется batch врагов, тип выбирается по весам (ФТ-09).

@export var start_time := 0.0
@export var end_time := 60.0
@export var interval := 1.0
@export var batch := 1
@export var enemies: Array[EnemyData] = []
## Вес каждого типа из enemies, та же длина.
@export var weights := PackedFloat32Array()

## Веса с поправкой на дальнобойных (BalanceConfig.ranged_spawn_weight); считаются один раз.
var _picked_weights := PackedFloat32Array()


func is_active(time: float) -> bool:
	return time >= start_time and time < end_time


func pick(rng: RandomNumberGenerator) -> EnemyData:
	return enemies[rng.rand_weighted(pick_weights())]


## Веса выбора: враги с дальней атакой (выстрел, кольцо снарядов, навесной огонь) — ×ranged_spawn_weight.
func pick_weights() -> PackedFloat32Array:
	if _picked_weights.size() != weights.size():
		_picked_weights = weights.duplicate()
		for i in mini(enemies.size(), weights.size()):
			if is_ranged(enemies[i]):
				_picked_weights[i] *= DataRegistry.BALANCE.ranged_spawn_weight
	return _picked_weights


static func is_ranged(enemy: EnemyData) -> bool:
	return enemy != null and not enemy.is_boss and (enemy.shot_interval > 0.0 or enemy.ring_count > 0)
