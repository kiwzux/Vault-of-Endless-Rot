@tool
class_name PhysicsLayers
extends RefCounted
## Битовые маски слоёв столкновений. Имена слоёв — в project.godot [layer_names].

const WORLD := 1 << 0
const PLAYERS := 1 << 1
const ENEMIES := 1 << 2
const PLAYER_HITBOX := 1 << 3
const ENEMY_HITBOX := 1 << 4
const PICKUPS := 1 << 5
