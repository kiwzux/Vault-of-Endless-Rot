class_name StrikeAction
extends SkillAction
## Удар с неба (шаг 3; была схема STRIKE оружия): метеоры, молнии, кислотные капли падают на разных
## случайных врагов в радиусе поиска и бьют по области навыка через fuse секунд (круг-предупреждение
## растёт). Количество — сколько ударов за раз.

@export var fuse := 0.5
@export var default_look: StringName = &"blast"


func kind() -> StringName:
	return &"strike"


func execute(rt: SkillRuntime) -> bool:
	var candidates := rt.world.director.enemies_in_radius(rt.player.global_position, rt.stats.range)
	if candidates.is_empty():
		return false
	for i in mini(rt.stats.amount, candidates.size()):
		var target: Enemy = candidates.pop_at(rt.player.rng.randi_range(0, candidates.size() - 1))
		rt.shoot({"type": rt.look(default_look), "pos": target.global_position, "radius": rt.stats.area, "fuse": fuse})
	return true
