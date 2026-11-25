class_name StatSheet
extends RefCounted
## Лист характеристик героя в духе Diablo: все характеристики с итоговыми значениями — уровень,
## ресурсы, нападение, защита, добыча. Считается из Player.stats_snapshot(), поэтому работает
## и на клиенте. Строки — [ключ подписи, итог, раздел, основа]. Основа (шаг 11.7, колонка «Основа» как в
## Halls of Torment) — то же без прокачки, предметов, баффов и реликвий: только герой и черта класса;
## пусто — у строки нет основы (золото, убийства). Пределы — StatDef.cap, формулы — BalanceConfig.

enum Section { BASE, OFFENSE, DEFENSE, UTILITY }

const SECTION_KEYS: PackedStringArray = ["CHAR_SECTION_BASE", "CHAR_SECTION_OFFENSE", "CHAR_SECTION_DEFENSE", "CHAR_SECTION_UTILITY"]
const SECTION_COLORS: Array[Color] = [
	Color(0.95, 0.78, 0.4), Color(0.95, 0.45, 0.35), Color(0.55, 0.7, 1.0), Color(0.6, 0.85, 0.5),
]


static func rows(player: Player, chest_price: int) -> Array:
	var total := _rows(player, chest_price, player.stats_snapshot(), false)
	var base := _rows(player, chest_price, player.hero.base_stats, true)
	for i in total.size():
		total[i].append(base[i][1])
	return total


## s — характеристики (итоговые или только черта класса); base — строки основы (без текущих здоровья и маны).
static func _rows(player: Player, chest_price: int, s: Dictionary, base: bool) -> Array:
	var balance := DataRegistry.BALANCE
	var v := func(id: StringName) -> float: return float(s.get(id, 0.0))
	var capped := func(id: StringName) -> float:
		var def := DataRegistry.stat_def(id)
		return def.capped(float(s.get(id, 0.0))) if def != null else float(s.get(id, 0.0))
	var result: Array = []
	var add := func(key: String, value: String, section: Section) -> void: result.append([key, value, section])
	var hero := player.hero

	add.call("CHAR_LEVEL", "" if base else str(player.level), Section.BASE)
	if base:
		add.call("CHAR_HEALTH", str(ceili(hero.max_health + v.call(Player.STAT_MAX_HEALTH))), Section.BASE)
		add.call("CHAR_MANA", str(ceili(hero.max_mana)) if hero.max_mana > 0.0 else "—", Section.BASE)
	else:
		add.call("CHAR_HEALTH", "%d / %d" % [ceili(player.health), ceili(player.max_health)], Section.BASE)
		add.call("CHAR_MANA", "%d / %d" % [ceili(player.mana), ceili(player.max_mana)] if player.max_mana > 0.0 else "—", Section.BASE)
	add.call("CHAR_REGEN", _num(v.call(Player.STAT_REGEN)), Section.BASE)
	add.call("CHAR_SPEED", str(roundi(hero.move_speed * (1.0 + v.call(Player.STAT_SWIFTNESS)))), Section.BASE)

	add.call("CHAR_DAMAGE", _pct(v.call(Player.STAT_MIGHT), true), Section.OFFENSE)
	add.call("CHAR_HASTE", _pct(minf(v.call(Player.STAT_HASTE), 1.0 - balance.min_cooldown_mult), true), Section.OFFENSE)
	add.call("CHAR_AREA", _pct(v.call(Player.STAT_AREA), true), Section.OFFENSE)
	add.call("CHAR_AMOUNT", "+%d" % int(v.call(Player.STAT_AMOUNT)), Section.OFFENSE)
	add.call("CHAR_CRIT", _pct(v.call(Player.STAT_CRIT), false), Section.OFFENSE)
	add.call("CHAR_CRIT_DAMAGE", "×%s" % _num(balance.crit_mult + v.call(Player.STAT_CRIT_DAMAGE)), Section.OFFENSE)
	add.call("CHAR_GIANT_SLAYER", _pct(v.call(Player.STAT_GIANT_SLAYER), true), Section.OFFENSE)
	add.call("CHAR_EXECUTE", _pct(capped.call(Player.STAT_EXECUTE), false), Section.OFFENSE)
	add.call("CHAR_BERSERK", _pct(v.call(Player.STAT_BERSERK), true), Section.OFFENSE)
	add.call("CHAR_LIFESTEAL", _pct(v.call(Player.STAT_LIFESTEAL), false), Section.OFFENSE)

	add.call("CHAR_ARMOR", _num(v.call(Player.STAT_ARMOR)), Section.DEFENSE)
	add.call("CHAR_RESILIENCE", _pct(capped.call(Player.STAT_RESILIENCE), false), Section.DEFENSE)
	add.call("CHAR_DODGE", _pct(capped.call(Player.STAT_DODGE), false), Section.DEFENSE)
	add.call("CHAR_THORNS", _num(v.call(Player.STAT_THORNS)), Section.DEFENSE)
	var ward: float = v.call(Player.STAT_WARD)
	add.call("CHAR_WARD", "%s s" % _num(balance.ward_interval * (1.0 - capped.call(Player.STAT_WARD))) if ward > 0.0 else "—", Section.DEFENSE)
	var revivals := int(v.call(Player.STAT_REVIVAL)) - (0 if base else player.revivals_used)
	add.call("CHAR_REVIVAL", str(maxi(revivals, 0)), Section.DEFENSE)

	add.call("CHAR_MAGNET", str(roundi(balance.base_pickup_radius * (1.0 + v.call(Player.STAT_MAGNET)))), Section.UTILITY)
	add.call("CHAR_XP_GAIN", _pct(v.call(Player.STAT_XP_GAIN), true), Section.UTILITY)
	add.call("CHAR_GOLD_GAIN", _pct(v.call(Player.STAT_GOLD_GAIN), true), Section.UTILITY)
	add.call("CHAR_CURSE", _pct(v.call(Player.STAT_CURSE), true), Section.UTILITY)
	add.call("CHAR_GOLD", "" if base else str(player.gold), Section.UTILITY)
	add.call("CHAR_CHEST_PRICE", "" if base else str(chest_price), Section.UTILITY)
	add.call("CHAR_KILLS", "" if base else str(player.kills), Section.UTILITY)
	return result


static func _pct(value: float, signed: bool) -> String:
	var text := _num(value * 100.0) + "%"
	return ("+" + text) if signed and value >= 0.0 else text


static func _num(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")
