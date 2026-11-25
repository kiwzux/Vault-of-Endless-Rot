class_name BossNova
extends BossAttack
## Волна: огромный взрыв вокруг босса — круг растёт весь замах, кто не вышел, получает урон. После взрыва —
## кольцо из count снарядов (0 — без кольца), чтобы отбежавшие не стояли спокойно.

@export var blast_radius := 90.0
@export var shard_speed := 90.0
@export var shard_reach := 260.0
## Доля урона у снарядов кольца.
@export var shard_share := 0.6


func telegraph(cast: BossCast) -> void:
	cast.blast(cast.origin(), blast_radius, windup, cast.damage_of(self), color)


func strike(cast: BossCast) -> void:
	if count <= 0:
		return
	var n := amount(cast)
	for i in n:
		cast.shard(cast.origin(), Vector2.RIGHT.rotated(TAU * i / n + cast.aim.angle()), shard_speed, shard_reach,
				cast.damage_of(self, shard_share), color)
