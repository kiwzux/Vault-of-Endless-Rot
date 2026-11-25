class_name SynergyData
extends Resource
## Резонанс тегов (шаг 4): навыки героя с одним тегом усиливают друг друга, как наборы в Diablo и
## черты в Halls of Torment. Считается, сколько у героя навыков с тегом tag (свои теги навыка и теги
## его рун, Synergies.counts); на пороге thresholds[i] действуют характеристики tiers[i]. Пороги
## не складываются: действует старший достигнутый.
##
## Характеристики — как у пассивок и предметов (StatDef), в том числе «по тегу» («might:fire»).
## Название — «Резонанс: <тег>» (SYNERGY_NAME), описание собирается из характеристик, поэтому новый
## резонанс — только .tres, без строк перевода.

@export var id: StringName
@export var order := 0
## Тег (TagDef), навыки с которым считаются.
@export var tag: StringName
## Сколько навыков с тегом нужно для порога 1, 2, … (по возрастанию).
@export var thresholds := PackedInt32Array([2, 3, 4])
## Характеристики порога: tiers[i] — {характеристика: значение} для thresholds[i].
@export var tiers: Array[Dictionary] = []


## Номер достигнутого порога (1, 2, …) при count навыках с тегом; 0 — ни один не достигнут.
func tier_for(count: int) -> int:
	var tier := 0
	for i in thresholds.size():
		if count >= thresholds[i]:
			tier = i + 1
	return tier


## Характеристики порога tier (с 1); пусто — такого порога нет.
func stats_for(tier: int) -> Dictionary:
	return tiers[tier - 1] if tier >= 1 and tier <= tiers.size() else {}


## Сколько навыков нужно для следующего порога; 0 — последний уже достигнут.
func next_threshold(count: int) -> int:
	for threshold in thresholds:
		if count < threshold:
			return threshold
	return 0
