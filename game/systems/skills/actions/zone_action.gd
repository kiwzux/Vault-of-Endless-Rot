class_name ZoneAction
extends SkillAction
## Зона на земле (шаг 3): святая вода, горючая смесь, ядовитое облако — круг радиусом области навыка
## бьёт всех внутри каждые tick_interval секунд, пока идёт длительность навыка. Ставится под случайных
## врагов в радиусе поиска (по зоне на единицу количества), под героя (at_self) или цепочкой от героя
## к ближайшему врагу (line, шаг 4: Стена огня — зоны встык через line_spacing радиусов, до стены).
## Урон навыка — за тик.
## Зона — узел World/Projectiles (Projectile, вид zone): клиенты рисуют её сами, урон считает хост.

@export var tick_interval := 0.5
@export var at_self := false
@export var line := false
## Шаг цепочки зон в радиусах зоны: 1.6 — круги чуть перекрываются.
@export var line_spacing := 1.6


func kind() -> StringName:
	return &"zone"


func execute(rt: SkillRuntime) -> bool:
	if at_self:
		_place(rt, rt.player.global_position)
		return true
	if line:
		return _line(rt)
	var candidates := rt.world.director.enemies_in_radius(rt.player.global_position, rt.stats.range)
	if candidates.is_empty():
		return false
	for i in mini(rt.stats.amount, candidates.size()):
		var target: Enemy = candidates.pop_at(rt.player.rng.randi_range(0, candidates.size() - 1))
		_place(rt, target.global_position)
	return true


## Цепочка зон от героя в сторону ближайшего врага: первая — у ног, дальше через шаг; у стены цепочка обрывается.
func _line(rt: SkillRuntime) -> bool:
	var origin := rt.player.global_position
	var target := rt.world.director.nearest_enemy(origin, rt.stats.range)
	if target == null:
		return false
	var dir := origin.direction_to(target.global_position)
	var step := maxf(rt.stats.area * line_spacing, 8.0)
	for i in rt.stats.amount:
		var pos := origin + dir * step * (i + 0.5)
		if rt.world.is_blocked(pos):
			break
		_place(rt, pos)
	return true


func _place(rt: SkillRuntime, pos: Vector2) -> void:
	rt.shoot({
		"type": &"zone", "pos": pos, "radius": rt.stats.area, "duration": rt.stats.duration, "tick": tick_interval,
	})
