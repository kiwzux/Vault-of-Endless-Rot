class_name PerfProbe
extends RefCounted
## Замер времени тика хоста по разделам (шаг 5): враги, навигация, навыки, снаряды, подбираемое, статусы.
## Включает стенд (tools/bench.gd); в игре выключен — тогда раздел стоит одну проверку флага.
## Использование: var t := PerfProbe.begin() … PerfProbe.add(&"раздел", t).

static var enabled := false
## Раздел → суммарное время, мкс, и число вызовов — с последнего reset().
static var totals := {}
static var calls := {}


static func begin() -> int:
	return Time.get_ticks_usec() if enabled else 0


static func add(section: StringName, started: int) -> void:
	if not enabled:
		return
	totals[section] = int(totals.get(section, 0)) + Time.get_ticks_usec() - started
	calls[section] = int(calls.get(section, 0)) + 1


static func reset() -> void:
	totals.clear()
	calls.clear()
