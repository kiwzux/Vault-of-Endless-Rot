class_name MapRequest
extends RefCounted
## Вход генератора карт (шаг 9, раздел 4 техзадания): биом, сложность и сид. По нему LevelService.generate_map
## возвращает MapPlan — описание карты в едином формате. Сегодня карту рисует CVAE (ОГР-02); другой генератор
## (новая модель) принимает тот же запрос и возвращает тот же MapPlan, игра при этом не меняется.

var biome: BiomeData
## Сложность — сквозной номер уровня забега (глубина): от неё растут враги, «гниль» в условии и риск слоя объектов.
var depth := 0
## Сид забега (код забега, DESIGN 6, фишка 2): тот же сид, биом и глубина дают ту же карту и те же объекты.
var run_seed := 0


static func create(biome_data: BiomeData, level_depth: int, seed_value: int) -> MapRequest:
	var request := MapRequest.new()
	request.biome = biome_data
	request.depth = level_depth
	request.run_seed = seed_value
	return request


## Уровень level_index текущего забега: биом — этап круга (RunPlan), сид — RunConfig.run_seed.
static func for_run(level_index: int) -> MapRequest:
	return create(RunPlan.biome(level_index), level_index, RunConfig.run_seed)


## Номер биома в палитре — номер условия CVAE.
func biome_index() -> int:
	return maxi(Palette.biomes().find(String(biome.id)), 0) if biome != null else 0


func to_dict() -> Dictionary:
	return {"biome": String(biome.id) if biome != null else "", "depth": depth, "run_seed": run_seed}
