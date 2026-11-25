class_name ProjectileStream
extends RefCounted
## Снаряды и следы атак по сети пачками событий (шаг 5, часть 2; курсовая Ворончихина В.А., ФТ-13).
## Хост за кадр копит события «выстрел» (номер снаряда и его данные) и «снаряд снят раньше конца пути» (номер) и
## отправляет их одной надёжной посылкой (WorldNet._fire_batch). Клиент строит те же узлы той же фабрикой
## (ProjectileFactory) и ведёт полёт сам — он детерминирован; попадания считает только хост.
## Снаряд, который долетел, догорел или взорвался в срок, клиент убирает сам: события о нём нет.
##
## Формат пачки (little-endian): u16 число выстрелов; выстрел — u32 номер, u8 вид (KINDS), u32 маска полей FIELDS,
## затем значения присутствующих полей по порядку FIELDS; u16 число снятых; u32 номер каждого.
## Поля, которые нужны только хосту для попаданий (урон, удача, пробивание, тик зоны, взрыв шара, холод), не уходят.
## Имена навыков — номер в DataRegistry.UPGRADES: у всех участников одна сборка (проверка версии, BuildInfo).
## Было (MultiplayerSpawner): у каждого снаряда своя посылка с путём спавнера и словарём со строковыми ключами
## (~300 байт) и вторая — при удалении; теперь выстрел — 20–45 байт внутри общей посылки кадра.

enum Codec { VEC2, F32, U8, U32, FLAG, SKILL, NAME, COLOR, POINTS }

## Поле данных → способ записи. Новые — только в конец (маска — номер поля).
const FIELDS: Array = [
	["pos", Codec.VEC2], ["dir", Codec.VEC2], ["speed", Codec.F32], ["range", Codec.F32], ["hostile", Codec.FLAG],
	["owner", Codec.U32], ["skill", Codec.SKILL], ["color", Codec.COLOR], ["radius", Codec.F32], ["fuse", Codec.F32],
	["return", Codec.FLAG], ["duration", Codec.F32], ["trigger", Codec.F32], ["line", Codec.FLAG], ["from", Codec.VEC2],
	["arc", Codec.F32], ["points", Codec.POINTS], ["count", Codec.U8], ["phase", Codec.F32], ["look", Codec.NAME],
	["width", Codec.F32],
]
## Только для попаданий у хоста — клиенту не нужны.
const HOST_ONLY: PackedStringArray = ["damage", "crit", "pierce", "tick", "explode", "chill"]
const MAX_POINTS := 32
const NO_INDEX := 0xFFFF

static var _skill_index := {}
static var _skill_ids: Array[StringName] = []
static var _warned := {}

## Всего выстрелов и снятий в очереди за всё время (для замеров трафика).
var spawns := 0
var removals := 0
var _spawn_buf := PackedByteArray()
var _queued := 0
var _removed := PackedInt32Array()


## Хост: выстрел pid с данными data (тем же словарём, что ушёл в фабрику).
func queue_spawn(pid: int, data: Dictionary) -> void:
	var w := Writer.new()
	var kind := ProjectileFactory.KINDS.find(StringName(data.get("type", &"")))
	w.u32(pid)
	w.u8(maxi(kind, 0))
	var mask := 0
	for i in FIELDS.size():
		if _present(data, FIELDS[i]):
			mask |= 1 << i
	w.u32(mask)
	for i in FIELDS.size():
		if mask & (1 << i):
			_write(w, FIELDS[i][1], data[FIELDS[i][0]])
	_spawn_buf.append_array(w.bytes)
	_queued += 1
	spawns += 1
	if OS.is_debug_build():
		_check_keys(data)


## Хост: снаряд pid снят раньше конца пути (попадание, сработавшая ловушка, смена уровня).
func queue_removal(pid: int) -> void:
	_removed.append(pid)
	removals += 1


## Выстрелов в очереди кадра.
func queued() -> int:
	return _queued


func is_empty() -> bool:
	return _spawn_buf.is_empty() and _removed.is_empty()


## Пачка кадра; очередь пустеет.
func take() -> PackedByteArray:
	var w := Writer.new()
	w.u16(_queued)
	w.bytes.append_array(_spawn_buf)
	w.u16(_removed.size())
	for pid in _removed:
		w.u32(pid)
	_spawn_buf = PackedByteArray()
	_queued = 0
	_removed = PackedInt32Array()
	return w.bytes


## Клиент: пачка → [[pid, data], …] выстрелов и номера снятых. null — пачка испорчена (отбрасывается целиком).
static func decode(bytes: PackedByteArray) -> Variant:
	var r := Reader.new(bytes)
	var shots: Array = []
	var count := r.u16()
	for n in count:
		var pid := r.u32()
		var kind := r.u8()
		var mask := r.u32()
		if r.bad or kind >= ProjectileFactory.KINDS.size():
			return null
		var data := {"type": ProjectileFactory.KINDS[kind]}
		for i in FIELDS.size():
			if mask & (1 << i):
				data[FIELDS[i][0]] = _read(r, FIELDS[i][1])
		if r.bad:
			return null
		shots.append([pid, data])
	var removed := PackedInt32Array()
	for n in r.u16():
		removed.append(r.u32())
	if r.bad:
		return null
	return {"shots": shots, "removed": removed}


