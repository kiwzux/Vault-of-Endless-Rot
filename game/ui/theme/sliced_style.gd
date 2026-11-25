@tool
class_name SlicedStyle
extends StyleBox
## Рамка из текстуры повышенной детальности (шаг 11.7, графика — art/gen_ui.py): 9 частей — углы как есть,
## стороны и середина растягиваются. StyleBoxTexture так не умеет: он рисует тексель = пиксель интерфейса,
## а интерфейс живёт в 640×360 и рисуется в разрешении окна — текстура в texel_scale раз крупнее нужна, чтобы
## рамка легла пиксель в пиксель (4× — окно 2560×1440, как вся графика с 18.10.2026; было 2× — 1280×720).
##
## Под рамкой можно замостить фон (fill — камень с решёткой и т. п.) кусками размера его текстуры: это несколько
## прямоугольников, а не растянутая текстура, поэтому узор не плывёт на панелях любого размера.

## Рамка; null — без рамки.
@export var texture: Texture2D
## Поля 9 частей в пикселях интерфейса (у текстуры — × texel_scale).
@export var margin := 8.0
## Текселей на пиксель интерфейса (art/gen_ui.py: SCALE).
@export var texel_scale := 4.0
## Рисовать середину рамки (у кнопок и ячеек — да, у панели с фоном — нет).
@export var draw_center := true
@export var modulate := Color.WHITE
@export_group("Fill")
## Фон под рамкой, мостится; null — без фона.
@export var fill: Texture2D
## Отступ фона от края, пиксели интерфейса.
@export var fill_inset := 2.0
@export var fill_modulate := Color.WHITE


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if fill != null:
		_draw_fill(to_canvas_item, rect.grow(-fill_inset))
	if texture == null:
		return
	var tex_size := texture.get_size()
	var m := minf(margin, minf(rect.size.x, rect.size.y) / 2.0)
	var tm := margin * texel_scale
	var xs := [rect.position.x, rect.position.x + m, rect.end.x - m, rect.end.x]
	var ys := [rect.position.y, rect.position.y + m, rect.end.y - m, rect.end.y]
	var us := [0.0, tm, tex_size.x - tm, tex_size.x]
	var vs := [0.0, tm, tex_size.y - tm, tex_size.y]
	var rid := texture.get_rid()
	for row in 3:
		for col in 3:
			if row == 1 and col == 1 and not draw_center:
				continue
			var dest := Rect2(xs[col], ys[row], xs[col + 1] - xs[col], ys[row + 1] - ys[row])
			if dest.size.x <= 0.0 or dest.size.y <= 0.0:
				continue
			var src := Rect2(us[col], vs[row], us[col + 1] - us[col], vs[row + 1] - vs[row])
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, dest, rid, src, modulate)


## Фон кусками размера текстуры (в пикселях интерфейса): последний кусок в ряду обрезается.
func _draw_fill(item: RID, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var tile := fill.get_size() / texel_scale
	var rid := fill.get_rid()
	var y := rect.position.y
	while y < rect.end.y:
		var h := minf(tile.y, rect.end.y - y)
		var x := rect.position.x
		while x < rect.end.x:
			var w := minf(tile.x, rect.end.x - x)
			RenderingServer.canvas_item_add_texture_rect_region(item, Rect2(x, y, w, h), rid,
					Rect2(0, 0, w * texel_scale, h * texel_scale), fill_modulate)
			x += w
		y += h
