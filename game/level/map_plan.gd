class_name MapPlan
extends RefCounted
## Описание карты в едином формате (шаг 9, раздел 4 техзадания) — ответ генератора на MapRequest:
## планировка LevelData (карта CVAE, ОГР-02) и слой объектов поверх её меток (ObjectLayer).
## Игра (LevelFlow) создаёт объекты только по слою, поэтому генератор можно заменить, не трогая игру.
## Клиентам уходит одна LevelData (ФТ-15): объекты слоя создаёт хост через MultiplayerSpawner.

## Откуда планировка: модель или запасная арена (нет модели или все попытки отбракованы, ТЗ 4.4.4).
const SOURCE_MODEL := "cvae"
const SOURCE_FALLBACK := "fallback"

var request: MapRequest
var level: LevelData
var source := SOURCE_MODEL
## Объекты по порядку создания: {"kind": StringName, "cell": Vector2i, ...поля вида}. Виды — как у
## PropFactory (chest, fountain, statue, obelisk, trial_altar, cursed_totem, interactable, merchant).
var objects: Array[Dictionary] = []
## Клетки под объектами слоя: порталы, место Грааля и босс логова встают мимо них.
var occupied: Array[Vector2i] = []


static func create(map_request: MapRequest, layout: LevelData, from: String = SOURCE_MODEL) -> MapPlan:
	var plan := MapPlan.new()
	plan.request = map_request
	plan.level = layout
	plan.source = from
	return plan


func add(kind: StringName, cell: Vector2i, fields: Dictionary = {}) -> Dictionary:
	var entry := {"kind": kind, "cell": cell}
	entry.merge(fields)
	objects.append(entry)
	occupied.append(cell)
	return entry


func count(kind: StringName) -> int:
	return objects.reduce(func(total: int, o: Dictionary) -> int: return total + int(o["kind"] == kind), 0)


## Для журнала и проверок: запрос, источник, контрольная сумма планировки и объекты (клетки — [x, y]).
func to_dict() -> Dictionary:
	var items: Array = []
	for o in objects:
		var item := o.duplicate()
		item["kind"] = String(o["kind"])
		item["cell"] = [o["cell"].x, o["cell"].y]
		items.append(item)
	return {
		"request": request.to_dict() if request != null else {},
		"source": source,
		"checksum": level.checksum() if level != null else "",
		"objects": items,
	}
