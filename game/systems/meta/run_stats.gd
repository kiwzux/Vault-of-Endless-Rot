class_name RunStats
extends Node
## Статистика забега (как в Megabonk): у каждого героя — убийства, опыт, золото, полученный урон, элиты
## и боссы, а по каждому навыку — урон, урон в секунду, убийства и уровень.
##
## Считает хост: урон и убийства идут из Enemy.take_hit по HitInfo.skill (навык-источник; руны, статусы,
## реакции и трупные взрывы засчитываются навыку, который их принёс). Источники не-навыки: SOURCE_THORNS —
## Шипы, SOURCE_NECROMANCY — скелеты Некромантии, пустой — прочее (удары без источника).
## Урон считается действительный: не больше здоровья, которое оставалось у врага.
## Урон в секунду навыка — урон, делённый на время, пока навык был у героя (эволюция забирает базовый
## навык: его время кончается, урон остаётся в таблице).
##
## Сеть: сводка героя — словарь Player.run_stats (хост → все, синхронизатор героя ON_CHANGE). Хост обновляет
## её раз в PUBLISH_INTERVAL с и сразу в конце забега; экран конца забега перерисовывается, когда она пришла.
## Формат сводки — summary_of.

const SOURCE_THORNS := &"thorns"
const SOURCE_NECROMANCY := &"necromancy"
const SOURCE_OTHER := &""
## Как часто сводка уходит по сети и как часто проверяется, какие навыки у героя.
const PUBLISH_INTERVAL := 2.0
const HELD_INTERVAL := 0.25


## Что накопил один герой.
class Record:
	## источник → урон (float) и убийства (int)
	var damage := {}
	var kills := {}
	## id навыка → [с какой секунды забега у героя, до какой (< 0 — ещё у героя)]
	var held := {}
	## id навыка → последний известный уровень
	var levels := {}
	var xp := 0
	var gold := 0
	var taken := 0.0
	var elites := 0
	var bosses := 0


## Секунд забега: идёт, пока мир не на паузе и забег не кончился.
var time := 0.0

var _world: World
var _records := {}
var _started := false
var _publish_left := 0.0
var _held_left := 0.0


func _ready() -> void:
	_world = World.of(self)
	Events.level_loaded.connect(func(_level: LevelData) -> void: _started = true)
	Events.xp_collected.connect(func(peer_id: int, amount: int) -> void:
		if multiplayer.is_server():
			record(peer_id).xp += amount)
	Events.gold_collected.connect(func(peer_id: int, amount: int) -> void:
		if multiplayer.is_server():
			record(peer_id).gold += amount)
	Events.run_ended.connect(func(_victory: bool) -> void: publish_all())


func _physics_process(delta: float) -> void:
	if not _started or not multiplayer.is_server() or _ended():
		return
	time += delta
	_held_left -= delta
	if _held_left <= 0.0:
		_held_left = HELD_INTERVAL
		for player in _world.get_players():
			_sync_held(player)
	_publish_left -= delta
	if _publish_left <= 0.0:
		_publish_left = PUBLISH_INTERVAL
		publish_all()


func _ended() -> bool:
	return _world.flow.phase in [LevelFlow.Phase.DEFEAT, LevelFlow.Phase.VICTORY]


func record(peer_id: int) -> Record:
	var rec: Record = _records.get(peer_id)
	if rec == null:
		rec = Record.new()
		_records[peer_id] = rec
	return rec


## Хост (Enemy.take_hit): удар героя нанёс dealt урона; killed — враг погиб от этого удара.
func record_hit(hit: HitInfo, dealt: float, killed: bool, enemy: Enemy) -> void:
	if hit.source_peer <= 0:
		return
	var rec := record(hit.source_peer)
	rec.damage[hit.skill] = float(rec.damage.get(hit.skill, 0.0)) + dealt
	if not killed:
		return
	rec.kills[hit.skill] = int(rec.kills.get(hit.skill, 0)) + 1
	if enemy.data.is_boss:
		rec.bosses += 1
	elif enemy.is_elite():
		rec.elites += 1


## Хост (Player.take_damage): герой потерял amount здоровья.
func record_taken(peer_id: int, amount: float) -> void:
	record(peer_id).taken += amount


func publish_all() -> void:
	if not multiplayer.is_server():
		return
	for player in _world.get_players():
		_sync_held(player)
		player.run_stats = summary_of(player.peer_id())


## Сводка героя для Player.run_stats:
## {"time": с, "xp", "gold", "taken", "elites", "bosses",
##  "skills": [[источник (String), урон (int), убийства, секунд у героя (float), уровень (0 — не навык)], …]}
## Навыки — по убыванию урона; навык без урона (ещё ни разу не попал) тоже в таблице.
func summary_of(peer_id: int) -> Dictionary:
	var rec := record(peer_id)
	var rows: Array = []
	var sources := rec.damage.keys()
	for id: StringName in rec.held:
		if not id in sources:
			sources.append(id)
	for source: StringName in sources:
		var seconds := time
		if rec.held.has(source):
			var span: Array = rec.held[source]
			seconds = (float(span[1]) if float(span[1]) >= 0.0 else time) - float(span[0])
		rows.append([String(source), roundi(float(rec.damage.get(source, 0.0))), int(rec.kills.get(source, 0)),
				snappedf(maxf(seconds, 0.0), 0.1), int(rec.levels.get(source, 0))])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return {
		"time": snappedf(time, 0.1), "xp": rec.xp, "gold": rec.gold, "taken": roundi(rec.taken),
		"elites": rec.elites, "bosses": rec.bosses, "skills": rows,
	}


## Какие навыки сейчас у героя: новый — начало его времени, пропавший (эволюция) — конец.
func _sync_held(player: Player) -> void:
	var rec := record(player.peer_id())
	for id: StringName in player.upgrade_levels:
		var skill := DataRegistry.upgrade(id) as SkillData
		if skill == null:
			continue
		rec.levels[id] = int(player.upgrade_levels[id])
		var span: Array = rec.held.get(id, [])
		if span.is_empty() or float(span[1]) >= 0.0:
			rec.held[id] = [time, -1.0]
	for id: StringName in rec.held:
		var span: Array = rec.held[id]
		if float(span[1]) < 0.0 and not player.upgrade_levels.has(id):
			span[1] = time


# --- Чтение сводки (экран конца забега; у клиента — из синхронизированного Player.run_stats) ---

## Весь урон героя по сводке.
static func total_damage(summary: Dictionary) -> int:
	var total := 0
	for row: Array in summary.get("skills", []):
		total += int(row[1])
	return total


## Урон в секунду строки сводки.
static func row_dps(row: Array) -> float:
	return float(row[1]) / float(row[3]) if float(row[3]) >= 1.0 else float(row[1])


## Ключ названия источника: навык — его name_key, Шипы и Некромантия — свои, прочее — «Прочее».
static func source_name_key(source: String) -> String:
	match StringName(source):
		SOURCE_THORNS:
			return "RUN_STATS_THORNS"
		SOURCE_NECROMANCY:
			return "RUN_STATS_NECROMANCY"
		SOURCE_OTHER:
			return "RUN_STATS_OTHER"
	var upgrade := DataRegistry.upgrade(StringName(source))
	return upgrade.name_key if upgrade != null else source
