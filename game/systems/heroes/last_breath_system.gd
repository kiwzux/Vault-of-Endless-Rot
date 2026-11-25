class_name LastBreathSystem
extends Node
## Хост: «Последний вздох» (DESIGN 6, фишка 5; CR-18) — воскрешение в кооперативе. Павший герой становится
## призраком и медленно двигается (Player). Живой союзник стоит рядом с ним REVIVE_TIME секунд —
## призрак встаёт с долей здоровья REVIVE_HEALTH. Отошёл — прогресс тает с той же скоростью.
## В «Хардкоре» не действует: павший ждёт следующего уровня (DESIGN 1). В одиночной игре поднять
## некому — гибель героя сразу завершает забег (LevelFlow).
## Прогресс — Player.revive_progress, его синхронизирует WorldNet; событие — Events.player_revived.

const REVIVE_TIME := 3.0
const REVIVE_RADIUS := 28.0
const REVIVE_HEALTH := 0.5

var _world: World


func _ready() -> void:
	_world = World.of(self)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or RunConfig.hardcore or _world.flow.phase in [LevelFlow.Phase.DEFEAT, LevelFlow.Phase.VICTORY]:
		return
	for fallen in _world.get_players():
		if fallen.alive:
			continue
		var helper := _helper_near(fallen)
		if helper == null:
			fallen.revive_progress = maxf(fallen.revive_progress - delta / REVIVE_TIME, 0.0)
			continue
		fallen.revive_progress = minf(fallen.revive_progress + delta / REVIVE_TIME, 1.0)
		if fallen.revive_progress >= 1.0:
			fallen.revive(REVIVE_HEALTH)
			Events.player_revived.emit(fallen.peer_id(), helper.peer_id())


## Живой союзник в радиусе; null — рядом никого.
func _helper_near(fallen: Player) -> Player:
	for other in _world.director.players_alive():
		if other != fallen and other.global_position.distance_to(fallen.global_position) <= REVIVE_RADIUS:
			return other
	return null
