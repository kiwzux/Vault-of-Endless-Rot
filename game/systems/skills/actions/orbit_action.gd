class_name OrbitAction
extends SkillAction
## Орбита (шаг 3; была схема ORBIT оружия): сферы кружат вокруг героя длительность навыка независимо
## от врагов (как Библия в Vampire Survivors) и ранят тех, кого задевают, — одного врага не чаще
## HIT_INTERVAL. Видимый след — один узел orbit: он сам идёт за героем на всех узлах сети.

const ORB_RADIUS := 5.0
const HIT_INTERVAL := 0.5

## Угловая скорость, рад/с.
@export var angular_speed := 3.0


func kind() -> StringName:
	return &"orbit"


func execute(rt: SkillRuntime) -> bool:
	var s := rt.stats
	rt.state["orbit_left"] = s.duration
	rt.state["count"] = s.amount
	rt.state["radius"] = s.range * s.area_mult
	rt.effect({
		"type": &"orbit", "pos": rt.player.global_position, "owner": rt.player.peer_id(), "count": s.amount,
		"radius": rt.state["radius"], "phase": rt.state.get("angle", 0.0), "speed": angular_speed,
		"duration": s.duration, "look": rt.data.fx_kind,
	})
	return true


func tick(rt: SkillRuntime, delta: float) -> void:
	var left: float = rt.state.get("orbit_left", 0.0)
	if left <= 0.0:
		return
	left -= delta
	rt.state["orbit_left"] = left
	var angle := fmod(float(rt.state.get("angle", 0.0)) + angular_speed * delta, TAU)
	rt.state["angle"] = angle
	var hits: Dictionary = rt.state.get_or_add("hits", {})
	if left <= 0.0:
		hits.clear()
		return
	var count: int = rt.state["count"]
	var radius: float = rt.state["radius"]
	for i in count:
		var pos := rt.player.global_position + Vector2.RIGHT.rotated(angle + TAU * i / count) * radius
		for e in rt.world.director.enemies_in_radius(pos, ORB_RADIUS):
			var id := e.get_instance_id()
			if hits.get(id, 0.0) > rt.time:
				continue
			hits[id] = rt.time + HIT_INTERVAL
			rt.hit(e)
