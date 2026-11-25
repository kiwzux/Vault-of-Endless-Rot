class_name GrailSite
extends MapObject
## Место Грааля в логове финального босса: появляется, если за круг посещено достаточно обелисков.
## Герой стоит на нём DIG_TIME секунд — Грааль выкопан (LevelFlow.on_grail_dug).

const DIG_TIME := 2.5

## 0..1, синхронизируется для клиентов.
@export var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()


func _ready() -> void:
	super()
	interact_radius = 14.0


func _interact(player: Player, delta: float) -> void:
	progress = minf(progress + delta / DIG_TIME, 1.0)
	if progress >= 1.0:
		used = true
		_world.flow.on_grail_dug(player)


## Выкопанный Грааль — места больше нет (пустой art_id прячет спрайт).
func art_id() -> StringName:
	return &"" if used else &"grail_site"


func _draw() -> void:
	if used:
		return
	var gold := Color(1.0, 0.82, 0.3)
	if _art == null:
		draw_line(Vector2(-6, -6), Vector2(6, 6), gold, 2.0)
		draw_line(Vector2(-6, 6), Vector2(6, -6), gold, 2.0)
	if progress > 0.0:
		draw_arc(Vector2.ZERO, 11.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 24, gold, 2.0)
