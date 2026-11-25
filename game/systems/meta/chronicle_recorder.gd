class_name ChronicleRecorder
extends Node
## Итог забега для «Летописи» (шаг 10, MetaProfile). Работает у каждого участника и пишет только
## своего героя: профиль у каждого свой. Источники одинаковы у хоста и клиентов — синхронизируемые
## свойства героя (kills, chests_opened) и события, которые WorldNet пересылает клиентам
## (boss_defeated, item_picked, player_revived, interactable_used). Врага «встретил» тот, у кого он появился
## в мире; запись лора — тот, кто её прочёл (Events.lore_read, локально).
## Логики, меняющей общее состояние, здесь нет: только подсчёт.

var _world: World
var _bosses := 0
var _revives := 0
var _uniques: Array[StringName] = []
## Шаг 8: прочитанные записи лора и освобождённые пленники; шаг 9: вскрытые тайники.
var _lore: Array[StringName] = []
var _rescued := 0
var _secrets := 0
## id врага → сколько появилось за забег.
var _seen := {}


func _ready() -> void:
	_world = World.of(self)
	Events.boss_defeated.connect(func() -> void: _bosses += 1)
	Events.player_revived.connect(_on_player_revived)
	Events.item_picked.connect(_on_item_picked)
	Events.lore_read.connect(func(id: StringName) -> void:
		if not id in _lore:
			_lore.append(id))
	Events.interactable_used.connect(func(_type: StringName, _peer: int, outcome: StringName) -> void:
		if outcome == &"freed":
			_rescued += 1
		elif outcome == &"secret":
			_secrets += 1)
	# Поля @onready мира в _ready его детей ещё пусты — контейнер берётся по пути.
	_world.get_node(^"Enemies").child_entered_tree.connect(_on_enemy_entered)


## Итог для MetaProfile.grant: герой, глубина (номер уровня с 1), пройденные уровни, убийства и прочее.
func summary() -> Dictionary:
	var player := _world.local_player()
	var victory := _world.flow.phase == LevelFlow.Phase.VICTORY
	return {
		"hero": String(RunConfig.get_hero().id),
		"hardcore": RunConfig.hardcore,
		"heat": RunConfig.heat(),  # Скверна печатей забега (шаг 12.3)
		"depth": GameState.level_index + 1,
		"levels": GameState.level_index + (1 if victory else 0),
		"kills": player.kills if player != null else 0,
		"chests": player.chests_opened if player != null else 0,
		"bosses": _bosses,
		"revives": _revives,
		"uniques": _uniques.duplicate(),
		"lore": _lore.duplicate(),
		"rescued": _rescued,
		"secrets": _secrets,
		"seen": _seen.duplicate(),
	}


func _mine(peer_id: int) -> bool:
	return peer_id == multiplayer.get_unique_id()


func _on_player_revived(_peer_id: int, by_peer_id: int) -> void:
	if _mine(by_peer_id):
		_revives += 1


func _on_item_picked(peer_id: int, item: Dictionary) -> void:
	var unique: StringName = StringName(str(item.get("unique", "")))
	if _mine(peer_id) and unique != &"" and not unique in _uniques:
		_uniques.append(unique)


func _on_enemy_entered(node: Node) -> void:
	var enemy := node as Enemy
	if enemy != null and not enemy.ally:  # союзные скелеты и призывы — не нечисть бестиария
		_seen[enemy.data_id] = int(_seen.get(enemy.data_id, 0)) + 1
