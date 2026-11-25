class_name BeamAction
extends SkillAction
## Луч (шаг 3): от героя в сторону ближайшего врага на всю дальность навыка, держится его длительность
## и бьёт всех на линии каждые tick_interval секунд (урон навыка — за тик). Направление задаётся в начале:
## луч идёт за героем, но не поворачивается. Клиентам хватает одного следа beam — он сам идёт за героем.

@export var width := 8.0
@export var tick_interval := 0.25


func kind() -> StringName:
	return &"beam"


func execute(rt: SkillRuntime) -> bool:
	var origin := rt.player.global_position
	var target := rt.world.director.nearest_enemy(origin, rt.stats.range)
	if target == null:
		return false
	var dir := origin.direction_to(target.global_position)
	rt.state["beam_left"] = rt.stats.duration
	rt.state["beam_dir"] = dir
	rt.state["beam_tick"] = 0.0
	rt.effect({
		"type": &"beam", "pos": origin, "owner": rt.player.peer_id(), "dir": dir, "radius": rt.stats.range,
		"width": width * rt.stats.area_mult, "duration": rt.stats.duration,
	})
	return true


func tick(rt: SkillRuntime, delta: float) -> void:
	var left: float = rt.state.get("beam_left", 0.0)
	if left <= 0.0:
		return
	rt.state["beam_left"] = left - delta
	var next: float = rt.state["beam_tick"]
	next -= delta
	if next > 0.0:
		rt.state["beam_tick"] = next
		return
	rt.state["beam_tick"] = next + tick_interval
	var dir: Vector2 = rt.state["beam_dir"]
	var from := rt.player.global_position
	for e in enemies_on_line(rt.world, from, from + dir * rt.stats.range, width * rt.stats.area_mult):
		rt.hit(e)


## Враги, чей круг пересекает отрезок from → to шириной width.
static func enemies_on_line(world: World, from: Vector2, to: Vector2, width: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	var middle := (from + to) / 2.0
	for e in world.director.enemies_in_radius(middle, from.distance_to(to) / 2.0 + width):
		var closest := Geometry2D.get_closest_point_to_segment(e.global_position, from, to)
		if closest.distance_to(e.global_position) <= width / 2.0 + e.radius:
			result.append(e)
	return result
