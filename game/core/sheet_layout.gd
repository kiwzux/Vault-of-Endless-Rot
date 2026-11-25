class_name SheetLayout
extends RefCounted
## Раскладка листа кадров, нарисованного кодом в art/ (DESIGN 4): размер кадра, сетка и анимации
## {имя: {"row", "col", "count", "fps", "rows", "per_row"}}. «col» — первый столбец (две короткие анимации в одной
## строке), «rows» > 1 — анимация из нескольких рядов кадров (удар на ходу: ряд на каждую фазу ходьбы), «per_row» —
## сколько таких рядов лежит рядом в одной строке листа (по умолчанию 1 — строка на ряд). Лист героя лежит отдельным PNG с <имя>.json рядом (of); листы врагов — блоками одного
## атласа (EnemyArt, from_dict с origin). Раскладка одна на лист и общая для всех узлов, которые его показывают;
## лист с другой раскладкой не требует правки кода.

var frame_size := Vector2i(32, 32)
var columns := 1
var rows := 1
## Левый верхний угол сетки в текстуре, px (у блока в общем атласе — не ноль).
var origin := Vector2i.ZERO
## Точка кадра, которую ставят в позицию узла (у врагов — середина над землёй), px.
var anchor := Vector2.ZERO
## Высота фигуры над anchor, px: над ней — полоска здоровья и надписи.
var height := 0.0
## Пройденный путь на кадр ходьбы, px листа: ноги не скользят ни при замедлении, ни на рывке.
var stride := 4.0
## Размер пикселя листа в мире, px. Листы 96 px (шаг 11.3) детальнее мира в 3 раза: scale 1/3, и на экране
## 1920×1080 (окно 640×360 × 3, растяжение canvas_items) пиксель листа — ровно пиксель экрана.
var scale := 1.0
## Направления (шаг 11.11): лист из блоков по dir_rows строк — "e", "ne", "n", "se", "s" (вправо, вправо-вверх,
## вверх, вправо-вниз, вниз); влево — те же блоки с flip_h. У листа без направлений — один блок «вправо».
var directions := PackedStringArray(["e"])
var dir_rows := 1
## Имя анимации → [строка, кадров, кадров в секунду, рядов, первый столбец, рядов в строке листа]. Ключи StringName и готовые числа: кадр выбирается
## у сотен врагов за кадр, без перевода имён и разбора словарей JSON (шаг 11.2).
var _animations := {}

## Нет такой анимации: первый кадр сетки, 1 кадр, 1 кадр/с.
const NONE := [0, 1, 1.0, 1, 0, 1]
## 8 секторов направления движения на экране (y вниз, сектор 0 — вправо, по часовой) → блок листа и отражение
## (−1 — прежнее: чистые «вверх» и «вниз» не перекидывают оружие в другую руку).
const SECTOR_DIRS: Array[String] = ["e", "se", "s", "se", "e", "ne", "n", "ne"]
const SECTOR_FLIP: Array[int] = [0, 0, -1, 1, 1, 1, -1, 0]
## Поворот в соседний сектор — только когда движение отклонилось от прежнего направления больше чем на этот угол
## (сектор — 45°, граница — 22,5°): стик геймпада у границы не дёргает героя туда-сюда.
const TURN_HYSTERESIS := 30.0

static var _cache := {}


## Раскладка листа texture из <имя>.json рядом. Нет файла — весь лист считается одним кадром (с предупреждением).
static func of(texture: Texture2D) -> SheetLayout:
	if texture == null:
		return null
	var path := texture.resource_path.get_basename() + ".json"
	if _cache.has(path):
		return _cache[path]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var layout: SheetLayout
	if parsed is Dictionary:
		layout = from_dict(parsed)
	else:
		push_warning("SheetLayout: нет раскладки %s — лист показывается одним кадром" % path)
		layout = from_dict({"frame": [texture.get_width(), texture.get_height()]})
	_cache[path] = layout
	return layout


## Раскладка из словаря (как в JSON генератора).
static func from_dict(d: Dictionary) -> SheetLayout:
	var layout := SheetLayout.new()
	var frame: Array = d.get("frame", [32, 32])
	layout.frame_size = Vector2i(int(frame[0]), int(frame[1]))
	layout.columns = maxi(int(d.get("columns", 1)), 1)
	layout.rows = maxi(int(d.get("rows", 1)), 1)
	var at: Array = d.get("origin", [0, 0])
	layout.origin = Vector2i(int(at[0]), int(at[1]))
	var anchor: Array = d.get("anchor", [layout.frame_size.x / 2.0, layout.frame_size.y / 2.0])
	layout.anchor = Vector2(float(anchor[0]), float(anchor[1]))
	layout.height = float(d.get("height", layout.frame_size.y))
	layout.stride = maxf(float(d.get("stride", 4.0)), 0.5)
	layout.scale = maxf(float(d.get("scale", 1.0)), 0.01)
	if d.has("directions"):
		layout.directions = PackedStringArray(d["directions"])
	layout.dir_rows = maxi(int(d.get("dir_rows", layout.rows)), 1)
	var animations: Dictionary = d.get("animations", {})
	for key: String in animations:
		var info: Dictionary = animations[key]
		layout._animations[StringName(key)] = [int(info.get("row", 0)), maxi(int(info.get("count", 1)), 1),
				maxf(float(info.get("fps", 1.0)), 0.001), maxi(int(info.get("rows", 1)), 1), int(info.get("col", 0)),
				maxi(int(info.get("per_row", 1)), 1)]
	return layout


