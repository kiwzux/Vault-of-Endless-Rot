class_name SkillRuntime
extends RefCounted
## Навык героя на хосте (шаг 3, R4; был WeaponRuntime): перезарядка, срабатывание действия, тики
## действия между срабатываниями, удары и снаряды навыка (ФТ-08, ТК-08). Урон считает хост; клиентам
## уходят только снаряды и следы через World/Projectiles.
##
## Удар навыка — HitInfo: Мощь и Удача героя (с прибавками «по тегу» и удачей навыка), теги и статусы
## навыка, Вампиризм навыка, взрыв убитого. Снаряду хост ставит их сам после спавна (Projectile.arm):
## клиенту они не нужны — попаданий он не считает.

## Если цели нет, навык проверяет снова через этот промежуток, а не ждёт полную перезарядку.
const RETRY_DELAY := 0.1

var data: SkillData
var level := 1
var player: Player
var world: World
## Числа навыка с последнего срабатывания.
var stats: SkillStats
## Состояние действия между срабатываниями (угол орбиты, луч, призванные): само действие — общий ресурс.
var state := {}
## Секунд жизни навыка: часы для «не чаще раза в N секунд» у орбиты и луча.
var time := 0.0

var _cooldown_left := 0.0


func _init(p_data: SkillData, p_level: int = 1) -> void:
	data = p_data
	level = p_level


func tick(delta: float, p_player: Player, p_world: World) -> void:
	player = p_player
	world = p_world
	time += delta
	if stats == null:
		refresh()
	if data.action != null:
		data.action.tick(self, delta)
	_cooldown_left -= delta
	if _cooldown_left > 0.0:
		return
	refresh()
	if data.action != null and data.action.execute(self):
		_cooldown_left = stats.cooldown
	else:
		_cooldown_left = RETRY_DELAY


## Пересчитать числа навыка: уровень, модификаторы, характеристики героя.
func refresh() -> void:
	stats = SkillStats.compute(data, level, player, player.skill_modifiers(data))


## Удар навыка с броском удачи; base — урон до множителей героя (обычно stats.damage).
func make_hit(base: float) -> HitInfo:
	var hit := player.make_hit(base, stats.tags, stats.statuses, stats.crit)
	hit.leech = stats.leech
	hit.kill_blast_share = stats.kill_blast_share
	hit.kill_blast_radius = stats.kill_blast_radius
	hit.skill = data.id
	return hit


## Ударить врага: урон навыка × scale.
func hit(enemy: Enemy, scale: float = 1.0) -> void:
	enemy.take_hit(make_hit(stats.damage * scale))


## Снаряд героя: удача брошена при выстреле, приёмы навыка хост ставит узлу сам. fields — данные для
## spawn_projectile без урона и владельца. Цвета нет: вместо него уходит id навыка (шаг 11.21) — цвет, стихию
## облика и эволюцию каждый участник берёт из данных навыка (SkillVfx.look_of). null — снарядов в мире уже предел
## (BalanceConfig.max_hero_projectiles, шаг 5): выстрел пропускается.
func shoot(fields: Dictionary) -> Node2D:
	if world.projectiles_full():
		return null
	var hit_info := make_hit(stats.damage)
	fields["damage"] = hit_info.amount
	fields["crit"] = hit_info.crit
	fields["hostile"] = false
	fields["owner"] = player.peer_id()
	fields["skill"] = data.id
	var node := world.spawn_projectile(fields)
	var projectile := node as Projectile
	if projectile != null:
		projectile.arm(hit_info, stats)
	return node


## Только след (дуга, молния, импульс, луч, рывок): урона не наносит. owner — чей след: по нему герой
## играет анимацию удара у всех участников (ProjectileFactory, шаг 11.1).
func effect(fields: Dictionary) -> Node2D:
	fields["skill"] = data.id
	if not fields.has("owner"):
		fields["owner"] = player.peer_id()
	return world.spawn_projectile(fields)


## Вид снаряда или следа: свой у навыка (SkillData.fx_kind) или стандартный для действия.
func look(standard: StringName) -> StringName:
	return data.fx_kind if data.fx_kind != &"" else standard
