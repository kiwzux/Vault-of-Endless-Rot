class_name SealData
extends Resource
## Печать Скверны (шаг 12.3, как Пакт наказания в Hades; выбор пользователя): модификатор сложности забега
## с рангами. Каждый ранг даёт points очков Скверны; сумма Скверны умножает души за забег и шанс редкого лута
## (BalanceConfig.heat_*). Печати ставит у Врат хост — для всего отряда (RunConfig.seals, Net). Хардкор — отдельно.
## Новая печать с уже известным действием — только .tres; новое действие — ещё строка в RunConfig.seal_mult
## у того, что оно меняет.

## Что меняет печать: доля на ранг к множителю (×(1 + per_rank × ранг); у «heal» и «xp» per_rank < 0).
enum Stat {
	ENEMY_HEALTH,  ## здоровье врагов (и боссов)
	ENEMY_DAMAGE,  ## урон врагов
	ENEMY_SPEED,  ## скорость врагов
	WAVE_SIZE,  ## врагов в пачке волны (предел живых — прежний, НФТ-07)
	ELITE_CHANCE,  ## шанс элиты
	BOSS_HEALTH,  ## здоровье боссов сверх ENEMY_HEALTH
	HEAL,  ## лечение героев (зелья, вампиризм, восстановление)
	PRICES,  ## цены сундуков, торговцев и переброса карт
	XP,  ## опыт за врагов
}

@export var id: StringName
@export var name_key: String
## Описание: {value} — сколько даёт один ранг, % (без знака).
@export var description_key: String
@export var stat := Stat.ENEMY_HEALTH
@export var per_rank := 0.2
@export var max_rank := 3
## Очков Скверны за ранг.
@export var points := 1
## Порядок в окне печатей.
@export var order := 0
@export var icon_color := Color(0.75, 0.3, 0.9)


## Множитель печати на ранге rank.
func mult(rank: int) -> float:
	return maxf(1.0 + per_rank * clampi(rank, 0, max_rank), 0.0)


## Печати из сети или файла: только известные, ранг — целое в пределах данных, нулевые отброшены.
static func sanitize(raw: Variant) -> Dictionary:
	var result := {}
	if not (raw is Dictionary):
		return result
	for key: Variant in raw:
		var seal := DataRegistry.seal(StringName(str(key))) if (key is String or key is StringName) else null
		var rank: Variant = raw[key]
		if seal == null or not (rank is int or rank is float):
			continue
		var clamped := clampi(int(rank), 0, seal.max_rank)
		if clamped > 0:
			result[seal.id] = clamped
	return result


## Скверна набора печатей: сумма рангов × очки.
static func heat_of(chosen: Dictionary) -> int:
	var total := 0
	for id: Variant in chosen:
		var seal := DataRegistry.seal(StringName(str(id)))
		if seal != null:
			total += seal.points * clampi(int(chosen[id]), 0, seal.max_rank)
	return total


## Описание ранга с числом: «Враги крепче на 20 %».
func describe() -> String:
	return TranslationServer.translate(description_key).format({"value": roundi(absf(per_rank) * 100.0)})
