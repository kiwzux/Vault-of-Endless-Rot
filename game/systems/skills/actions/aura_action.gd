class_name AuraAction
extends SkillAction
## Аура (шаг 3; была схема AURA оружия): удар по всем врагам вокруг героя. Радиус — дальность × область.


func kind() -> StringName:
	return &"aura"


func execute(rt: SkillRuntime) -> bool:
	var origin := rt.player.global_position
	var reach := rt.stats.range * rt.stats.area_mult
	var victims := rt.world.director.enemies_in_radius(origin, reach)
	if victims.is_empty():
		return false
	for e in victims:
		rt.hit(e)
	rt.effect({"type": &"nova", "pos": origin, "radius": reach})  # волна от героя (шаг 11.21), а не взрыв pulse
	return true
