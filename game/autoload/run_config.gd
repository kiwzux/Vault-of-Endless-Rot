extends Node
## Параметры текущего забега: герой, его таланты из хаба, сложность «Хардкор» (ХК), печати Скверны, биом, сид.
## ХК: павший игрок не воскрешается до конца уровня, враги крепче, награда в хабе выше (DESIGN 1);
## множители — BalanceConfig (hardcore_*).
## Печати Скверны (шаг 12.3): ранги модификаторов сложности (SealData); сумма их очков — Скверна — умножает души
## за забег и шанс редкого лута (BalanceConfig.heat_*). Ставит хост у Врат, клиентам приходят с началом забега
## (Net._begin_run) — у всех участников одни и те же.

var hero: HeroData
var hardcore := false
## Печати на этот забег: {id печати: ранг}, только известные печати и ранги в пределах данных.
var seals := {}
var biome := 0
var run_seed := 0
## Ранги талантов героя на этот забег (CR-04): {id таланта: ранг}. Снимок профиля на момент старта.
var talents := {}
## Навыки, ещё не открытые заданиями в профиле (шаг 10): в левел-апе их нет. Пусто — открыто всё
## (проверки и сцена уровня, запущенная из редактора).
var locked_skills: Array[StringName] = []
## Души за этот забег уже начислены (выход в хаб засчитывается один раз).
var reward_claimed := false
## Сколько душ дал последний забег — хаб показывает это при возвращении.
var last_reward := 0


func start_new_run(p_hero: HeroData, p_hardcore: bool, p_seed: int = 0, p_talents: Dictionary = {},
		p_locked: Array = [], p_seals: Dictionary = {}) -> void:
	hero = p_hero
	hardcore = p_hardcore
	seals = SealData.sanitize(p_seals)
	talents = p_talents.duplicate()
	locked_skills.assign(p_locked)
	reward_claimed = false
	last_reward = 0
	if p_seed != 0:
		run_seed = p_seed
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		run_seed = rng.randi()


## Герой по умолчанию нужен, когда сцена уровня запущена напрямую из редактора (F6).
func get_hero() -> HeroData:
	return hero if hero else DataRegistry.HEROES[0]


## Скверна этого забега.
func heat() -> int:
	return SealData.heat_of(seals)


## Множитель печатей этого забега на характеристику stat (SealData.Stat); печатей на неё нет — 1.
func seal_mult(stat: int) -> float:
	var mult := 1.0
	for id: StringName in seals:
		var seal := DataRegistry.seal(id)
		if seal != null and seal.stat == stat:
			mult *= seal.mult(int(seals[id]))
	return mult


func enemy_health_mult() -> float:
	return (DataRegistry.BALANCE.hardcore_enemy_health if hardcore else 1.0) * seal_mult(SealData.Stat.ENEMY_HEALTH)


func enemy_damage_mult() -> float:
	return (DataRegistry.BALANCE.hardcore_enemy_damage if hardcore else 1.0) * seal_mult(SealData.Stat.ENEMY_DAMAGE)


## Души за забег: Хардкор × Скверна.
func reward_mult() -> float:
	return (DataRegistry.BALANCE.hardcore_reward if hardcore else 1.0) * heat_reward(heat())


## Множитель душ за Скверну heat.
static func heat_reward(p_heat: int) -> float:
	return 1.0 + DataRegistry.BALANCE.heat_souls_per_point * maxi(p_heat, 0)


## Шанс магических и лучших предметов за Скверну этого забега.
func magic_find_mult() -> float:
	return 1.0 + DataRegistry.BALANCE.heat_magic_find_per_point * heat()
