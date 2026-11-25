class_name PropFactory
extends RefCounted
## Фабрика объектов карты для контейнера World/Props (и для spawn_function спавнера в game/net):
## порталы, объекты по меткам LevelData (CR-06) и торговцы (CR-14).
## null — неизвестный вид (данные могли прийти по сети).

const PORTAL_SCENE := "res://entities/props/portal.tscn"
const OBJECTS := {
	&"chest": preload("res://entities/props/chest.gd"),
	&"fountain": preload("res://entities/props/fountain.gd"),
	&"statue": preload("res://entities/props/statue.gd"),
	&"obelisk": preload("res://entities/props/obelisk.gd"),
	&"grail_site": preload("res://entities/props/grail_site.gd"),
}


static func create(data: Dictionary) -> Node2D:
	var kind: StringName = data.get("kind", &"")
	var node: Node2D = null
	if kind == &"portal":
		var mode: int = data.get("mode", Portal.Mode.NEXT)
		if mode not in Portal.Mode.values():
			return null
		var portal: Portal = load(PORTAL_SCENE).instantiate()
		portal.mode = mode as Portal.Mode
		portal.active = data.get("active", false)
		node = portal
	elif kind == &"merchant":
		node = Merchant.create(data)
		if node == null:
			return null
	elif kind == &"interactable":  # шаг 8: точка из данных (InteractableData)
		node = Interactable.create(data)
		if node == null:
			return null
	elif OBJECTS.has(kind):
		node = OBJECTS[kind].new()
		(node as MapObject).object_id = int(data.get("id", 0))
	elif kind == ChallengeAltar.TRIAL or kind == ChallengeAltar.CURSED:
		var altar := ChallengeAltar.new()
		altar.kind = kind
		altar.object_id = int(data.get("id", 0))
		node = altar
	else:
		return null
	node.position = data.get("pos", Vector2.ZERO)
	_add_light(node, kind)
	return node


## Свет объекта (шаг 11.8, LightMap): вид — из VisualConfig (испытание — по id алтаря), точка интереса — своим
## цветом и радиусом из InteractableData. Использованный объект гаснет (MapObject.light_scale).
static func _add_light(node: Node2D, kind: StringName) -> void:
	var config := DataRegistry.VISUAL
	var interactable := node as Interactable
	if interactable != null:
		var info := DataRegistry.interactable(interactable.data_id)
		LightSources.add(node, Color(info.color, config.interactable_light_energy), info.light_radius, LightSources.Rank.PROP)
		return
	var key: StringName = (node as ChallengeAltar).kind if node is ChallengeAltar else kind
	var color: Color = config.prop_light_colors.get(key, Color.TRANSPARENT)
	if node is Portal:  # портал светит цветом своего вида: дальше, Бесконечная гниль, завершить
		color = Color(Portal.MODE_COLORS[(node as Portal).mode], color.a)
	LightSources.add(node, color, config.prop_light_radius.get(key, 0.0), LightSources.Rank.PROP)
