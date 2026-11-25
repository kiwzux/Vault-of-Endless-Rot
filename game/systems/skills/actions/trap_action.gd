class_name TrapAction
extends SkillAction
## Ловушка (шаг 3): бросается под случайного врага в радиусе поиска, взводится arm_time секунд и
## срабатывает, когда враг подойдёт на trigger_radius: удар по области навыка и статусы (капкан —
## оглушение и кровь). Не сработала за длительность навыка — исчезает. Количество — ловушек за раз.
## Ловушка — узел World/Projectiles (Projectile, вид trap): срабатывание решает хост.

@export var arm_time := 0.4
@export var trigger_radius := 14.0


func kind() -> StringName:
	return &"trap"


func execute(rt: SkillRuntime) -> bool:
	var candidates := rt.world.director.enemies_in_radius(rt.player.global_position, rt.stats.range)
	if candidates.is_empty():
		return false
	for i in mini(rt.stats.amount, candidates.size()):
		var target: Enemy = candidates.pop_at(rt.player.rng.randi_range(0, candidates.size() - 1))
		rt.shoot({
			"type": &"trap", "pos": target.global_position, "radius": rt.stats.area, "fuse": arm_time,
			"trigger": trigger_radius, "duration": rt.stats.duration,
		})
	return true
