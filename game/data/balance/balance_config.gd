class_name BalanceConfig
extends Resource
## Баланс боя в одном месте (шаг 2, R7): урон и защита героя, кривая опыта, рост врагов с глубиной
## и волнами, элиты, «Хардкор». Пределы отдельных характеристик (Уклонение, Стойкость…) — StatDef.cap.
## Числа читает только хост, кроме подписей листа героя.

@export_group("Hero offense")
## Множитель удачного удара (Удача, HoMM3); Сокрушение прибавляется сверху.
@export var crit_mult := 2.0
## Перезарядка не короче этой доли от базовой, сколько бы ни было Спешки.
@export var min_cooldown_mult := 0.4
## Ярость действует, пока здоровья меньше этой доли.
@export var berserk_threshold := 0.5

@export_group("Hero defense")
## Урон по герою после брони — не меньше этого.
@export var min_damage_taken := 1.0
## Оберег заряжается за столько секунд (быстрее с характеристикой ward).
@export var ward_interval := 10.0
## Второе дыхание поднимает с этой долей здоровья.
@export var revival_health := 0.5
## Зелье из пояса лечит эту долю здоровья.
@export var potion_heal := 0.4
@export var base_pickup_radius := 40.0
## Урон по герою растёт с его уровнем: ×(1 + доля × (уровень − 1)) — прокачка не делает забег прогулкой.
## Урон среды (BiomeData.hazard_hero_damage — доля здоровья) не растёт. 18.10.2026: 0,05 → 0,02 (на 20-м ×1,38, было ×1,95).
@export var damage_taken_per_hero_level := 0.02
## Один удар (после брони и стойкости) снимает не больше этой доли наибольшего здоровья (18.10.2026): ни враг, ни
## босс не убивают героя с полного здоровья быстрее чем за 4 удара, как бы ни вырос урон с глубиной и кругами.
@export var max_hit_share := 0.25

@export_group("Experience")
## Опыт до следующего уровня: xp_first на 1-м уровне, дальше на xp_step больше за каждый уровень (ФТ-10).
## 17.10.2026: чуть медленнее (было 4 и 6 — до 20-го уровня 1102 опыта, стало 1292).
@export var xp_first := 5
@export var xp_step := 7
## После xp_late_from-го уровня каждый уровень дороже ещё на xp_late_step × (уровень − xp_late_from)² (18.10.2026,
## по журналу боёв): навыки упираются в 20-й уровень, а к финалу герои доходили до 115–200 — сверх 6 навыков
## уровни шли в пассивки, и поздние боссы таяли за 16–25 с. Тот же опыт теперь даёт 85–102 уровня вместо 115–200;
## 80-й — 73-й, до 60-го — как было.
@export var xp_late_from := 60
@export var xp_late_step := 4.0
## Доля опыта, которую герой получает с кристаллов, сундуков и наград (UpgradeSystem.grant_xp): 17.10.2026 — на 35 %
## меньше. «Обучаемость» и таланты прибавляются сверху; опыт «до следующего уровня» (книга алхимика) — без неё.
@export var xp_gain_mult := 0.65
## Кристаллы крупнее с глубиной забега и с каждой волной уровня.
@export var xp_growth_per_level := 0.3
@export var xp_growth_per_wave := 0.1