## Показать лист в спрайте (centered): сетка кадров, точка anchor — в позиции узла, масштаб листа × extra_scale.
## Детальный лист (scale < 1) сглаживается при уменьшении: в окне 1280×720 кадр 96 px занимает 64 px экрана,
## и без сглаживания контур мерцал бы. Точка anchor должна быть на середине кадра по x: flip_h отражает кадр
## вокруг его центра.
func apply_to(sprite: Sprite2D, extra_scale: float = 1.0) -> void:
	sprite.hframes = columns
	sprite.vframes = rows
	sprite.centered = true
	sprite.offset = Vector2(frame_size) / 2.0 - anchor
	sprite.scale = Vector2.ONE * scale * extra_scale
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if scale < 1.0 else CanvasItem.TEXTURE_FILTER_PARENT_NODE


## Путь в мире на кадр ходьбы, px.
func world_stride() -> float:
	return stride * scale


## Кадров в анимации; 0 — такой анимации в листе нет.
func count(anim: StringName) -> int:
	return _animations[anim][1] if _animations.has(anim) else 0


## Строк в многострочной анимации (удар на ходу — по фазам ходьбы); 1 — обычная.
func rows_of(anim: StringName) -> int:
	return _animations.get(anim, NONE)[3]


func fps(anim: StringName) -> float:
	return _animations.get(anim, NONE)[2]


## Длительность одного проигрыша, с.
func duration(anim: StringName) -> float:
	var info: Array = _animations.get(anim, NONE)
	return info[1] / info[2] if _animations.has(anim) else 0.0


## Индекс кадра в сетке (у Sprite2D с hframes = columns, vframes = rows — его frame): i-й кадр анимации
## по кругу, row_shift — строка внутри многострочной анимации, dir — блок направления (dir_index, facing).
## Многострочная анимация может класть по per_row своих «строк» рядом в одну строку листа (удар на ходу, шаг 11.22).
@warning_ignore("integer_division")
func frame(anim: StringName, i: int, row_shift: int = 0, dir: int = 0) -> int:
	var info: Array = _animations.get(anim, NONE)
	var shift := clampi(row_shift, 0, info[3] - 1)
	var per_row: int = info[5]
	return (dir * dir_rows + info[0] + shift / per_row) * columns + info[4] + (shift % per_row) * info[1] + posmod(i, info[1])


## Кадр зацикленной анимации через time секунд от начала.
func frame_at(anim: StringName, time: float, dir: int = 0) -> int:
	return frame(anim, int(time * fps(anim)), 0, dir)


## Блок направления по имени ("s" — лицом к камере: статуи и портреты); нет такого — первый блок.
func dir_index(dir_name: String) -> int:
	return maxi(directions.find(dir_name), 0)


## Новый угол взгляда (центр сектора, градусы; 0 — вправо, 90 — вниз) по движению v на экране: поворот — только
## когда движение ушло от прежнего угла дальше TURN_HYSTERESIS. Нулевое движение угол не меняет.
static func turn(angle: float, v: Vector2) -> float:
	if v.length_squared() < 0.0001:
		return angle
	var to := rad_to_deg(v.angle())
	if absf(angle_difference(deg_to_rad(angle), deg_to_rad(to))) <= deg_to_rad(TURN_HYSTERESIS):
		return angle
	return snappedf(to, 45.0)


## Блок листа и отражение для угла взгляда: [индекс блока, flip_h]. keep_flip — прежнее отражение (для «вверх»/«вниз»).
func facing(angle: float, keep_flip: bool) -> Array:
	var sector := posmod(roundi(angle / 45.0), 8)
	var flip := SECTOR_FLIP[sector]
	# Лист без такого направления (враги, старые листы) — блок «вправо» с отражением по горизонтали.
	return [maxi(directions.find(SECTOR_DIRS[sector]), 0), keep_flip if flip < 0 else flip == 1]


## Область кадра index в текстуре, px (портреты, кадры из общего атласа).
@warning_ignore("integer_division")
func region(index: int) -> Rect2:
	return Rect2(Vector2(origin) + Vector2(index % columns, index / columns) * Vector2(frame_size), Vector2(frame_size))
