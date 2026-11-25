class_name LevelGenerator
extends RefCounted
## Цикл «CVAE (ONNX) → декодер → BFS-валидатор» с повторными попытками (ФТ-01 — ФТ-05).
## Работает только на хосте (ФТ-06, ФТ-15). generate() не трогает дерево сцен и автозагрузки,
## поэтому его можно вызывать из WorkerThreadPool (НФТ-05). Записи для журнала (ФТ-17) возвращаются
## в результате, а пишет их вызывающий в основном потоке (LevelService).

const DEFAULT_MODEL := "res://models/levelgen.onnx"
const MAX_ATTEMPTS := 5  # ФТ-05
## Размер латентного вектора z берётся из входа модели (z_dim): с 11.10.2026 — 64 (было 32; на датасете
## с устройством биомов 32 числа не вмещали положение опасных клеток — НФТ-10 83 % → 88 %, ml/README).
## Допустимый размер — от MIN_Z_DIM до MAX_Z_DIM.
const MIN_Z_DIM := 8
const MAX_Z_DIM := 256
## ФТ-17: обязательные поля каждой записи журнала генерации.
const LOG_FIELDS: PackedStringArray = ["seed", "z", "attempt", "valid", "gen_ms", "model_hash"]
## Сколько биома логова (Бездна) подмешивается в условие биома с каждым уровнем (DESIGN 6, фишка 1
## «Бесконечная гниль») и потолок этой доли. Проверить на обученной модели; если смешанные условия дают плохие карты — 0.
const ROT_PER_LEVEL := 0.15
const MAX_ROT := 0.6

var model_path: String
var model_hash := ""
var validator := LevelValidator.new()

## Длина z у загруженной модели.
var z_dim := 0

var _model: RefCounted  # OnnxModel из GDExtension; через ClassDB, чтобы скрипт компилировался и без расширения
var _map_size := 0
var _error := ""


class Request:
	var run_seed := 0
	var level_index := 0
	var biome := 0
	var room_type := 0
	## Доля условия биома логова в векторе cond (фишка «Бесконечная гниль», DESIGN 6): 0 — чистый биом.
	var rot := 0.0
	## Номер биома логова в палитре — к нему «загнивает» условие; -1 — смешения нет.
	var rot_biome := -1


class Result:
	## null, если все попытки отбракованы или модель недоступна.
	var level: LevelData
	var attempts: Array[Dictionary] = []
	var total_ms := 0.0
	var error := ""


func _init(path: String = DEFAULT_MODEL) -> void:
	model_path = path
	Palette.class_count()  # палитра загружается в основном потоке, до первого вызова из пула
	if not ClassDB.class_exists(&"OnnxModel"):
		_error = "расширение addons/onnx_runtime не загружено"
		return
	if not FileAccess.file_exists(path):
		_error = "нет файла модели %s" % path
		return
	_model = ClassDB.instantiate(&"OnnxModel")
	if _model.load(path) != OK:
		_error = _model.get_last_error()
		_model = null
		return
	_error = _check_interface()
	if _error != "":
		_model = null
		return
	model_hash = _model.get_model_hash()


func is_ready() -> bool:
	return _model != null


func get_error() -> String:
	return _error


## Запрос на уровень level_index забега: тип комнаты и доля гнили выводятся из сида и глубины.
## rot_biome — номер биома логова в палитре (к нему «загнивают» остальные), -1 — без смешения.
static func make_request(run_seed: int, level_index: int, biome: int, rot_biome: int = -1) -> Request:
	var request := Request.new()
	request.run_seed = run_seed
	request.level_index = level_index
	request.biome = biome
	request.room_type = hash([run_seed, level_index, "room_type"]) % Palette.room_types().size()
	request.rot_biome = rot_biome
	request.rot = 0.0 if rot_biome < 0 or biome == rot_biome else minf(ROT_PER_LEVEL * level_index, MAX_ROT)
	return request


static func cond_dim() -> int:
	return Palette.biomes().size() + Palette.room_types().size()


## Сид попытки выводится из сида забега: тот же код забега даёт те же карты (DESIGN 6, фишка 2).
## Для воспроизведения по журналу сид не пересчитывается — в записи хранится итоговый сид и z.
static func attempt_seed(run_seed: int, level_index: int, attempt: int) -> int:
	return hash([run_seed, level_index, attempt])


