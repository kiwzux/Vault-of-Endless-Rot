class_name SummonAction
extends SkillAction
## Призыв (шаг 3): союзники (Enemy с ally, как скелеты Некромантии) рядом с героем. Живут длительность
## навыка; от одного навыка у героя не больше max_alive + «Залп». За срабатывание — количество навыка.
## Удар союзника — урон навыка с Мощью героя. Союзники — узлы World/Enemies: их создаёт хост через
## спавнер (ФТ-13), позицию клиентам несёт снимок врагов.

@export var ally_id: StringName = &"ghoul"
@export var max_alive := 3


func kind() -> StringName:
	return &"summon"


func execute(rt: SkillRuntime) -> bool:
	var ally := DataRegistry.enemy(ally_id)
	if ally == null:
		return false
	var alive: Array = rt.state.get_or_add("allies", [])
	for i in range(alive.size() - 1, -1, -1):
		var node := instance_from_id(alive[i]) as Enemy
		if node == null or node.dead:
			alive.remove_at(i)
	var room := max_alive + rt.stats.extra - alive.size()
	var origin := rt.player.global_position
	# Союзник бьёт data.contact_damage × Enemy.ALLY_DAMAGE_MULT × dmg_mult — подгоняем под урон навыка.
	var per_hit := rt.stats.damage * rt.player.damage_mult(rt.stats.tags)
	var dmg_mult := per_hit / maxf(ally.contact_damage * Enemy.ALLY_DAMAGE_MULT, 0.01)
	for i in mini(rt.stats.amount, room):
		var offset := Vector2.RIGHT.rotated(rt.player.rng.randf() * TAU) * 18.0
		var pos := origin + offset if not rt.world.is_blocked(origin + offset) else origin
		var summoned := rt.world.spawn_enemy({
			"id": ally_id, "pos": pos, "ally": true, "owner": rt.player.peer_id(), "dmg_mult": dmg_mult,
			"life": rt.stats.duration,
		})
		if summoned != null:
			summoned.source_skill = rt.data.id  # урон союзника — урон навыка в статистике забега
			alive.append(summoned.get_instance_id())
	return true
