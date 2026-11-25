class_name ObjectRules
extends Resource
## Правила слоя объектов биома (шаг 9): сколько и с каким шансом ставить объекты поверх меток карты CVAE.
## Места решает карта модели (ОГР-02) — метки, клетки декора и проходимость; правила задают только плотность
## и риск. Рискованные события (алтарь проклятий, пленник) с глубиной встречаются чаще: risk_per_depth.

@export_group("Markers")
## Метка фонтана — святилище вместо фонтана с этим шансом.
@export var shrine_chance := 0.6
## Сундук — мимик с этим шансом, начиная с уровня mimic_min_depth (0 — первый уровень).
@export var mimic_chance := 0.15
@export var mimic_min_depth := 1
## Испытаний у меток появления врагов, кроме испытания на метке статуи.
@export var extra_challenges := 1

@export_group("Points")
## Разрушаемых на клетках декора не больше этого; не ближе breakable_spawn_gap шагов к точке появления.
@export var breakables_max := 12
@export var breakable_spawn_gap := 3
@export var lore_per_level := 2
@export var curse_altar_chance := 0.5
@export var prisoner_chance := 0.6
## Сколько раз пробуется пленник (каждый — с шансом prisoner_chance и риском глубины).
@export var prisoner_tries := 1

@export_group("Extra")
## Сверх меток модели (17.10.2026: больше объектов на уровне): платные сундуки и святилища-баффы на случайных
## достижимых клетках пола — не ближе scatter_spawn_gap шагов к точке появления и scatter_gap клеток друг к другу
## и к другим объектам.
@export var extra_chests := 0
@export var extra_shrines := 0
@export var scatter_spawn_gap := 6
@export var scatter_gap := 4
## Пасхалка (17.10.2026): Золотое ведро (точка с placement «easter») с этим шансом на первом уровне забега — значит,
## не больше одного раза за забег. Место — случайная разнесённая клетка пола, как у сундуков сверх меток.
@export var golden_bucket_chance := 0.0

@export_group("Secrets")
## Тайников (карманов карты с треснувшей стеной) на уровень не больше этого; в тайнике — клад (точка
## с placement «secret») и с шансом secret_shrine_chance — святилище, если в нём не меньше 6 клеток.
@export var secret_rooms_max := 2
@export var secret_shrine_chance := 0.35

@export_group("Risk")
## Прибавка к шансам алтаря проклятий и пленника за уровень глубины и её потолок.
@export var risk_per_depth := 0.03
@export var risk_cap := 0.9


## Шанс рискованного события на глубине depth.
func risk(base: float, depth: int) -> float:
	return minf(base + risk_per_depth * depth, maxf(base, risk_cap))
