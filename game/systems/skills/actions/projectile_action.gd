class_name ProjectileAction
extends SkillAction
## Снаряды (шаг 3; были схемы PROJECTILE и NOVA оружия): в ближайших врагов (NEAREST) или кольцом во все
## стороны, если враг рядом (RADIAL). Модификаторы: +снаряды, пробивание, скорость, раскол, рикошет,
## возврат; explode — взрыв при первом попадании радиусом области навыка (огненный шар).

enum Aim { NEAREST, RADIAL }

## Целей меньше, чем снарядов: лишние уходят веером с этим шагом.
const SPREAD := deg_to_rad(12.0)

@export var aim := Aim.NEAREST
@export var speed := 240.0
## Долетает до края дальности и возвращается (серп), раня врагов на обратном пути.
@export var returns := false
@export var explode := false
## Дальность полёта × радиус поиска: NEAREST — 1.5 (с возвратом всегда 2), RADIAL — 1.3.
@export var range_mult := 1.5
## RADIAL: снарядов за единицу «Залпа» героя (кольцо огня — 2).
@export var per_extra := 1
@export var default_look: StringName = &"arrow"


func kind() -> StringName:
	return &"projectile"


func execute(rt: SkillRuntime) -> bool:
	if aim == Aim.RADIAL:
		return _radial(rt)
	return _nearest(rt)


func _nearest(rt: SkillRuntime) -> bool:
	var s := rt.stats
	var origin := rt.player.global_position
	var targets := rt.world.director.nearest_enemies(origin, s.range, s.amount)
	if targets.is_empty():
		return false
	var back := returns or s.returns
	for i in s.amount:
		var target: Enemy = targets[i % targets.size()]
		var dir := origin.direction_to(target.global_position)
		if i >= targets.size():
			dir = dir.rotated(SPREAD * (i - targets.size() + 1) * (1 if i % 2 == 0 else -1))
		rt.shoot({
			"type": rt.look(default_look), "pos": origin, "dir": dir, "speed": speed * s.speed_mult,
			"range": s.range * (2.0 if back else range_mult), "return": back, "pierce": s.pierce,
			"explode": s.area if explode else 0.0,
		})
	return true


func _radial(rt: SkillRuntime) -> bool:
	var s := rt.stats
	var origin := rt.player.global_position
	var reach := s.range * s.area_mult
	if rt.world.director.nearest_enemy(origin, reach) == null:
		return false
	var count := s.amount + s.extra * (per_extra - 1)
	var offset := rt.player.rng.randf() * TAU
	var back := returns or s.returns
	for i in count:
		rt.shoot({
			"type": rt.look(default_look), "pos": origin, "dir": Vector2.RIGHT.rotated(offset + TAU * i / count),
			"speed": speed * s.speed_mult, "range": reach * range_mult, "return": back, "pierce": s.pierce,
			"explode": s.area if explode else 0.0,
		})
	return true
