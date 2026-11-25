class_name ConeAction
extends SkillAction
## Удар конусом (шаг 3; была схема ARC оружия): по всем врагам в секторе перед героем в сторону ближайшего;
## при количестве 2 и больше — второй взмах назад. Радиус — дальность навыка × область.

@export var arc_degrees := 120.0


func kind() -> StringName:
	return &"cone"


func execute(rt: SkillRuntime) -> bool:
	var s := rt.stats
	var origin := rt.player.global_position
	var reach := s.range * s.area_mult
	var target := rt.world.director.nearest_enemy(origin, reach)
	if target == null:
		return false
	var forward := origin.direction_to(target.global_position)
	var half_arc := deg_to_rad(arc_degrees) / 2.0
	var directions: Array[Vector2] = [forward]
	if s.amount >= 2:
		directions.append(-forward)
	var candidates := rt.world.director.enemies_in_radius(origin, reach)
	for dir in directions:
		for e in candidates:
			if absf(dir.angle_to(e.global_position - origin)) <= half_arc:
				rt.hit(e)
		rt.effect({"type": &"slash", "pos": origin, "dir": dir, "radius": reach, "arc": arc_degrees})
	return true
