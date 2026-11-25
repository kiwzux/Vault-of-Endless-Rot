class_name HeroPassiveSystem
extends Node
## Хост: пассивки героев, которые создают объекты. Некромантия (DESIGN 1, отсылка к HoMM3):
## часть врагов, убитых Некромантом, встаёт скелетами-союзниками. Лидерство и Мана-щит
## меняют характеристики самого героя и живут в Player.

const NECROMANCY_CHANCE := 0.08
const MAX_SKELETONS := 6
## Кого поднимает Некромантия: в предел скелетов не входят союзники навыков призыва (упыри, легион).
const RAISED: Array[StringName] = [&"skeleton", &"skeleton_warrior"]
## С этой глубины поднимаются Скелеты-воины.
const WARRIOR_LEVEL := 2

var _world: World
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_world = World.of(self)
	_rng.seed = hash([RunConfig.run_seed, "necromancy"])
	Events.enemy_died.connect(_on_enemy_died)


func _on_enemy_died(enemy: Node, killer_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var killer := _world.find_player(killer_peer_id)
	var victim := enemy as Enemy
	if killer == null or victim == null or victim.data.is_boss:
		return
	var chance := NECROMANCY_CHANCE + killer.stat(Player.STAT_NECROMANCY)
	if killer.hero.passive == Player.PASSIVE_NECROMANCY and _rng.randf() < chance:
		raise_skeleton(killer, victim.global_position)


## Предел скелетов героя: талант «Повелитель мёртвых» добавляет по скелету за каждые 2 % шанса.
func max_skeletons(master: Player) -> int:
	return MAX_SKELETONS + floori(master.stat(Player.STAT_NECROMANCY) * 50.0 + 0.001)


## Хост: поднять скелета-союзника для героя. null — предел скелетов уже достигнут.
func raise_skeleton(master: Player, pos: Vector2) -> Enemy:
	if skeletons_of(master.peer_id()) >= max_skeletons(master):
		return null
	var id := &"skeleton_warrior" if GameState.level_index >= WARRIOR_LEVEL else &"skeleton"
	var skeleton := _world.spawn_enemy({
		"id": id, "pos": pos, "ally": true, "owner": master.peer_id(), "dmg_mult": master.damage_mult(),
	})
	if skeleton != null:
		skeleton.source_skill = RunStats.SOURCE_NECROMANCY
	return skeleton


func skeletons_of(peer_id: int) -> int:
	var n := 0
	for child in _world.enemies.get_children():
		if child is Enemy and child.ally and not child.dead and child.owner_peer == peer_id and child.data_id in RAISED:
			n += 1
	return n
