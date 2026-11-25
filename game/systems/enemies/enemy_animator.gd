class_name EnemyAnimator
extends Node
## Кадры врагов (шаг 11.2) у хоста и у клиентов: позиция врага есть у всех, поэтому анимация выводится из неё
## (Enemy.animate) без сетевых данных. Чтобы 300 врагов не стоили 300 вызовов за кадр, за кадр обновляется
## доля SLICES: каждый враг — раз в SLICES кадров. С шага 11.4 ходьба — 8 фаз, и быстрому врагу (70 px/с) нужно
## ~25 кадров ходьбы в секунду: при 60 FPS обновление раз в 2 кадра (30 в секунду) их не пропускает
## (стенд 300 врагов: _process 0,47 → 0,70 мс, кадр без изменений).

const SLICES := 2

var _time := 0.0
var _turn := 0
var _world: World


func _ready() -> void:
	_world = World.of(self)


func _process(delta: float) -> void:
	if _world == null:
		return
	var started := PerfProbe.begin()
	_time += delta
	_turn = (_turn + 1) % SLICES
	var heroes := _world.get_players()
	var list := _world.enemies.get_children()
	for i in range(_turn, list.size(), SLICES):
		var enemy := list[i] as Enemy
		if enemy != null and enemy.sheet() != null:
			enemy.animate(_time, heroes)
	PerfProbe.add(&"enemy_anim", started)
