class_name BossCharge
extends BossAttack
## Рывки: count бросков по прямой к герою. Перед каждым — полоса на земле (замах windup, следующие — pause),
## направление закреплено с начала полосы — от рывка уходят в сторону. Касание во время рывка ранит
## (урон касания босса), у стены рывок кончается. trail_damage > 0 — за боссом остаются горящие пятна.

@export var speed := 280.0
@export var dash_time := 0.5
## Замах перед вторым и следующими рывками, с.
@export var pause := 0.5
@export var trail_damage := 0.0
@export var trail_radius := 16.0
@export var trail_time := 3.0
@export var trail_step := 30.0


func telegraph(cast: BossCast) -> void:
	_show_lane(cast, windup)


func strike(cast: BossCast) -> void:
	cast.state["dash"] = 1
	cast.state["dashing"] = true
	cast.state["left"] = dash_time
	cast.state["trail_from"] = cast.origin()


func tick(cast: BossCast, delta: float) -> bool:
	var left: float = cast.state["left"] - delta
	cast.state["left"] = left
	if not cast.state["dashing"]:
		if left <= 0.0:  # замах следующего рывка кончился
			cast.state["dashing"] = true
			cast.state["left"] = dash_time
		return true
	var hit_wall := cast.dash(cast.aim, speed, delta)
	_leave_trail(cast)
	if left > 0.0 and not hit_wall:
		return true
	if int(cast.state["dash"]) >= amount(cast):
		return false
	cast.state["dash"] = int(cast.state["dash"]) + 1
	cast.state["dashing"] = false
	cast.state["left"] = pause
	var hero: Variant = cast.nearest()
	if hero == null:
		return false
	cast.aim = cast.origin().direction_to(hero.global_position)
	_show_lane(cast, pause)
	return true


func _show_lane(cast: BossCast, fuse: float) -> void:
	cast.warn_line(cast.origin(), cast.aim, speed * dash_time, cast.radius() + 2.0, fuse, color)


func _leave_trail(cast: BossCast) -> void:
	if trail_damage <= 0.0 or cast.origin().distance_to(cast.state["trail_from"]) < trail_step:
		return
	cast.state["trail_from"] = cast.origin()
	cast.zone(cast.origin(), trail_radius, trail_time, 0.5, trail_damage * cast.damage_mult(), color)
