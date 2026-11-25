class_name TalentData
extends Resource
## Талант в хабе (CR-04): постоянное улучшение героя между забегами, покупается за души.
## Ранг даёт per_rank к характеристике героя (Player.STAT_*) на весь забег. Особые характеристики:
## START_GOLD — золото в начале забега, WEAPON_MASTERY — уровни стартового оружия сверх первого.

const START_GOLD := &"start_gold"
const WEAPON_MASTERY := &"weapon_mastery"

@export var id: StringName
## Порядок показа в хабе (DataRegistry сортирует по нему).
@export var order := 0
## Чей талант (HeroData.id); пусто — общий для всех героев.
@export var hero: StringName
@export var name_key: String
@export var description_key: String
@export var stat: StringName
@export var per_rank := 0.0
@export var max_rank := 5
## Цена ранга r (с нуля): cost_base × cost_growth^r.
@export var cost_base := 50
@export var cost_growth := 1.6
@export var icon_color := Color.WHITE


func fits(p_hero: HeroData) -> bool:
	return hero == &"" or (p_hero != null and p_hero.id == hero)


func is_global() -> bool:
	return hero == &""


## Цена следующего ранга, если сейчас rank; 0 — предел достигнут.
func cost(rank: int) -> int:
	if rank >= max_rank:
		return 0
	return roundi(cost_base * pow(cost_growth, rank))
