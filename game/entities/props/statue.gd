class_name Statue
extends MapObject
## Статуя (CR-06, испытание CR-16): герой подходит и жмёт E — статуя пробуждается мини-боссом.
## Его гарантированный предмет задан в данных (EnemyData.loot_rarity).

const GUARDIAN_ID := &"stone_golem"


func _init() -> void:
	requires_key = true


func _ready() -> void:
	super()
	interact_radius = 28.0


func activate(_player: Player) -> bool:
	used = true
	_world.waves.spawn_enemy(DataRegistry.enemy(GUARDIAN_ID), global_position)
	Events.statue_awakened.emit()
	return true


func prompt_text(_player: Player, near: bool) -> String:
	var title := tr(ChallengeAltar.name_key(ChallengeAltar.STATUE))
	return tr("CHALLENGE_PROMPT").format({"name": title}) if near else title


func prompt_color(_player: Player) -> Color:
	return Color(0.8, 0.82, 0.9)


func art_id() -> StringName:
	return &"statue_empty" if used else &"statue"


func _draw() -> void:
	if _art != null:
		return
	if used:  # пустой постамент
		draw_rect(Rect2(-9, -2, 18, 6), Color(0.4, 0.4, 0.42))
		return
	draw_rect(Rect2(-9, -2, 18, 6), Color(0.45, 0.45, 0.48))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5, -2), Vector2(-6, -16), Vector2(0, -22), Vector2(6, -16), Vector2(5, -2),
	]), Color(0.62, 0.62, 0.65))