## z ~ N(0, I) длины size из сида: точка априорного распределения латентного пространства (НФТ-09).
static func make_z(seed_value: int, size: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var z := PackedFloat32Array()
	z.resize(size)
	for i in size:
		z[i] = rng.randfn(0.0, 1.0)
	return z


## cond = [биом (смесь с биомом логова rot_biome) | one-hot типа комнаты].
static func make_cond(biome: int, room_type: int, rot: float, rot_biome: int = -1) -> PackedFloat32Array:
	var biome_count := Palette.biomes().size()
	var cond := PackedFloat32Array()
	cond.resize(cond_dim())
	var mix := clampf(rot, 0.0, 1.0) if rot_biome >= 0 else 0.0
	cond[biome] += 1.0 - mix
	if mix > 0.0:
		cond[rot_biome] += mix
	cond[biome_count + room_type] = 1.0
	return cond


func generate(request: Request) -> Result:
	var result := Result.new()
	if not is_ready():
		result.error = _error
		return result
	var started := Time.get_ticks_usec()
	var cond := make_cond(request.biome, request.room_type, request.rot, request.rot_biome)
	for attempt in range(1, MAX_ATTEMPTS + 1):
		var attempt_started := Time.get_ticks_usec()
		var seed_value := attempt_seed(request.run_seed, request.level_index, attempt)
		var z := make_z(seed_value, z_dim)
		var level := _infer(z, cond, request.biome, request.room_type, seed_value)
		var record := {
			"seed": seed_value,
			"z": z,
			"cond": cond,
			"attempt": attempt,
			"run_seed": request.run_seed,
			"level_index": request.level_index,
			"biome": request.biome,
			"room_type": request.room_type,
			"model_hash": model_hash,
		}
		if level == null:
			record.merge({"valid": false, "errors": ["inference_failed"], "error_text": _model.get_last_error()})
		else:
			var report := _validate_and_finish(level)
			record.merge(report.to_dict())
			record["checksum"] = level.checksum()  # после _validate_and_finish — та же, что получат клиенты (ФТ-15)
			if report.valid:
				result.level = level
		record["gen_ms"] = (Time.get_ticks_usec() - attempt_started) / 1000.0
		result.attempts.append(record)
		if result.level != null:
			record["outcome"] = "accepted"
			break
		record["outcome"] = "exhausted" if attempt == MAX_ATTEMPTS else "rejected"
	result.total_ms = (Time.get_ticks_usec() - started) / 1000.0
	if result.level == null:
		result.error = "все %d попыток отбракованы (ФТ-05)" % MAX_ATTEMPTS
	return result


## ФТ-17: та же карта по записи журнала (тот же z, cond, версия модели) — без пересчёта сида.
## Принимает запись и после JSON: числа там float64, z восстанавливается точно (журнал пишется с full_precision).
func reproduce(record: Dictionary) -> LevelData:
	if not is_ready() or record.get("model_hash") != model_hash:
		return null
	var z := PackedFloat32Array(record["z"])
	if z.size() != z_dim:
		return null
	var cond := PackedFloat32Array(record["cond"])
	var level := _infer(z, cond, int(record["biome"]), int(record["room_type"]), int(record["seed"]))
	if level != null:
		_validate_and_finish(level)
	return level


func _infer(z: PackedFloat32Array, cond: PackedFloat32Array, biome: int, room_type: int, seed_value: int) -> LevelData:
	var out: Dictionary = _model.run({"z": z, "cond": cond})
	if out.is_empty():
		return null
	return LevelDecoder.decode(out["probs"], _map_size, biome, room_type, seed_value, model_hash,
			validator.min_spawn_exit_distance)


## Проверка (ФТ-04) и, если карта принята, последний детерминированный шаг конвейера:
## враги появляются только там, откуда дойдут до игроков — веса недостижимых клеток обнуляются.
## Тайлы не меняются: это ограничение для спавнера волн, а не правка планировки.
## Один и тот же шаг и при генерации, и при воспроизведении по журналу — иначе не совпадут контрольные суммы.
func _validate_and_finish(level: LevelData) -> LevelValidator.Report:
	var report := validator.validate(level)
	if report.valid:
		for i in level.spawn_weights.size():
			if report.distances[i] < 0:
				level.spawn_weights[i] = 0
	return report


## Модель обязана иметь интерфейс декодера CVAE из DESIGN 2.3, иначе генератор не запускается.
func _check_interface() -> String:
	var inputs: Dictionary = _model.get_input_shapes()
	var outputs: Dictionary = _model.get_output_shapes()
	var z: Variant = inputs.get("z")
	if not (z is PackedInt64Array) or z.size() != 2 or z[0] != 1 or z[1] < MIN_Z_DIM or z[1] > MAX_Z_DIM:
		return "вход z модели должен быть [1, N], N от %d до %d, а он %s" % [MIN_Z_DIM, MAX_Z_DIM, z]
	z_dim = z[1]
	if inputs.get("cond") != PackedInt64Array([1, cond_dim()]):
		return "вход cond модели должен быть [1, %d], а он %s" % [cond_dim(), inputs.get("cond")]
	var probs: Variant = outputs.get("probs")
	if not (probs is PackedInt64Array) or probs.size() != 4 or probs[0] != 1 or probs[1] != Palette.class_count() \
			or probs[2] != probs[3] or probs[2] not in LevelData.ALLOWED_SIZES:
		return "выход probs модели должен быть [1, %d, S, S], S из %s, а он %s" \
				% [Palette.class_count(), LevelData.ALLOWED_SIZES, probs]
	_map_size = probs[2]
	return ""
