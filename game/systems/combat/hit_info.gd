class_name HitInfo
extends RefCounted
## Удар по врагу (шаг 2, R3): сколько урона, от какого героя, с какими тегами, удачный ли и какие
## статусы пытается наложить. Строит хост — оружие (Player.make_hit), снаряд, статус, реакция, союзник;
## разбирает Enemy.take_hit. Живёт один кадр и по сети не передаётся.

var amount := 0.0
## peer id героя-источника; 0 — не герой.
var source_peer := 0
## Битовая маска тегов (DataRegistry.tag_mask).
var tags := 0
var crit := false
## Тик статуса: без вспышки, Вампиризма и новых статусов.
var is_dot := false
## Array[StatusApplication] — что удар пытается наложить, если враг выжил.
var statuses: Array = []
## Вампиризм навыка сверх Вампиризма героя (шаг 3, модификаторы).
var leech := 0.0
## Убитый этим ударом враг взрывается: доля урона удара и радиус (модификатор «трупный взрыв»).
var kill_blast_share := 0.0
var kill_blast_radius := 0.0
## Источник для статистики забега (RunStats): id навыка — его урон, статусы, реакции и взрывы убитых;
## RunStats.SOURCE_THORNS, SOURCE_NECROMANCY; пусто — прочее.
var skill: StringName


static func make(p_amount: float, p_source: int, p_tags: int = 0, p_crit: bool = false,
		p_statuses: Array = []) -> HitInfo:
	var hit := HitInfo.new()
	hit.amount = p_amount
	hit.source_peer = p_source
	hit.tags = p_tags
	hit.crit = p_crit
	hit.statuses = p_statuses
	return hit
