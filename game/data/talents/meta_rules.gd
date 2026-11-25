class_name MetaRules
extends Resource
## Награда за забег в души (CR-04): за убитых врагов, пройденные уровни и победу. В Хардкоре — ×2
## (BalanceConfig.hardcore_reward). Души тратятся на таланты в хабе; сброс талантов возвращает долю.

@export var souls_per_kill := 0.05
@export var souls_per_level := 25
@export var victory_bonus := 100
## Доля душ, которая возвращается при сбросе талантов героя.
@export var respec_refund := 1.0


func run_reward(kills: int, levels_cleared: int, victory: bool, reward_mult: float) -> int:
	var souls := kills * souls_per_kill + levels_cleared * souls_per_level + (victory_bonus if victory else 0)
	return roundi(souls * reward_mult)