@export_group("Enemies")
## Рост силы врагов: с глубиной забега и с каждой следующей волной уровня (номер волны с нуля).
@export var health_growth_per_level := 0.3
## Во сколько раз больше врагов в волнах на этапе круга (RunPlan.stage: 1-й, 2-й, 3-й уровень, логово) —
## 17.10.2026: 2-й уровень ×3, 3-й ×5. Предел живых (WaveTable.max_alive, НФТ-07) не растёт.
@export var enemy_count_mults := PackedFloat32Array([1.0, 3.0, 5.0, 1.0])
## Каждый следующий круг (бесконечный режим, RunPlan.cycle) — здоровье врагов и боссов ещё ×cycle_health_mult
## (17.10.2026), сверх роста по глубине: 2-й круг ×1,75, 3-й ×3,06.
@export var cycle_health_mult := 1.75
## Урон врагов с глубиной и с волной: 18.10.2026 — 0,2 → 0,15 и 0,15 → 0,08 (герой не падает за 3 удара).
@export var damage_growth_per_level := 0.15
@export var health_growth_per_wave := 0.2
@export var damage_growth_per_wave := 0.08
## Скорость шага всех врагов и боссов (не союзников героя) от EnemyData.speed: ×0,8 — на 20 % медленнее
## (14.10.2026). Рывки и приёмы боссов со своей скоростью и телеграфом не меняются.
@export var enemy_speed_mult := 0.8
## Скорость снарядов врагов и боссов (выстрелы, кольца, осколки): дальность та же, летят медленнее — легче уйти.
## 14.10.2026: 0,75, затем ещё −15 % → 0,6375.
@export var enemy_projectile_speed_mult := 0.6375
## Урон летящих снарядов врагов и боссов (то же, что выше; взрывы и зоны на земле — нет): −25 %.
@export var enemy_projectile_damage_mult := 0.75
## Урон всех врагов, кроме боссов (и подручных боссов), по герою: −15 % (14.10.2026), 18.10.2026 — 0,6.
## Боссы — boss_damage_at.
@export var enemy_damage_scale := 0.6
## Вес врагов с дальней атакой (выстрел, кольцо снарядов, навесной огонь) в составе волн: −10 %, затем ещё −20 %
## (14.10.2026) → 0,72; 18.10.2026 ещё −20 % → 0,576.
@export var ranged_spawn_weight := 0.576
## Урон дальних атак обычных врагов (выстрел, навесной огонь, кольцо снарядов; не боссов) сверх прочих поправок:
## 14.10.2026 −20 % (0,8), 18.10.2026 +15 % → 0,92.
@export var ranged_damage_mult := 0.92
## Доля врагов улучшенного тира за уровень глубины (CR-09): 0, 35 %, 70 %, дальше все.
@export var tier_chance_per_level := 0.35
## Сопротивление стихии не выше этого (EnemyData.resistances).
@export var max_resistance := 0.75

@export_group("Elites")
@export var elite_chance_base := 0.03
@export var elite_chance_per_level := 0.015
@export var elite_chance_max := 0.2
## С этой глубины у элиты два аффикса.
@export var elite_second_affix_level := 3
@export var elite_health_mult := 4.0
@export var elite_xp_mult := 5
@export var elite_size_mult := 1.25

@export_group("Co-op")
## Масштаб под число героев (шаг 6, раздел 6 техзадания): здоровье врагов и боссов ×coop_health_mults[героев − 1]
## (14.10.2026: вдвоём ×1,2, втроём ×1,3, вчетвером ×1,4; было +0,5 за героя), шанс элиты +coop_elite_per_player.
## Больше героев, чем в списке, — последний множитель. Число врагов не растёт: предел живых и трафик снимков (НФТ-07)
## те же, что в одиночной игре.
@export var coop_health_mults := PackedFloat32Array([1.0, 1.2, 1.3, 1.4])
@export var coop_elite_per_player := 0.25

@export_group("Bosses")
## Шаг 12: общая ручка здоровья всех боссов поверх EnemyData.max_health (подгонка по плейтесту одним числом).
@export var boss_health_mult := 1.0
## Здоровье босса с глубиной растёт быстрее, чем у волн (health_growth_per_level): к поздним боссам герой
## приходит с собранным билдом, и при росте как у волн они падали за секунды.
@export var boss_health_growth_per_level := 0.6
## Урон босса сверх роста врагов (enemy_damage_mult): ×boss_damage_mult у первого, +boss_damage_growth_per_level
## за глубину, не больше boss_damage_max. Подручные босса бьют как обычные враги.
## 18.10.2026: было ×3 → ×5 — босс убивал с одного удара; стало ×1,5 → ×2,5 (и предел удара max_hit_share).
@export var boss_damage_mult := 1.5
@export var boss_damage_growth_per_level := 0.35
@export var boss_damage_max := 2.5
## Боссы крупнее обычного облика и радиуса (как элиты — elite_size_mult): видно издалека, кто перед тобой.
@export var boss_size_mult := 1.5

