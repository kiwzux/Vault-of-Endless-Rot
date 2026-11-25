class_name BossRain
extends BossAttack
## Дождь взрывов (метеоры, кости с неба, гнилые плевки): waves волн; в каждой — взрыв под каждым героем
## и ещё count − 1 вокруг него в scatter px. Телеграф — сам взрыв: его круг растёт fuse секунд.

@export var blast_radius := 30.0
@export var fuse := 1.1
@export var scatter := 70.0
@export var waves := 1
@export var wave_gap := 0.7


func telegraph(cast: BossCast) -> void:
	cast.pulse(cast.origin(), cast.radius() + 10.0, color)  # босс «колдует»


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
	for hero in cast.heroes():
		var at: Vector2 = hero.global_position
		cast.blast(at, blast_radius, fuse, cast.damage_of(self), color)
		for i in amount(cast) - 1:
			var offset := Vector2.RIGHT.rotated(cast.rng.randf() * TAU) * cast.rng.randf_range(scatter * 0.4, scatter)
			if not cast.is_blocked(at + offset):
				cast.blast(at + offset, blast_radius, fuse + cast.rng.randf() * 0.3, cast.damage_of(self), color)
	cast.state["fired"] = int(cast.state["fired"]) + 1
