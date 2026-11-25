class_name Fountain
extends MapObject
## Фонтан (CR-06): временный бафф на BUFF_TIME секунд; у каждого игрока свой откат.

const BUFF_ID := &"fountain"
const BUFF_TIME := 60.0
const COOLDOWN := 120.0
const BUFF_STATS := {&"might": 0.25, &"swiftness": 0.15, &"regen": 1.0}

## peer id → секунд до следующего использования.
var _cooldowns := {}


func _physics_process(delta: float) -> void:
	for peer: int in _cooldowns.keys():
		_cooldowns[peer] -= delta
		if _cooldowns[peer] <= 0.0:
			_cooldowns.erase(peer)
	for p in _world.director.players_alive():
		if not _cooldowns.has(p.peer_id()) and global_position.distance_to(p.global_position) <= interact_radius:
			p.add_buff(BUFF_ID, BUFF_TIME, BUFF_STATS)
			_cooldowns[p.peer_id()] = COOLDOWN


func art_id() -> StringName:
	return &"fountain"


func _draw() -> void:
	if _art != null:
		return
	draw_circle(Vector2.ZERO, 11.0, Color(0.45, 0.42, 0.38))
	draw_circle(Vector2.ZERO, 8.0, Color(0.3, 0.8, 0.85, 0.85))
	draw_circle(Vector2(0, -2), 2.5, Color(0.8, 1.0, 1.0))