@export_group("Hardcore")
@export var hardcore_enemy_health := 1.5
@export var hardcore_enemy_damage := 1.25
@export var hardcore_reward := 2.0

@export_group("Heat")
## Печати Скверны (шаг 12.3): каждое очко Скверны — души за забег ×(1 + heat_souls_per_point × Скверна)
## и шанс магических и лучших предметов ×(1 + heat_magic_find_per_point × Скверна). С Хардкором — множатся.
@export var heat_souls_per_point := 0.1
@export var heat_magic_find_per_point := 0.04

@export_group("Limits")
## Пределы (шаг 5): сколько объектов одновременно, чтобы худший случай не ронял кадр и сеть.
## Кристаллов опыта на земле не больше: сверх предела опыт добавляется к старому кристаллу (как красный
## кристалл в Vampire Survivors) — опыт не теряется.
@export var max_xp_gems := 250
## Узлов в World/Projectiles не больше: сверх предела новые снаряды, осколки, зоны и ловушки героев не
## создаются (SkillRuntime.shoot, раскол и рикошет). Снаряды врагов, взрывы и следы создаются всегда.
@export var max_hero_projectiles := 400


## ФТ-10: опыт до следующего уровня.
func xp_to_next(level: int) -> int:
	var late := maxi(level - xp_late_from, 0)
	return xp_first + xp_step * maxi(level - 1, 0) + roundi(xp_late_step * late * late)


## Множитель опыта за врага на глубине depth в волне wave.
func xp_mult(depth: int, wave: int) -> float:
	return (1.0 + xp_growth_per_level * depth) * (1.0 + xp_growth_per_wave * wave)


## Множители здоровья и урона врага на глубине depth в волне wave (без «Хардкора» и натиска).
func enemy_health_mult(depth: int, wave: int) -> float:
	return (1.0 + health_growth_per_level * depth) * (1.0 + health_growth_per_wave * wave)


## Надбавка здоровья врагов и боссов на круге cycle (RunPlan.cycle, с нуля): ×cycle_health_mult за каждый
## пройденный круг. Умножает WaveSpawner.spawn_enemy (здесь RunPlan недоступен — циклическая зависимость).
func cycle_health_at(cycle: int) -> float:
	return pow(cycle_health_mult, maxi(cycle, 0))


## Множитель числа врагов в волнах на этапе stage (RunPlan.stage, с нуля); вне списка — ×1.
func enemy_count_at(stage: int) -> float:
	return enemy_count_mults[stage] if stage >= 0 and stage < enemy_count_mults.size() else 1.0


func enemy_damage_mult(depth: int, wave: int) -> float:
	return (1.0 + damage_growth_per_level * depth) * (1.0 + damage_growth_per_wave * wave)


## Множитель здоровья босса на глубине depth (без «Хардкора» и кооператива).
func boss_health_at(depth: int) -> float:
	return boss_health_mult * (1.0 + boss_health_growth_per_level * depth)


## Множитель урона босса на глубине depth сверх enemy_damage_mult.
func boss_damage_at(depth: int) -> float:
	return minf(boss_damage_mult + boss_damage_growth_per_level * depth, boss_damage_max)


## Во сколько раз больше урона получает герой уровня level (до брони и стойкости).
func damage_taken_mult(level: int) -> float:
	return 1.0 + damage_taken_per_hero_level * maxi(level - 1, 0)


func tier_chance(depth: int) -> float:
	return tier_chance_per_level * depth


func elite_chance(depth: int) -> float:
	return minf(elite_chance_base + elite_chance_per_level * depth, elite_chance_max)


## Шаг 6: множители здоровья врагов и шанса элиты при players героях в забеге.
func coop_health_mult(players: int) -> float:
	if coop_health_mults.is_empty():
		return 1.0
	return coop_health_mults[clampi(players - 1, 0, coop_health_mults.size() - 1)]


func coop_elite_mult(players: int) -> float:
	return 1.0 + coop_elite_per_player * maxi(players - 1, 0)


func elite_affix_count(depth: int) -> int:
	return 2 if depth >= elite_second_affix_level else 1
