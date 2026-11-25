class_name BossCast
extends RefCounted
## Одно применение приёма босса (BossAttack): кто, по кому, в какой фазе, куда целился в начале замаха,
## сколько прошло с удара, и свои счётчики приёма (state). Помощники создают снаряды, взрывы, зоны и телеграфы
## врага в World/Projectiles — клиенты видят их через спавнер, как выстрелы обычных врагов.
##
## Босс, мир и цель здесь без типов (Enemy, World, Player): приёмы — ресурсы данных, их грузит каталог
## (DataRegistry) и в проверках без автозагрузок (smoke_test); тип Enemy потянул бы за собой весь игровой код.

## Enemy — босс.
var boss
## World — мир босса.
var world
## Player — цель в начале замаха.
var target
var phase := 0
## Направление на цель и её место в начале замаха — по ним бьёт приём, даже если цель отошла.
var aim := Vector2.RIGHT
var spot := Vector2.ZERO
## Секунд с удара.
var time := 0.0
var state := {}
## Босс в этом тике двигался сам (рывок) — шаг steering не нужен.
var moving := false
var rng: RandomNumberGenerator


func _init(p_boss: Variant, p_world: Variant, p_target: Variant, p_phase: int, p_rng: RandomNumberGenerator) -> void:
	boss = p_boss
	world = p_world
	target = p_target
	phase = p_phase
	rng = p_rng
	spot = p_target.global_position
	aim = p_boss.global_position.direction_to(spot)
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT


func origin() -> Vector2:
	return boss.global_position


## Урон удара с множителем урона босса.
func damage_of(attack: BossAttack, share: float = 1.0) -> float:
	return attack.damage * share * damage_mult()


## Множитель урона босса (глубина, ХК, кооператив).
func damage_mult() -> float:
	return float(boss.damage_mult)


## Радиус босса, px.
func radius() -> float:
	return float(boss.radius)


## Живой ближайший к боссу герой сейчас (цель могла пасть) или null.
func nearest() -> Variant:
	return world.director.nearest_player(boss.global_position)


## Живые герои.
func heroes() -> Array:
	return world.director.players_alive()


func is_blocked(pos: Vector2) -> bool:
	return world.is_blocked(pos)


func shard(pos: Vector2, dir: Vector2, speed: float, reach: float, damage: float, color: Color) -> void:
	world.spawn_projectile({
		"type": &"shard", "pos": pos, "dir": dir, "speed": speed, "range": reach, "damage": damage,
		"hostile": true, "color": color,
	})


## Взрыв: круг растёт fuse секунд (он и есть телеграф), затем урон всем героям внутри.
func blast(pos: Vector2, radius_px: float, fuse: float, damage: float, color: Color) -> void:
	world.spawn_projectile({
		"type": &"blast", "pos": pos, "radius": radius_px, "fuse": fuse, "damage": damage, "hostile": true,
		"color": color,
	})


## Зона на земле: жжёт героев внутри каждые tick секунд, пока не истечёт duration.
func zone(pos: Vector2, radius_px: float, duration: float, tick: float, damage: float, color: Color) -> void:
	world.spawn_projectile({
		"type": &"zone", "pos": pos, "radius": radius_px, "duration": duration, "tick": tick, "damage": damage,
		"hostile": true, "color": color,
	})


func warn(pos: Vector2, radius_px: float, fuse: float, color: Color) -> void:
	world.spawn_projectile({"type": &"warn", "pos": pos, "radius": radius_px, "fuse": fuse, "color": color})


## Полоса-предупреждение от pos вдоль dir длиной length и полушириной half_width.
func warn_line(pos: Vector2, dir: Vector2, length: float, half_width: float, fuse: float, color: Color) -> void:
	world.spawn_projectile({
		"type": &"warn", "pos": pos, "dir": dir, "line": true, "range": length, "radius": half_width, "fuse": fuse,
		"color": color,
	})


func pulse(pos: Vector2, radius_px: float, color: Color) -> void:
	world.spawn_projectile({"type": &"pulse", "pos": pos, "radius": radius_px, "color": color})


## Подручный босса enemy_id: здоровье — доля health_share от множителя босса; урон — без надбавки босса
## (BalanceConfig.boss_damage_at), как у врагов волн (с enemy_damage_scale). false — предел живых врагов волн.
func summon(enemy_id: StringName, pos: Vector2, health_share: float) -> bool:
	if world.director.hostile_count() >= world.waves.table.max_alive:
		return false
	var balance := DataRegistry.BALANCE
	world.spawn_enemy({
		"id": enemy_id, "pos": pos, "hp_mult": float(boss.health_mult) * health_share,
		"dmg_mult": float(boss.damage_mult) / balance.boss_damage_at(GameState.level_index) * balance.enemy_damage_scale,
	})
	return true


## Шаг рывка босса (Enemy.dash_step); true — упёрся в стену.
func dash(dir: Vector2, speed: float, delta: float) -> bool:
	moving = true
	return boss.dash_step(dir, speed, delta)
