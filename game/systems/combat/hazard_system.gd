class_name HazardSystem
extends Node
## Хост: опасные клетки биома (шаг 9, раздел 4 техзадания — «свои опасности»). Клетка HAZARD непроходима
## (вода, лава, топь, провал — вид рисует LevelArt), а у самого её края действует эффект биома из данных
## (BiomeData, группа Hazard): героям — доля здоровья в секунду и/или холод, врагам — статус (горение, яд,
## холод, страх). Так опасные клетки, которые рисует модель, меняют бой: врагов можно водить вдоль лавы.
## Сеть: всё считает хост; здоровье героев и холод (Player.chills) уже синхронизируются, статусы врагов
## видны клиентам оттенком из снимка.
## Стоимость: раз в TICK секунд на каждого героя и врага — 9 клеток вокруг; 300 врагов — ~5 400 проверок в секунду.

const TICK := 0.5

var _world: World
var _biome: BiomeData
var _left := 0.0


func _ready() -> void:
	_world = World.of(self)
	Events.level_loaded.connect(func(_level: LevelData) -> void: _biome = RunPlan.biome(GameState.level_index))


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _biome == null or GameState.current_level == null:
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = TICK
	var started := PerfProbe.begin()
	var level := GameState.current_level
	if _biome.hazard_hero_damage > 0.0 or _biome.hazard_hero_chill:
		for p in _world.director.players_alive():
			if at_hazard(level, p.global_position, _biome.hazard_reach):
				_hurt_hero(p)
	if _biome.hazard_status != &"":
		for node in _world.enemies.get_children():
			var enemy := node as Enemy
			if enemy != null and not enemy.dead and not enemy.ally and at_hazard(level, enemy.global_position, _biome.hazard_reach):
				var base := 0.0 if enemy.data.is_boss else enemy.max_health * _biome.hazard_enemy_damage
				_world.statuses.apply(enemy, _biome.hazard_status, base)
	PerfProbe.add(&"hazards", started)


## Стоит ли точка pos у края опасной клетки: ближе reach px к клетке HAZARD (из 9 клеток вокруг).
static func at_hazard(level: LevelData, pos: Vector2, reach: float) -> bool:
	var tile := float(Palette.tile_size())
	var cell := Vector2i((pos / tile).floor())
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			if not level.in_bounds(c) or level.get_tile(c) != Palette.Tile.HAZARD:
				continue
			var rect := Rect2(Vector2(c) * tile, Vector2.ONE * tile)
			var nearest := pos.clamp(rect.position, rect.end)
			if nearest.distance_to(pos) <= reach:
				return true
	return false


func _hurt_hero(player: Player) -> void:
	if _biome.hazard_hero_chill:
		player.chill()
	if _biome.hazard_hero_damage > 0.0:
		player.take_damage(player.max_health * _biome.hazard_hero_damage * TICK, null, false)  # доля здоровья: без роста
