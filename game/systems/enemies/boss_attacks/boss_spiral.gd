class_name BossSpiral
extends BossAttack
## Спираль: count рукавов снарядов вращаются вокруг босса duration секунд. Уходить — по кругу вслед за
## вращением или подальше. Телеграф — круг вокруг босса; направление вращения — случайное.

@export var duration := 3.0
## Снарядов в секунду на рукав.
@export var rate := 4.0
## Скорость вращения, рад/с.
@export var turn_speed := 1.6
@export var speed := 90.0
@export var reach := 300.0

const TELL_MARGIN := 30.0


func telegraph(cast: BossCast) -> void:
	cast.warn(cast.origin(), cast.radius() + TELL_MARGIN, windup, color)
	cast.state["turn"] = turn_speed if cast.rng.randf() < 0.5 else -turn_speed


func strike(cast: BossCast) -> void:
	cast.state["shots"] = 0


func tick(cast: BossCast, _delta: float) -> bool:
	if cast.time >= duration:
		return false
	var due := floori(cast.time * rate) + 1
	var arms := amount(cast)
	while int(cast.state["shots"]) < due:
		var shot: int = cast.state["shots"]
		var angle := cast.aim.angle() + float(cast.state["turn"]) * shot / rate
		for arm in arms:
			cast.shard(cast.origin(), Vector2.RIGHT.rotated(angle + TAU * arm / arms), speed, reach,
					cast.damage_of(self), color)
		cast.state["shots"] = shot + 1
	return true
