class_name SkillFxLayer
extends Node2D
## Короткие эффекты навыков без узла на каждый (шаг 11.21): вспышка выстрела у руки героя, искры попадания снаряда,
## разряд молнии или столп света удара с неба. Один узел и один проход отрисовки, как искры Juice: сотни попаданий
## не плодят узлов. У каждого участника свои — выводятся из того, что он уже видит (снаряд исчез раньше конца пути,
## у героя начался удар), по сети ничего не уходит. Предел живых — по качеству эффектов (VisualConfig.vfx_limit).
## Над картой света: вспышки светятся сами.

const Z := 91

## Эффекты — параллельные массивы; закончившийся заменяется последним (порядок не важен).
var _clips: Array[SkillVfx.Clip] = []
var _pos := PackedVector2Array()
var _rot := PackedFloat32Array()
var _size := PackedFloat32Array()
var _age := PackedFloat32Array()
var _colors := PackedColorArray()
## Вспышка выстрела — не чаще одной у героя за кадр (залп кинжалов — одна вспышка).
var _cast_frame := {}


func _ready() -> void:
	z_index = Z
	if SkillVfx.available():
		material = SkillVfx.material
	Events.level_loaded.connect(func(_level: LevelData) -> void: clear())
	set_process(false)


func count() -> int:
	return _clips.size()


func clear() -> void:
	_clips.clear()
	_pos.clear()
	_rot.clear()
	_size.clear()
	_age.clear()
	_colors.clear()
	set_process(false)
	queue_redraw()


## Разовый эффект c в точке pos (опора кадра), поворот rot, размер size.
func spawn(c: SkillVfx.Clip, pos: Vector2, rot := 0.0, size := 1.0, color := Color.WHITE) -> void:
	if c == null:
		return
	if _clips.size() >= DataRegistry.VISUAL.vfx_limit(Settings.effects_quality):
		return
	_clips.append(c)
	_pos.append(pos)
	_rot.append(rot)
	_size.append(size)
	_age.append(0.0)
	_colors.append(color)
	set_process(true)


## Вспышка выстрела героя player в сторону dir стихией element.
func cast_flash(player: Node2D, dir: Vector2, element: StringName) -> void:
	var frame := Engine.get_process_frames()
	var id := player.get_instance_id()
	if _cast_frame.get(id, -1) == frame:
		return
	_cast_frame[id] = frame
	var forward := dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	spawn(SkillVfx.pick("cast", element), player.global_position + DataRegistry.VISUAL.cast_flash_offset + forward * 5.0,
			forward.angle())


func _process(delta: float) -> void:
	var i := _clips.size() - 1
	while i >= 0:
		_age[i] += delta
		if _age[i] >= _clips[i].duration():
			_remove(i)
		i -= 1
	if _clips.is_empty():
		set_process(false)
	queue_redraw()


func _remove(i: int) -> void:
	var last := _clips.size() - 1
	_clips[i] = _clips[last]
	_pos[i] = _pos[last]
	_rot[i] = _rot[last]
	_size[i] = _size[last]
	_age[i] = _age[last]
	_colors[i] = _colors[last]
	_clips.resize(last)
	_pos.resize(last)
	_rot.resize(last)
	_size.resize(last)
	_age.resize(last)
	_colors.resize(last)


func _draw() -> void:
	for i in _clips.size():
		var c := _clips[i]
		SkillVfx.draw(self, c, c.index_at(_age[i]), _pos[i], _rot[i], _size[i], _colors[i])
