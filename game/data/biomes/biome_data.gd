class_name BiomeData
extends Resource
## Биом (шаг 9, раздел 4 техзадания): этап круга забега, условие CVAE, волны с боссом и правила слоя объектов.
## id совпадает с именем биома в models/palette.json — это номер условия модели (cond), поэтому биомов ровно
## столько, сколько их в палитре, и порядок order = порядок палитры = порядок этапов круга (RunPlan).
## Новый биом — новый .tres, новое имя в палитре и переобучение модели (ml/README.md): без этого CVAE его не знает.
## Графика — атлас assets/tiles/<id>.png (art/gen_tileset.py, LevelArt).

@export var id: StringName
## Этап круга: 0 — первый уровень; биом с final_lair — последний (логово финального босса).
@export var order := 0
@export var name_key: String
## Логово финального босса: босс ждёт сразу, таймера и портала на метке EXIT нет (LevelFlow).
@export var final_lair := false
## Волны и босс биома (ФТ-09).
@export var waves: WaveTable
## Правила слоя объектов поверх меток модели (ObjectLayer): что, сколько и с каким шансом.
@export var objects: ObjectRules

@export_group("Hazard")
## Опасные клетки биома (HazardSystem): название и описание для меню паузы; эффект действует на тех, кто
## стоит ближе hazard_reach px к клетке HAZARD.
@export var hazard_name_key: String
@export var hazard_desc_key: String
@export var hazard_reach := 18.0
## Героям: доля максимального здоровья в секунду и холод (замедление Player.chill).
@export var hazard_hero_damage := 0.0
@export var hazard_hero_chill := false
## Врагам: статус (StatusEffectData.id) и урон-основа как доля здоровья врага (у боссов — 0).
@export var hazard_status: StringName
@export var hazard_enemy_damage := 0.0

@export_group("Sound")
## Эмбиент уровня этого биома (шаг 11.13, автозагрузка Sound); пусто — музыка меню.
@export var music: AudioStream
## Боевой трек биома (шаг 11.28): плавно сменяет эмбиент, когда вокруг своего героя разгорается бой
## (AudioConfig, группа Battle); пусто — бой идёт под эмбиент.
@export var battle_music: AudioStream

@export_group("Decor")
## Предметы обстановки (шаг 11.29, DecorPlan): id предметов атласа props (art/gen_props.py, decor_*). У стен — высокие
## (дерево, колонна, статуя), на открытом полу — низкие (надгробие, пень, кости); повтор id — чаще.
@export var decor_wall: Array[StringName] = []
@export var decor_open: Array[StringName] = []
## Сколько предметов ставится на уровень, если хватает мест: у стен — по одному, на открытом полу — мест, на каждом
## от 1 до decor_cluster предметов кучкой (надгробия кладбищем, грибы, кости).
@export var decor_wall_count := 14
@export var decor_open_count := 8
@export var decor_cluster := 3

@export_group("Light")
## Тьма уровня (шаг 11.8, LightMap): столько света там, куда не достаёт ни один источник; белый — без затемнения.
@export var ambient_light := Color(0.45, 0.45, 0.5)
## Свечение опасных клеток (лава, топь, провал): цвет с энергией в альфе и радиус от центра клетки, px мира.
## Альфа 0 — клетки не светятся.
@export var hazard_light := Color(0, 0, 0, 0)
@export var hazard_light_radius := 80.0
