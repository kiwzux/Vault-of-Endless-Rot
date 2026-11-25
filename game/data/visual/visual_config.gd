class_name VisualConfig
extends Resource
## Облик без влияния на игру: свет уровня (шаг 11.8), тряска, стоп-кадр, частицы, пятна, отдача (шаг 11.9),
## пост-эффекты (шаг 11.10).
## Считает каждый участник у себя, по сети ничего не уходит.
## Массивы *_by_quality — по качеству эффектов (Settings.effects_quality: 0 — низкое, 1 — среднее, 2 — высокое).
## Темнота и свечение опасных клеток — у биома (BiomeData, группа Light), свет тайлов — в раскладке атласа
## (art/gen_tileset.py, FACE_LIGHTS и DECOR_LIGHTS), свет точек интереса — InteractableData.light_radius.

@export_group("Light")
## Тексель карты света, px мира: 0 — света нет (уровень освещён целиком, как до шага 11.8).
@export var light_texel_by_quality := PackedInt32Array([0, 8, 4])
## Сколько источников рисуется за кадр (в пределах экрана): герои, затем объекты и тайлы, затем атаки.
@export var max_lights_by_quality := PackedInt32Array([0, 64, 160])
## Запас карты света за краем экрана, px мира: свет из-за края виден, край при сдвиге камеры не мигает.
@export var light_margin := 48.0
## Цвет — оттенок, альфа — энергия (0…1): столько света источник добавляет в центре пятна.
@export var hero_light := Color(1.0, 0.86, 0.66, 0.9)
@export var hero_light_radius := 170.0
## Павший герой (призрак) светит слабее.
@export var ghost_light_share := 0.4
## Снаряды и следы атак по виду (Projectile.kind, CombatFx.kind): радиус света, px мира. −1 — радиус самой атаки
## (взрыв, зона, ловушка, телеграф, импульс) × area_light_share. Вида нет в списке — атака не светит.
@export var attack_light_radius := {
	&"fireball": 56.0, &"ember": 30.0, &"frost": 30.0, &"shard": 28.0, &"acid": -1.0, &"blast": -1.0,
	&"smite": -1.0, &"zone": -1.0, &"trap": 26.0, &"warn": -1.0, &"lightning": 72.0, &"pulse": -1.0,
	&"orbit": -1.0, &"beam": 64.0, &"nova": -1.0,
}
@export var attack_light_energy := 0.6
@export var area_light_share := 1.25
## Телеграф удара врага светит ярче атак героя: его надо видеть и в темноте.
@export var telegraph_light_energy := 0.75
## Предметы на земле этой редкости (ItemRoller.Rarity) и выше светятся цветом редкости.
@export var loot_light_min_rarity := 2
@export var loot_light_radius := 40.0
@export var loot_light_energy := 0.55
## Объекты карты по виду (PropFactory: kind; испытания — id алтаря): цвет с энергией в альфе и радиус.
## Точки интереса (Interactable) светят своим цветом InteractableData.color с радиусом из данных.
@export var prop_light_colors := {
	&"portal": Color(0.7, 0.45, 1.0, 0.8), &"merchant": Color(1.0, 0.75, 0.4, 0.7), &"fountain": Color(0.45, 0.75, 1.0, 0.55),
	&"obelisk": Color(0.6, 0.8, 1.0, 0.45), &"grail_site": Color(1.0, 0.85, 0.4, 0.5), &"statue": Color(0.75, 0.75, 0.85, 0.3),
	&"chest": Color(1.0, 0.8, 0.45, 0.35), &"trial_altar": Color(1.0, 0.6, 0.3, 0.6), &"cursed_totem": Color(0.8, 0.2, 0.4, 0.6),
}
@export var prop_light_radius := {
	&"portal": 110.0, &"merchant": 80.0, &"fountain": 70.0, &"obelisk": 60.0, &"grail_site": 60.0, &"statue": 50.0,
	&"chest": 40.0, &"trial_altar": 70.0, &"cursed_totem": 70.0,
}
@export var interactable_light_energy := 0.55
## Объект, которым уже воспользовались (сундук открыт, святилище погасло), светит этой долей.
@export var used_light_share := 0.0
## Мерцание огня: доля энергии и частота, рад/с; у каждого источника своя фаза.
@export var flicker := 0.12
@export var flicker_speed := 9.0

@export_group("Shake")
## Тряска камеры своего героя (шаг 11.9, Juice): сила 0…1 складывается от событий и спадает на shake_decay в секунду;
## смещение — max_offset × сила², px мира. Отключается в настройках (Settings.screen_shake).
@export var shake_max_offset := 7.0
@export var shake_decay := 2.4
@export var shake_frequency := 26.0
@export var shake_hero_hurt := 0.35
## Взрыв удара врага: сила в центре, к shake_blast_reach px от своего героя спадает до нуля.
@export var shake_hostile_blast := 0.45
@export var shake_blast_reach := 220.0
@export var shake_boss_spawn := 0.6
@export var shake_elite_death := 0.25
@export var shake_boss_death := 0.8
@export var shake_secret := 0.35

