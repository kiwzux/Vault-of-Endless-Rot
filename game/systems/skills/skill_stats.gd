class_name SkillStats
extends RefCounted
## Числа навыка в момент срабатывания (шаг 3, R4): уровень навыка + модификаторы (встроенные, классовые,
## руны забега) + ступени эволюции навыка (UpgradeRules) + характеристики героя. Считается заново при каждом срабатывании, поэтому бафф фонтана,
## новая пассивка или руна действуют сразу. Только хост.

var damage := 0.0
var cooldown := 1.0
## Дальность поиска цели (конус, аура и орбита умножают её на area_mult — как раньше у оружия).
var range := 0.0
## Множитель области: Размах героя + модификаторы.
var area_mult := 1.0
## Радиус области навыка (взрыв, зона, ловушка) с учётом area_mult.
var area := 0.0
## Количество с «Залпом» героя (по единице за единицу Залпа).
var amount := 1
## «Залп» героя отдельно: кольцу осколков он даёт больше (ProjectileAction.per_extra).
var extra := 0
var pierce := 0
var duration := 0.0
var speed_mult := 1.0
## Прибавка к шансу удачного удара и Вампиризм навыка.
var crit := 0.0
var leech := 0.0
var split := 0
var split_share := 0.5
var ricochet := 0
var returns := false
var kill_blast_share := 0.0
var kill_blast_radius := 0.0
## Маска тегов навыка с тегами модификаторов.
var tags := 0
## Array[StatusApplication]: статусы навыка и модификаторов.
var statuses: Array = []
## Модификаторы, которые подошли навыку.
var modifiers: Array[SkillModifier] = []


## extra_modifiers — классовые модификаторы героя и руны забега.
static func compute(data: SkillData, level: int, player: Player, extra_modifiers: Array = []) -> SkillStats:
	var s := SkillStats.new()
	var base_mask := DataRegistry.tag_mask(data.tags)
	var kind := data.action.kind() if data.action != null else &""
	var bonus := {"damage": 0.0, "cooldown": 0.0, "area": 0.0, "range": 0.0, "duration": 0.0, "speed": 0.0}
	var amount_bonus := 0
	var pierce_bonus := 0
	var tags: Array = data.tags.duplicate()
	s.statuses = data.on_hit.duplicate()
	for mod: SkillModifier in data.modifiers + extra_modifiers:
		if mod == null or not fits(mod, base_mask, kind):
			continue
		s.modifiers.append(mod)
		bonus["damage"] += mod.damage
		bonus["cooldown"] += mod.cooldown
		bonus["area"] += mod.area
		bonus["range"] += mod.range_bonus
		bonus["duration"] += mod.duration
		bonus["speed"] += mod.speed
		amount_bonus += mod.amount
		pierce_bonus += mod.pierce
		s.crit += mod.crit
		s.leech += mod.lifesteal
		s.split += mod.split
		if mod.split > 0:
			s.split_share = mod.split_share
		s.ricochet += mod.ricochet
		s.returns = s.returns or mod.returns
		if mod.kill_blast_radius > s.kill_blast_radius:
			s.kill_blast_radius = mod.kill_blast_radius
			s.kill_blast_share = mod.kill_blast_share
		tags.append_array(mod.add_tags)
		s.statuses.append_array(mod.statuses)
	# Ступени эволюции навыка (UpgradeRules): урон, перезарядка, область и количество.
	var rules := DataRegistry.UPGRADE_RULES
	var stage := player.evolution_stage(data.id)
	bonus["damage"] += rules.evolution_damage * stage
	bonus["cooldown"] -= rules.evolution_cooldown * stage
	bonus["area"] += rules.evolution_area * stage
	if rules.evolution_amount_every > 0:
		@warning_ignore("integer_division")
		amount_bonus += stage / rules.evolution_amount_every
	s.tags = DataRegistry.tag_mask(tags)
	s.damage = data.damage_at(level) * (1.0 + bonus["damage"])
	s.cooldown = data.cooldown_at(level) * player.cooldown_mult() * maxf(0.2, 1.0 + bonus["cooldown"])
	s.range = data.range_at(level) * (1.0 + bonus["range"])
	s.area_mult = player.area_mult() + bonus["area"]
	s.area = data.area_at(level) * s.area_mult
	s.extra = player.extra_amount()
	s.amount = maxi(data.amount_at(level) + amount_bonus + s.extra, 1)
	s.pierce = data.pierce_at(level) + pierce_bonus
	s.duration = data.duration_at(level) * (1.0 + bonus["duration"])
	s.speed_mult = maxf(0.2, 1.0 + bonus["speed"])
	return s


## Модификатор подходит навыку с тегами mask и действием kind.
static func fits(mod: SkillModifier, mask: int, kind: StringName) -> bool:
	if not mod.requires_actions.is_empty() and kind not in mod.requires_actions:
		return false
	return mod.requires_tags.is_empty() or (mask & DataRegistry.tag_mask(mod.requires_tags)) != 0
