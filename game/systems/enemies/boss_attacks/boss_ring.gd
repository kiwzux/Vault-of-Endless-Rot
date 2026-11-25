class_name BossRing
extends BossAttack
## Кольцо: count снарядов во все стороны, waves колец подряд, каждое повёрнуто на полшага — между снарядами
## остаются щели, в них и надо встать. Телеграф — круг вокруг босса.

@export var speed := 95.0
@export var reach := 280.0
@export var waves := 1
@export var wave_gap := 0.4
## Поворот следующего кольца — доля шага между снарядами.
@export var twist := 0.5

const TELL_MARGIN := 26.0


func telegraph(cast: BossCast) -> void:
	cast.warn(cast.origin(), cast.radius() + TELL_MARGIN, windup, color)


func strike(cast: BossCast) -> void:
	cast.state["fired"] = 0
	_fire(cast)


func tick(cast: BossCast, _delta: float) -> bool:
	var fired: int = cast.state["fired"]
	if fired >= waves:
		return false
	if cast.time >= fired * wave_gap:
		_fire(cast)
	return true


func _fire(cast: BossCast) -> void:
	var fired: int = cast.state["fired"]
	var n := amount(cast)
	var step := TAU / n
	var offset := cast.aim.angle() + step * twist * fired
	for i in n:
		cast.shard(cast.origin(), Vector2.RIGHT.rotated(offset + step * i), speed, reach, cast.damage_of(self), color)
	cast.state["fired"] = fired + 1
