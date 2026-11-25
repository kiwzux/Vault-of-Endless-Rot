class_name EnemyCorpses
extends Node2D
## Смерть врагов (шаг 11.2). Узел врага исчезает сразу — хост освобождает его в _die, клиенты — по спавнеру, —
## а падение доигрывается здесь у каждого участника: строка «смерть» листа врага, затем растворение. Все трупы
## рисуются одним узлом за проход из атласа врагов, как DamageNumbers: сотня смертей в секунду не создаёт сотню
## узлов и не рвёт пакет отрисовки. Лежит под живыми (z_index −1 в сцене мира, после слоя уровня).
## Шаг 11.9: под трупом остаётся пятно цветом врага (кровь, костная пыль, эктоплазма) и гаснет за stain_time;
## предел пятен — по качеству эффектов (VisualConfig). Новый уровень очищает и трупы, и пятна прежнего.

## Сколько труп тает после последнего кадра, с.
const FADE := 0.45
const MAX_CORPSES := 160
## Пятно сплюснуто: вид сверху-сбоку, как у тени.
const STAIN_SQUASH := 0.55

## [позиция, SheetLayout, отражён ли, масштаб, оттенок, возраст]
var _items: Array = []
## [позиция, цвет, радиус, возраст]
var _stains: Array = []


func _ready() -> void:
	set_process(false)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # листы врагов 96 px уменьшаются в 3 раза (шаг 11.4)
	Events.level_loaded.connect(func(_level: LevelData) -> void: clear())


func add(enemy: Enemy) -> void:
	if _items.size() >= MAX_CORPSES:
		_items.pop_front()
	var layout := enemy.sheet()
	_items.append([enemy.global_position, layout, enemy.body.flip_h, enemy.body.scale.x, enemy.rest_tint(), 0.0])
	var config := DataRegistry.VISUAL
	var limit := config.stain_limit(Settings.effects_quality)
	if limit > 0 and enemy.data != null and not enemy.ally:
		if _stains.size() >= limit:
			_stains.pop_front()
		var color := Color(enemy.data.placeholder_color.darkened(0.45), config.stain_alpha)
		_stains.append([enemy.global_position, color, layout.frame_size.x * enemy.body.scale.x * 0.25, 0.0])
	set_process(true)


func count() -> int:
	return _items.size()


func stain_count() -> int:
	return _stains.size()


func clear() -> void:
	_items.clear()
	_stains.clear()
	queue_redraw()


func _process(delta: float) -> void:
	for item: Array in _items:
		item[5] += delta
	_items = _items.filter(func(item: Array) -> bool:
		var layout: SheetLayout = item[1]
		return item[5] < layout.duration(&"death") + FADE)
	var stain_time := DataRegistry.VISUAL.stain_time
	for stain: Array in _stains:
		stain[3] += delta
	while not _stains.is_empty() and _stains[0][3] >= stain_time:
		_stains.pop_front()  # пятна стареют по порядку появления
	if _items.is_empty() and _stains.is_empty():
		set_process(false)
	queue_redraw()


## Пятна — одна текстура-клякса прямоугольниками без смены трансформации: все пятна идут одним пакетом отрисовки.
func _draw() -> void:
	var stain_time := DataRegistry.VISUAL.stain_time
	var blob := LightMap.spot()
	for stain: Array in _stains:
		var color: Color = stain[1]
		color.a *= clampf((stain_time - stain[3]) / (stain_time * 0.4), 0.0, 1.0)  # последние 40 % времени — гаснет
		var r: float = stain[2]
		var at: Vector2 = stain[0]
		draw_texture_rect(blob, Rect2(at - Vector2(r, r * STAIN_SQUASH), Vector2(r, r * STAIN_SQUASH) * 2.0), false, color)
		var drop := at + Vector2(r * 0.7, r * 0.2)
		draw_texture_rect(blob, Rect2(drop - Vector2(r, r * STAIN_SQUASH) * 0.5, Vector2(r, r * STAIN_SQUASH)), false, color)
	var atlas := EnemyArt.texture
	if atlas == null:
		return
	for item: Array in _items:
		var layout: SheetLayout = item[1]
		var age: float = item[5]
		var last := layout.count(&"death") - 1
		var frame := layout.frame(&"death", mini(int(age * layout.fps(&"death")), last))
		var tint: Color = item[4]
		var fade_from := layout.duration(&"death")
		if age > fade_from:
			tint.a *= clampf(1.0 - (age - fade_from) / FADE, 0.0, 1.0)
		var scale: float = item[3]
		draw_set_transform(item[0], 0.0, Vector2(-scale if item[2] else scale, scale))
		draw_texture_rect_region(atlas, Rect2(-layout.anchor, Vector2(layout.frame_size)), layout.region(frame), tint)
	draw_set_transform(Vector2.ZERO)
