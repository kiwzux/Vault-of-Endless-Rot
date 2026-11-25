class_name InteractableData
extends Resource
## Интерактивная точка карты (шаг 8, раздел 4 техзадания): вид поведения и его числа — данные, а не код.
## Где встаёт, решает карта CVAE (ОГР-02): placement — метка модели, на которой или рядом с которой точка
## появляется (LevelFlow._spawn_interactables). Новая точка того же вида — только .tres в data/interactables/.
## Поведение по виду — Interactable (entities/props/interactable.gd).

enum Kind {
	## Святилище: временный бафф активировавшему и союзникам рядом; одно на всех, гаснет после использования.
	SHRINE,
	## Алтарь проклятий: до конца уровня враги крепче, зато опыт, золото и лут щедрее.
	CURSE_ALTAR,
	## Разрушаемое (бочка, урна, гроб): разбивается касанием, роняет добычу, иногда — засада.
	BREAKABLE,
	## Лор: надпись, книга, труп искателя — текст по E, запись в «Летопись».
	LORE,
	## Пленник: по E нападает стража (элиты); перебили — пленник награждает.
	PRISONER,
	## Треснувшая стена тайника (шаг 9): по E её бьют; после wall_hits ударов клетка становится полом,
	## открывается бонусная комната, иногда с её стражей.
	SECRET_WALL,
}

## Где встаёт: на метке фонтана (fountain), на клетке декора модели (rubble), рядом с меткой объекта
## (near_marker), рядом с меткой появления врагов (enemy_spawn); шаг 9 — на стене тайника (secret_door)
## и внутри тайника (secret); пасхалка (easter, 17.10.2026) — Золотое ведро: ObjectRules.golden_bucket_chance
## на первом уровне забега.
const PLACEMENTS: Array[StringName] = [&"fountain", &"rubble", &"near_marker", &"enemy_spawn", &"secret_door", &"secret",
		&"easter"]

@export var id: StringName
@export var name_key: String
@export var kind := Kind.SHRINE
@export var placement: StringName = &"near_marker"
## Вес выбора среди точек того же места и с какого уровня глубины точка встречается.
@export var weight := 1.0
@export var min_depth := 0
@export var color := Color.WHITE
## Свет точки цветом color (шаг 11.8, LightMap), px мира; 0 — не светит. Использованная точка гаснет.
@export var light_radius := 0.0

@export_group("Shrine")
## Бафф святилища: характеристики героя (Player.STAT_*) на buff_time секунд; союзники в радиусе — тоже.
@export var buff_stats := {}
@export var buff_time := 60.0
@export var share_radius := 160.0

@export_group("Curse altar")
## Прибавки до конца уровня: здоровье и урон новых врагов, опыт, золото и шанс лута (доли).
@export var curse_health := 0.4
@export var curse_damage := 0.2
@export var curse_reward := 0.5

@export_group("Breakable")
## Добыча: золото [мин, макс] до множителя глубины, шансы зелья и предмета, кристаллы опыта.
@export var gold := Vector2i.ZERO
@export var potion_chance := 0.0
@export var item_chance := 0.0
@export var xp_gems := 0
## Предмет не ниже этой редкости (ItemRoller.Rarity), если выпал.
@export var item_rarity := 0
## Засада: с этим шансом из обломков встаёт враг ambush_id (гроб — скелет).
@export var ambush_id: StringName
@export var ambush_chance := 0.0
## Облик: barrel, urn, coffin (рисует Interactable).
@export var look: StringName = &"barrel"

@export_group("Prisoner")
## Стража: столько элит текущей волны с guard_affixes аффиксами; награда — золото и предмет не ниже редкости.
@export var guard_count := 3
@export var guard_affixes := 1
@export var reward_gold := Vector2i(80, 140)
@export var reward_rarity := 2

@export_group("Secret wall")
## Ударов до пролома; с шансом guard_chance в тайнике встаёт стража (guard_count, guard_affixes из группы пленника).
@export var wall_hits := 3
@export var guard_chance := 0.35


func fits(depth: int) -> bool:
	return depth >= min_depth
