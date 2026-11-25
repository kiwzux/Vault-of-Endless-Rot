class_name BossFan
extends BossAttack
## Веер: volleys залпов по count снарядов в секторе spread_deg в сторону цели. Телеграф — полоса к цели;
## первый залп летит туда, где цель стояла в начале замаха, следующие — снова в ближайшего героя.

@export var spread_deg := 50.0
@export var volleys := 1
@export var volley_gap := 0.35
@export var speed := 130.0
@export var reach := 320.0

const TELL_HALF_WIDTH := 10.0


func telegraph(cast: BossCast) -> void:
	cast.warn_line(cast.origin(), cast.aim, reach * 0.6, TELL_HALF_WIDTH, windup, color)


func strike(cast: BossCast) -> void:
	cast.state["fired"] = 0
	_fire(cast, cast.aim)


func tick(cast: BossCast, _delta: float) -> bool:
	var fired: int = cast.state["fired"]
	if fired >= volleys:
		return false
	if cast.time >= fired * volley_gap:
		var hero: Variant = cast.nearest()
		_fire(cast, cast.origin().direction_to(hero.global_position) if hero != null else cast.aim)
	return true


func _fire(cast: BossCast, dir: Vector2) -> void:
	var n := amount(cast)
	var spread := deg_to_rad(spread_deg)
	for i in n:
		var t := 0.0 if n == 1 else float(i) / (n - 1) - 0.5
		cast.shard(cast.origin(), dir.rotated(t * spread), speed, reach, cast.damage_of(self), color)
	cast.state["fired"] = int(cast.state["fired"]) + 1
