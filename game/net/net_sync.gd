class_name NetSync
extends RefCounted
## Построение узлов MultiplayerSynchronizer кодом (ФТ-14). Сущности создаются фабриками
## (Enemy.create, Pickup.create, PropFactory.create …), поэтому синхронизаторы добавляются в той же
## spawn_function — она выполняется и на хосте, и на клиентах, узлы получаются одинаковыми.
##
## ON_CHANGE — свойство уходит, только когда изменилось (надёжная доставка, проверка раз в interval);
## ALWAYS — каждый interval, ненадёжно (позиции). spawn — значение приходит вместе с созданием узла.

## НФТ-07: частота репликации состояния не ниже 20 Гц. Синхронизатор отсчитывает интервал целыми кадрами
## и сбрасывает остаток: ровно 1/20 с при 60 FPS то и дело выходит в 4 кадра (замер: 19,1 Гц), ровно
## 1/30 с — в 3 кадра (23 Гц). Интервал 30 мс короче двух кадров при 60 FPS, поэтому состояние уходит
## каждые 2 кадра (30 Гц), а 20 Гц сохраняются, пока у хоста не меньше 40 FPS.
const REPLICATION_HZ := 20.0
const INTERVAL := 0.03


## Синхронизатор свойств properties узла node. host — полномочия у хоста (peer 1), даже если узел
## принадлежит игроку (герой: позицию ведёт владелец, здоровье и золото — хост).
static func add(node: Node, sync_name: String, properties: PackedStringArray, on_change: bool,
		interval: float = INTERVAL, host: bool = false, spawn: bool = true) -> MultiplayerSynchronizer:
	var config := SceneReplicationConfig.new()
	for property in properties:
		var path := NodePath(".:" + property)
		config.add_property(path)
		config.property_set_spawn(path, spawn)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE if on_change
				else SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync: MultiplayerSynchronizer = HostSynchronizer.new() if host else MultiplayerSynchronizer.new()
	sync.name = sync_name
	sync.replication_config = config
	if on_change:
		sync.delta_interval = interval
	else:
		sync.replication_interval = interval
	node.add_child(sync)  # root_path по умолчанию — «..», то есть сам node
	return sync