static func _present(data: Dictionary, field: Array) -> bool:
	if not data.has(field[0]):
		return false
	return bool(data[field[0]]) if field[1] == Codec.FLAG else true


static func _write(w: Writer, codec: int, value: Variant) -> void:
	match codec:
		Codec.VEC2:
			var v := Vector2(value)
			w.f32(v.x)
			w.f32(v.y)
		Codec.F32:
			w.f32(float(value))
		Codec.U8:
			w.u8(clampi(int(value), 0, 255))
		Codec.U32:
			w.u32(int(value))
		Codec.FLAG:
			pass
		Codec.SKILL:
			var index := skill_index(StringName(value))
			w.u16(index)
			if index == NO_INDEX:
				w.text(String(value))
		Codec.NAME:
			w.text(String(value))
		Codec.COLOR:
			var c := Color(value)
			for channel in [c.r, c.g, c.b, c.a]:
				w.f16(channel)
		Codec.POINTS:
			var points := PackedVector2Array(value)
			var n := mini(points.size(), MAX_POINTS)
			w.u8(n)
			for i in n:
				w.f32(points[i].x)
				w.f32(points[i].y)


static func _read(r: Reader, codec: int) -> Variant:
	match codec:
		Codec.VEC2:
			return Vector2(r.f32(), r.f32())
		Codec.F32:
			return r.f32()
		Codec.U8:
			return r.u8()
		Codec.U32:
			return r.u32()
		Codec.FLAG:
			return true
		Codec.SKILL:
			var index := r.u16()
			if index == NO_INDEX:
				return StringName(r.text())
			_ensure_skills()
			return _skill_ids[index] if index < _skill_ids.size() else &""
		Codec.NAME:
			return StringName(r.text())
		Codec.COLOR:
			return Color(r.f16(), r.f16(), r.f16(), r.f16())
		Codec.POINTS:
			var points := PackedVector2Array()
			for i in mini(r.u8(), MAX_POINTS):
				points.append(Vector2(r.f32(), r.f32()))
			return points
	return null


## Номер навыка в DataRegistry.UPGRADES; NO_INDEX — не навык (тогда имя уходит строкой).
static func skill_index(id: StringName) -> int:
	_ensure_skills()
	return _skill_index.get(id, NO_INDEX)


static func _ensure_skills() -> void:
	if not _skill_ids.is_empty():
		return
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		_skill_index[upgrade.id] = _skill_ids.size()
		_skill_ids.append(upgrade.id)


## Отладка: поле данных, которого нет ни в FIELDS, ни в HOST_ONLY, клиенту бы не дошло — сказать один раз.
static func _check_keys(data: Dictionary) -> void:
	for key: Variant in data:
		var name := String(key)
		if name == "type" or name in HOST_ONLY or _warned.has(name):
			continue
		if not FIELDS.any(func(f: Array) -> bool: return f[0] == name):
			_warned[name] = true
			push_warning("ProjectileStream: поле «%s» снаряда не передаётся клиентам — добавьте его в FIELDS" % name)


class Writer:
	var bytes := PackedByteArray()

	func _grow(n: int) -> int:
		var at := bytes.size()
		bytes.resize(at + n)
		return at

	func u8(v: int) -> void:
		bytes.encode_u8(_grow(1), v)

	func u16(v: int) -> void:
		bytes.encode_u16(_grow(2), v)

	func u32(v: int) -> void:
		bytes.encode_u32(_grow(4), v)

	func f32(v: float) -> void:
		bytes.encode_float(_grow(4), v)

	func f16(v: float) -> void:
		bytes.encode_half(_grow(2), v)

	func text(s: String) -> void:
		var raw := s.to_utf8_buffer()
		u8(mini(raw.size(), 255))
		bytes.append_array(raw.slice(0, 255))


class Reader:
	var bytes: PackedByteArray
	var at := 0
	var bad := false

	func _init(p_bytes: PackedByteArray) -> void:
		bytes = p_bytes

	func _take(n: int) -> int:
		if at + n > bytes.size():
			bad = true
			return -1
		at += n
		return at - n

	func u8() -> int:
		var i := _take(1)
		return bytes.decode_u8(i) if i >= 0 else 0

	func u16() -> int:
		var i := _take(2)
		return bytes.decode_u16(i) if i >= 0 else 0

	func u32() -> int:
		var i := _take(4)
		return bytes.decode_u32(i) if i >= 0 else 0

	func f32() -> float:
		var i := _take(4)
		return bytes.decode_float(i) if i >= 0 else 0.0

	func f16() -> float:
		var i := _take(2)
		return bytes.decode_half(i) if i >= 0 else 0.0

	func text() -> String:
		var n := u8()
		var i := _take(n)
		return bytes.slice(i, i + n).get_string_from_utf8() if i >= 0 else ""
