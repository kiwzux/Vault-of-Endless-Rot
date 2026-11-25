class_name BalanceLog
extends Node
## Журнал боёв с боссами для подгонки баланса (шаг 12): сколько прожил босс, сколько у него было здоровья
## и с какими героями (класс, уровень, навыки с уровнями и ступенями, урон за бой). Пишет хост — одна строка JSON
## на бой в user://balance_log.jsonl (папка профиля); сводку по журналу печатает tools/balance_report.gd.
## Персональных данных нет: только числа забега и метка сборки (BuildInfo).
##
## Бой — от появления босса (Events.boss_spawned) до его смерти (victory) или гибели отряда (defeat, с долей
## оставшегося здоровья). Время — RunStats.time: пауза не считается. Урон героя за бой — прирост его урона
## в RunStats (вместе с подручными босса — они вокруг него и мешают так же).

const PATH := "user://balance_log.jsonl"
## Тестам — свой файл.
static var path := PATH

## Дополнительные поля записи текущего боя (tools/balance_sim: сколько раз босса подтягивали к герою).
var extra := {}

var _world: World
var _boss: Enemy
var _started := 0.0
## peer id → урон героя на начало боя.
var _damage_at_start := {}


func _ready() -> void:
	_world = World.of(self)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.enemy_died.connect(func(enemy: Node, _killer: int) -> void:
		if enemy == _boss:
			_finish("victory"))
	Events.run_ended.connect(func(victory: bool) -> void:
		if not victory and is_instance_valid(_boss):
			_finish("defeat"))


func _on_boss_spawned(boss: Node) -> void:
	if not multiplayer.is_server() or not boss is Enemy:
		return
	_boss = boss
	_started = _world.run_stats.time
	_damage_at_start = {}
	extra = {}
	for player in _world.get_players():
		_damage_at_start[player.peer_id()] = _damage_of(player.peer_id())


## Текущий бой не записывать (tools/balance_sim добивает босса после своего тайм-аута и пишет бой сам).
func cancel() -> void:
	_boss = null


func _finish(outcome: String) -> void:
	var boss := _boss
	_boss = null
	if not multiplayer.is_server() or not is_instance_valid(boss):
		return
	var seconds := maxf(_world.run_stats.time - _started, 0.0)
	var heroes: Array = []
	for player in _world.get_players():
		var dealt := _damage_of(player.peer_id()) - float(_damage_at_start.get(player.peer_id(), 0.0))
		heroes.append({
			"hero": String(player.hero.id), "level": player.level, "alive": player.alive,
			"damage": roundi(dealt), "dps": roundi(dealt / seconds) if seconds > 0.0 else 0,
			"skills": _skills_of(player), "items": player.equipment.size(),
		})
	write(extra.merged({
		"date": Time.get_datetime_string_from_system(false, true), "build": BuildInfo.id(),
		"boss": String(boss.data_id), "depth": GameState.level_index, "players": heroes.size(),
		"hardcore": RunConfig.hardcore, "heat": RunConfig.heat(), "boss_hp": roundi(boss.max_health),
		"left": snappedf(clampf(boss.health / boss.max_health, 0.0, 1.0), 0.01) if outcome == "defeat" else 0.0,
		"seconds": snappedf(seconds, 0.1), "outcome": outcome, "heroes": heroes,
	}))


## Строка журнала — в конец файла (файла нет — создаётся).
static func write(entry: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) \
			else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("BalanceLog: не удалось открыть %s" % path)
		return
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.close()


## Все записи журнала (битые строки пропускаются).
static func read_all(file_path: String = path) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(file_path):
		return result
	for line in FileAccess.get_file_as_string(file_path).split("\n", false):
		var entry: Variant = JSON.parse_string(line)
		if entry is Dictionary:
			result.append(entry)
	return result


func _damage_of(peer_id: int) -> float:
	var total := 0.0
	for value: float in _world.run_stats.record(peer_id).damage.values():
		total += value
	return total


## Навыки героя: id → [уровень, ступень эволюции] (пассивки — [уровень, 0]).
static func _skills_of(player: Player) -> Dictionary:
	var result := {}
	for id: StringName in player.upgrade_levels:
		result[String(id)] = [int(player.upgrade_levels[id]), player.evolution_stage(id)]
	return result
