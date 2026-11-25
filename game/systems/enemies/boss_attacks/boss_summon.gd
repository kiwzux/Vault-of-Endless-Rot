class_name BossSummon
extends BossAttack
## Призыв: метки вокруг босса горят замах, затем из них встают count подручных enemy_id (со множителями
## босса, здоровье — health_share). Предел живых врагов волн (WaveTable.max_alive) не превышается.

@export var enemy_id: StringName = &"skeleton"
@export var health_share := 0.5
@export var spread := 40.0

const MARK_RADIUS := 9.0


func telegraph(cast: BossCast) -> void:
	var spots: Array[Vector2] = []
	var n := amount(cast)
	for i in n:
		var spot := cast.origin() + Vector2.RIGHT.rotated(TAU * i / n + cast.rng.randf()) * (cast.radius() + spread)
		if not cast.is_blocked(spot):
			spots.append(spot)
			cast.warn(spot, MARK_RADIUS, windup, color)
	cast.state["spots"] = spots


func strike(cast: BossCast) -> void:
	for spot: Vector2 in cast.state["spots"]:
		if not cast.summon(enemy_id, spot, health_share):
			return
