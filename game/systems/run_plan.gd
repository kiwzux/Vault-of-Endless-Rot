class_name RunPlan
extends RefCounted
## Структура забега. Круг = уровни по биомам (data/biomes/, BiomeData.order): Проклятый лес → Затопленный склеп →
## Пылающий собор, затем телепорт в логово финального босса — Бездну (CR-08, шаг 9). Победа над ним открывает
## два портала: «Завершить забег» и «Бесконечная гниль» — следующий круг тех же биомов, сложнее (глубина растёт).
## level_index — сквозной номер уровня забега (GameState.level_index), он же глубина.
## Этапы — функции, а не статические поля: поля скрипта заполняются при его загрузке, а RunPlan загружается
## как зависимость самого каталога, ещё до того, как каталог собран.


## Уровней в круге — столько, сколько биомов.
static func levels_per_cycle() -> int:
	return DataRegistry.BIOMES.size()


## id биомов по этапам; совпадают с биомами палитры (models/palette.json) — это условие CVAE.
static func stages() -> Array[StringName]:
	var result: Array[StringName] = []
	for item: BiomeData in DataRegistry.BIOMES:
		result.append(item.id)
	return result


static func stage(level_index: int) -> int:
	return level_index % levels_per_cycle()


@warning_ignore("integer_division")
static func cycle(level_index: int) -> int:
	return level_index / levels_per_cycle()


static func biome(level_index: int) -> BiomeData:
	return DataRegistry.BIOMES[stage(level_index)]


static func stage_name(level_index: int) -> StringName:
	return biome(level_index).id


static func is_final(level_index: int) -> bool:
	return biome(level_index).final_lair


## id биома для условия генератора (cond CVAE).
static func biome_for(level_index: int) -> int:
	return maxi(Palette.biomes().find(String(stage_name(level_index))), 0)


## Номер биома логова в палитре: к нему «загнивает» условие остальных с глубиной (DESIGN 6, фишка 1).
static func final_biome_index() -> int:
	for item: BiomeData in DataRegistry.BIOMES:
		if item.final_lair:
			return Palette.biomes().find(String(item.id))
	return -1


static func biome_key(level_index: int) -> String:
	return biome(level_index).name_key

