class_name LightSources
extends RefCounted
## Подвижные источники света (шаг 11.8): герои, снаряды и следы атак, объекты карты, редкий лут. Узел встаёт сюда
## сам (add) — у хоста и у клиентов одинаково, из того, что у них уже есть, — и уходит, когда покидает дерево.
## LightMap читает список каждый кадр. Если у узла есть метод light_scale() -> float, яркость и радиус следуют
## ему (0 — погас): взрыв разгорается, импульс гаснет, открытый сундук темнеет. Скрытый узел не светит
## (у клиента снаряд прячется до того, как его удалит хост).

## Порядок рисования, когда источников больше предела: сначала герои, затем объекты, затем атаки.
enum Rank { HERO, PROP, ATTACK }

## id узла → [узел, цвет × энергия, радиус, есть ли light_scale, Rank].
static var _items := {}


## color — оттенок, альфа — энергия; radius — px мира. Без энергии или радиуса узел не встаёт.
static func add(node: CanvasItem, color: Color, radius: float, rank := Rank.ATTACK) -> void:
	if node == null or radius <= 0.0 or color.a <= 0.0:
		return
	var id := node.get_instance_id()
	var forget := _forget.bind(id)
	if not node.tree_exiting.is_connected(forget):
		node.tree_exiting.connect(forget, CONNECT_ONE_SHOT)
	_items[id] = [node, Color(color.r * color.a, color.g * color.a, color.b * color.a), radius,
			node.has_method(&"light_scale"), rank]


static func remove(node: Object) -> void:
	if node != null:
		_forget(node.get_instance_id())


static func _forget(id: int) -> void:
	_items.erase(id)


static func count() -> int:
	return _items.size()


## Источники для кадра по рангам ([герои, объекты, атаки]), в каждом — [позиция, цвет, радиус]; только живые и видимые.
static func collect() -> Array:
	var ranked: Array = [[], [], []]
	var stale: Array = []
	for id: int in _items:
		var item: Array = _items[id]
		var node: CanvasItem = item[0]
		if not is_instance_valid(node):
			stale.append(id)
			continue
		if not node.is_visible_in_tree():
			continue
		var scale := 1.0
		if item[3]:
			scale = node.light_scale()
			if scale <= 0.0:
				continue
		ranked[item[4]].append([node.global_position, item[1] * scale, item[2] * (0.6 + 0.4 * minf(scale, 1.0))])
	for id: int in stale:
		_items.erase(id)
	return ranked
