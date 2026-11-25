class_name BossPools
extends BossAttack
## Лужи: под каждым героем и ещё count − 1 вокруг него — круг-предупреждение на замах, затем зона, которая жжёт
## zone_time секунд. Поле боя сжимается: стоять на месте нельзя.

@export var zone_radius := 26.0
@export var zone_time := 6.0
@export var zone_tick := 0.5
@export var scatter := 60.0


func telegraph(cast: BossCast) -> void:
	var spots: Array[Vector2] = []
	for hero in cast.heroes():
		spots.append(hero.global_position)
		for i in amount(cast) - 1:
			var spot: Vector2 = hero.global_position + Vector2.RIGHT.rotated(cast.rng.randf() * TAU) * cast.rng.randf_range(
					scatter * 0.5, scatter)
			if not cast.is_blocked(spot):
				spots.append(spot)
	for spot in spots:
		cast.warn(spot, zone_radius, windup, color)
	cast.state["spots"] = spots


func strike(cast: BossCast) -> void:
	for spot: Vector2 in cast.state["spots"]:
		cast.zone(spot, zone_radius, zone_time, zone_tick, cast.damage_of(self), color)