@export_group("Hit stop")
## Стоп-кадр: время почти стоит (Engine.time_scale) столько реальных секунд. Только в одиночной игре —
## в кооперативе время общее. Отключается в настройках (Settings.hit_stop).
@export var hit_stop_scale := 0.05
@export var stop_hero_hurt := 0.035
@export var stop_elite_death := 0.05
@export var stop_boss_death := 0.14

@export_group("Particles")
## Искры и капли — один узел, предел живых частиц по качеству эффектов.
@export var particle_limit_by_quality := PackedInt32Array([80, 260, 520])
@export var hit_sparks := 2
@export var crit_sparks := 5
@export var spark_color := Color(1.0, 0.86, 0.55)
## Доля частиц удара — капли крови (цвет — blood_color), остальное — искры.
@export var hit_blood_share := 0.5
@export var blood_color := Color(0.55, 0.05, 0.05)
## Брызги при смерти врага — цветом врага (EnemyData.placeholder_color): кровь, костная пыль, эктоплазма, угли.
@export var death_particles := 9
@export var elite_death_particles := 22
@export var particle_speed := 75.0
@export var particle_life := 0.45
@export var particle_gravity := 160.0

@export_group("Skill effects")
## Короткие эффекты навыков (шаг 11.21, SkillFxLayer): вспышки выстрела и искры попаданий — предел живых по качеству.
@export var vfx_limit_by_quality := PackedInt32Array([40, 140, 280])
## Где у героя рука со вспышкой выстрела относительно точки на земле, px мира.
@export var cast_flash_offset := Vector2(0.0, -12.0)

@export_group("Stains")
## Пятна на месте смерти врагов (EnemyCorpses): предел по качеству и сколько секунд гаснут.
@export var stain_limit_by_quality := PackedInt32Array([0, 48, 120])
@export var stain_time := 8.0
@export var stain_alpha := 0.6

@export_group("Post")
## Пост-эффекты (шаг 11.10, PostFx; отключаются в настройках Settings.post_effects). Виньетка: цвет с силой в альфе.
@export var vignette := Color(0, 0, 0, 0.45)
## Рана своего героя: края краснеют (цвет с силой в альфе) и гаснут за hurt_pulse_time с.
@export var hurt_vignette := Color(0.55, 0.0, 0.0, 0.4)
@export var hurt_pulse_time := 0.35
## Мало здоровья (доля): края пульсируют красным, удар — лёгкая хроматическая аберрация (не чаще cooldown).
@export var low_health := 0.3
@export var low_health_vignette := Color(0.45, 0.0, 0.0, 0.5)
## Сдвиг каналов аберрации — доля расстояния до центра экрана.
@export var aberration := 0.012
@export var aberration_time := 0.3
@export var aberration_cooldown := 1.2

@export_group("Recoil")
## Отдача врага от удара — только картинка (спрайт сдвигается от ближайшего героя и возвращается), px мира.
@export var recoil := 2.5
@export var recoil_time := 0.09

@export_group("Icons")
## Значки атласа предметов (art/gen_icons.py, ItemIcon) у того, что не описано ресурсом: зелье в поясе и на земле,
## Ключ босса. Значки экипировки и товаров — в их данных (ItemBaseData.icons, UniqueItemData.icon, GoodsData.icon).
@export var potion_icon: StringName = &"potion_18"
@export var key_icon: StringName = &"relic_01"
## Размер значка предмета на земле, px мира (рисунок в клетке занимает ~3/4).
@export var ground_icon_size := 20.0


func light_texel(quality: int) -> int:
	return light_texel_by_quality[clampi(quality, 0, light_texel_by_quality.size() - 1)]


func max_lights(quality: int) -> int:
	return max_lights_by_quality[clampi(quality, 0, max_lights_by_quality.size() - 1)]


func particle_limit(quality: int) -> int:
	return particle_limit_by_quality[clampi(quality, 0, particle_limit_by_quality.size() - 1)]


func vfx_limit(quality: int) -> int:
	return vfx_limit_by_quality[clampi(quality, 0, vfx_limit_by_quality.size() - 1)]


func stain_limit(quality: int) -> int:
	return stain_limit_by_quality[clampi(quality, 0, stain_limit_by_quality.size() - 1)]


## Радиус света атаки вида kind размера size (радиус взрыва, зоны, импульса); 0 — не светит.
func attack_radius(kind: StringName, size: float) -> float:
	var radius: float = attack_light_radius.get(kind, 0.0)
	return size * area_light_share if radius < 0.0 else radius
