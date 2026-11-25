class_name DashAction
extends SkillAction
## Рывок (шаг 3): призрачный двойник героя проносится по прямой к ближайшему врагу и дальше, на всю
## дальность навыка (до стены), и один раз ранит всех на пути. Сам герой не двигается: его позицию ведёт
## владелец (ФТ-08, ФТ-14), а навык автоматический. Клиентам — след dash.

## Шаг проверки стены вдоль пути, px.
const WALL_STEP := 8.0

@export var width := 18.0


func kind() -> StringName:
	return &"dash"


func execute(rt: SkillRuntime) -> bool:
	var origin := rt.player.global_position
	var target := rt.world.director.nearest_enemy(origin, rt.stats.range)
	if target == null:
		return false
	var dir := origin.direction_to(target.global_position)
	var length := WALL_STEP
	while length < rt.stats.range and not rt.world.is_blocked(origin + dir * (length + WALL_STEP)):
		length += WALL_STEP
	var to := origin + dir * length
	var thickness := width * rt.stats.area_mult
	for e in BeamAction.enemies_on_line(rt.world, origin, to, thickness):
		rt.hit(e)
	rt.effect({"type": &"dash", "pos": origin, "dir": dir, "radius": length, "width": thickness})
	return true
