class_name Obelisk
extends MapObject
## Обелиск HoMM3 (CR-06, DESIGN 6, фишка 3): посещение открывает фрагмент карты Грааля.
## Счёт ведёт LevelFlow; собрал достаточно за круг — в логове финального босса можно выкопать Грааль.


func _interact(_player: Player, _delta: float) -> void:
	used = true
	_world.flow.on_obelisk_visited()


func art_id() -> StringName:
	return &"obelisk_used" if used else &"obelisk"


func _draw() -> void:
	if _art != null:
		return
	var stone := Color(0.85, 0.82, 0.7) if not used else Color(0.5, 0.48, 0.42)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5, 4), Vector2(-3, -18), Vector2(0, -22), Vector2(3, -18), Vector2(5, 4),
	]), stone)
	if not used:
		draw_circle(Vector2(0, -12), 2.0, Color(1.0, 0.85, 0.4))
