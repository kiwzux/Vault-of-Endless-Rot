class_name BossCross
extends BossAttack
## Крест: count лучей из взрывов от босса — первый луч в сторону цели, остальные поровну по кругу. Взрывы
## луча загораются по очереди от босса наружу (каждый — свой растущий круг), безопасно — между лучами.

@export var blasts_per_line := 6
@export var spacing := 34.0
@export var blast_radius := 18.0
## Задержка каждого следующего взрыва луча, с.
@export var step_delay := 0.08


func telegraph(cast: BossCast) -> void:
	var lines := amount(cast)
	for line in lines:
		var dir := cast.aim.rotated(TAU * line / lines)
		for i in blasts_per_line:
			var at := cast.origin() + dir * (cast.radius() + spacing * (i + 0.5))
			if cast.is_blocked(at):
				break  # луч обрывается у стены
			cast.blast(at, blast_radius, windup + step_delay * i, cast.damage_of(self), color)
