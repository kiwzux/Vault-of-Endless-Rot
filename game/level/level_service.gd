class_name LevelService
extends RefCounted
## ФТ-07: связка генератора с игрой. Хост вызывает generate_map() при входе в уровень:
## генерация идёт в WorkerThreadPool (НФТ-05), журнал пишется в основном потоке (ФТ-17),
## при отказе — запись в журнал, уведомление игрока и запасная арена, без аварийного завершения (ТЗ 4.4.4).

## Параметр запуска для разработки: другая модель вместо models/levelgen.onnx, например заготовка
## `godot --path game -- --levelgen-model=res://models/spike/levelgen_spike.onnx`.
const MODEL_ARG := "--levelgen-model="

static var _generator: LevelGenerator
## Фоновая задача генерации, которая сейчас выполняется; -1 — нет.
static var _pending_task := -1


## Генератор создаётся один раз, в основном потоке. Нет модели — не ошибка игры, а повод для запасной арены.
static func generator() -> LevelGenerator:
	if _generator == null:
		var path := LevelGenerator.DEFAULT_MODEL
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with(MODEL_ARG):
				path = arg.trim_prefix(MODEL_ARG)
		_generator = LevelGenerator.new(path)
	return _generator


## Модель загружена в этом процессе. У клиента кооператива — никогда: уровни приходят от хоста (ФТ-15).
static func is_generator_loaded() -> bool:
	return _generator != null


## Выход из игры (вызывает GenLog._exit_tree). Если игрок закрыл окно во время генерации, сначала
## дожидаемся фоновой задачи — иначе движок начнёт выгружаться, пока поток ещё выполняет генератор.
## Затем модель освобождается, пока расширение ONNX ещё загружено.
static func release() -> void:
	if _pending_task != -1:
		WorkerThreadPool.wait_for_task_completion(_pending_task)
		_pending_task = -1
	_generator = null


## Хост: генератор карт (шаг 9, раздел 4 техзадания) — запрос (биом, сложность, сид) → описание карты MapPlan:
## планировка от CVAE (ОГР-02) и слой объектов поверх её меток (ObjectLayer). Корутина — вызывать через await.
static func generate_map(tree: SceneTree, request: MapRequest) -> MapPlan:
	var level := await _generate_layout(tree, request)
	var source := MapPlan.SOURCE_FALLBACK if level.model_hash == TestLevel.MODEL_HASH else MapPlan.SOURCE_MODEL
	return ObjectLayer.plan(level, request, source)


static func _generate_layout(tree: SceneTree, map_request: MapRequest) -> LevelData:
	var gen := generator()
	if not gen.is_ready():
		# Пока нет обученной модели (models/levelgen.onnx) — тестовая арена; это штатный режим разработки.
		push_warning("LevelService: генератор недоступен (%s) — тестовая арена" % gen.get_error())
		return _fallback(map_request)

	# Биом задаёт структура забега (RunPlan): этап круга — условие CVAE.
	var request := LevelGenerator.make_request(map_request.run_seed, map_request.depth, map_request.biome_index(),
			RunPlan.final_biome_index())
	var box := {}  # лямбда захватывает локальные переменные по значению, а словарь — по ссылке
	var task := WorkerThreadPool.add_task(func() -> void: box["result"] = gen.generate(request))
	_pending_task = task
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	if _pending_task == task:  # иначе задачу уже дождался release()
		WorkerThreadPool.wait_for_task_completion(task)
		_pending_task = -1

	var result: LevelGenerator.Result = box["result"]
	for record in result.attempts:
		GenLog.write(record)
	if result.level != null:
		return result.level
	push_error("LevelService: %s — запасная арена" % result.error)
	Events.level_generation_failed.emit(result.error)
	return _fallback(map_request)


## Запасная арена в облике биома запроса.
static func _fallback(map_request: MapRequest) -> LevelData:
	var level := TestLevel.make()
	level.biome = map_request.biome_index()
	return level
