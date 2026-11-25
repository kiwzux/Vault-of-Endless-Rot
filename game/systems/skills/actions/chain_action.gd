class_name ChainAction
extends SkillAction
## Цепь (шаг 3; была схема CHAIN оружия): удар по ближайшему врагу и прыжки к следующим ближайшим
## в радиусе jump_radius; прыжков — количество навыка.

@export var jump_radius := 90.0


func kind() -> StringName:
	return &"chain"


func execute(rt: SkillRuntime) -> bool:
	var origin := rt.player.global_position
	var current := rt.world.director.nearest_enemy(origin, rt.stats.range)
	if current == null:
		return false
	var points := PackedVector2Array([origin])
	var hit := {}
	for jump in rt.stats.amount + 1:
		hit[current.get_instance_id()] = true
		points.append(current.global_position)
		var from := current.global_position
		rt.hit(current)
		current = rt.world.director.nearest_enemy(from, jump_radius, hit)
		if current == null:
			break
	rt.effect({"type": &"lightning", "pos": origin, "points": points})
	return true
