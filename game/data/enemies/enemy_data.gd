class_name EnemyData
extends Resource
## Описание врага или босса. Множители сложности (ХК, глубина) применяет хост при спавне.

@export var id: StringName
@export var name_key: String
@export var max_health := 10.0
@export var speed := 40.0
@export var contact_damage := 5.0
## Опыт за убийство: столько выпадает в кристалле. 0 — без кристалла.
@export var xp := 1
@export var radius := 6.0
@export var is_boss := false
## Цвет врага: его снаряды и вспышки, а у врага без листа в атласе (EnemyArt) — оттенок белой заглушки.
## Облик врага — лист с его id в атласе врагов (art/gen_enemies.py, шаг 11.2).
@export var placeholder_color := Color.WHITE
## Улучшенная версия (тир выше, как существа HoMM3, CR-09): с глубиной забега волны
## всё чаще выпускают её вместо этой.
@export var upgrade: EnemyData
## Гарантированный предмет не ниже этой редкости (ItemRoller.Rarity); -1 — без гарантии.
@export var loot_rarity := -1
## Сколько таких предметов (мимик — вдвое больше сундука, шаг 8).
@export var loot_items := 1
## Гарантированное золото [мин, макс] до множителя глубины (CR-14); ноль — только случайное
## по EconomyTable.
@export var gold := Vector2i.ZERO
## Сопротивления стихиям (шаг 2): id тега (TagDef) → доля урона, которая не проходит; меньше нуля —
## уязвимость. Не выше BalanceConfig.max_resistance.
@export var resistances := {}
## Врождённые повадки (18.10.2026, враги по эскизам): аффиксы-поведения элит (EliteAffixData: огненный след,
## телепорт к герою, вампиризм, каменная кожа, взрыв после смерти…) у каждого врага этого вида — но без статуса
## элиты: ни прибавки здоровья, размера и опыта, ни ауры и подписи. Считает хост; новых сетевых данных нет.
@export var innate_affixes: Array[StringName] = []

@export_group("Ring attack")
## Кольцо снарядов во все стороны; 0 — атаки нет.
@export var ring_count := 0
@export var ring_interval := 4.0
@export var ring_damage := 10.0
@export var ring_speed := 100.0
@export var ring_range := 260.0

@export_group("Ranged attack")
## Выстрел в цель; 0 — враг только бьёт вплотную.
@export var shot_interval := 0.0
@export var shot_range := 160.0
@export var shot_damage := 8.0
@export var shot_speed := 120.0
## Стрелок держится на этой дистанции и не идёт вплотную; 0 — идёт.
@export var keep_distance := 0.0
## Снарядов за выстрел (веер) и угол веера; 1 — одиночный выстрел.
@export var shot_count := 1
@export var shot_spread_deg := 30.0
## Навесной огонь (мортира): снаряд не летит, а через shot_fuse секунд взрывается там, где стоял герой
## в момент выстрела, радиусом shot_blast. Уклоняться — уходить из круга.
@export var shot_lob := false
@export var shot_blast := 34.0
@export var shot_fuse := 1.1

@export_group("Special")
## Рывок: замирает на charge_windup секунд (видно по вспышке), затем бросается на героя.
@export var charge_interval := 0.0
@export var charge_windup := 0.6
@export var charge_speed := 260.0
@export var charge_time := 0.45
@export var charge_range := 220.0
## Самоподрыв вплотную: взрывается при касании героя (урон и радиус), умирает без награды за убийство.
@export var suicide_damage := 0.0
@export var suicide_radius := 34.0
## Деление при смерти: столько врагов split_id появляются на месте убитого.
@export var split_id: StringName
@export var split_count := 0
## Целитель: каждые heal_interval секунд лечит раненых врагов в радиусе на долю их здоровья.
@export var heal_interval := 0.0
@export var heal_radius := 110.0
@export var heal_share := 0.25
## Телепорт: каждые blink_interval секунд переносится на blink_range ближе к герою (в обход стен).
@export var blink_interval := 0.0
@export var blink_range := 120.0

@export_group("Boss")
## Призыв подручных вокруг себя.
@export var summon_id: StringName
@export var summon_count := 0
@export var summon_interval := 8.0
## Ниже этой доли здоровья — ярость: быстрее ходит и чаще стреляет кольцом. 0 — без ярости.
## У боссов шага 12 вместо неё — фазы (phase_thresholds).
@export var enrage_below := 0.0
## Шаг 12: приёмы босса (BossAttack, data/enemies/boss_attacks/) — по очереди, случайно по весу, без повтора
## подряд, только открытые его фазой. Пусто — враг пользуется полями выше (кольцо, выстрел, призыв).
@export var attacks: Array[BossAttack] = []
## Пороги фаз — доли здоровья по убыванию: [0.66, 0.33] — три фазы. Новая фаза: босс замирает, затем приём,
## открытый этой фазой; ходит быстрее (×phase_speed_mult за фазу), передышки короче (×phase_tempo за фазу);
## последняя фаза — облик ярости.
@export var phase_thresholds := PackedFloat32Array()
@export var phase_speed_mult := 1.12
@export var phase_tempo := 0.85
