class_name LevelDecor
extends Node2D
## Предметы обстановки на уровне (шаг 11.29): спрайты атласа props (art/gen_props.py, decor_*) по плану DecorPlan —
## у каждого участника свои, из той же карты, по сети ничего не уходит. Узел в общей сортировке по высоте (y_sort)
## с героями, врагами и объектами: герой проходит и за деревом, и перед ним. Огонь предметов — неподвижный свет
## уровня (LevelLights), анимация огня — у спрайта (PropArt).


func _ready() -> void:
	y_sort_enabled = true
	Events.level_loaded.connect(_on_level_loaded)
	if GameState.current_level != null:
		_on_level_loaded(GameState.current_level)


## Сколько предметов на уровне (проверки и стенд).
func count() -> int:
	return get_child_count()


func _on_level_loaded(level: LevelData) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for item: Dictionary in DecorPlan.of(level):
		var pos: Vector2 = item["pos"]
		var art := PropArt.attach(self, item["id"], fmod(pos.x * 0.013 + pos.y * 0.021, 1.0))
		if art == null:
			continue
		art.position = pos
		if item["flip"]:
			art.scale.x = -art.scale.x  # зеркало вокруг опоры: свет (LevelLights) зеркалится так же
