class_name AudioConfig
extends Resource
## Звук (шаг 11.13): музыка вне уровней, бой с боссом и звуки интерфейса. Трек уровня — BiomeData.music.
## Всё воспроизводит автозагрузка Sound у каждого участника отдельно: в сеть звук не уходит.
## Файлы — game/assets/audio/ (авторы и лицензии — game/assets/audio/CREDITS.txt).

@export_group("Music")
## Главное меню, лобби и экран настроек.
@export var menu_music: AudioStream
## Убежище.
@export var hub_music: AudioStream
## Пока на уровне жив босс (у всех участников: босса видно в списке врагов, сигнал хоста не нужен).
@export var boss_music: AudioStream
## Смена трека: старый затихает, новый нарастает, с.
@export var crossfade := 2.5
## Громкость музыки до ползунка «Музыка», дБ: эмбиент — фон, он не должен глушить бой.
@export var music_db := -8.0

@export_group("Battle")
## Боевые слои (шаг 11.28): напряжённость 0…1 вокруг своего героя — враги ближе battle_radius (px мира;
## элита и босс — по elite_weight), деленные на battle_full, плюс hurt_boost, пока рана свежее hurt_memory с.
@export var battle_radius := 220.0
@export var battle_full := 16.0
@export var elite_weight := 4.0
@export var hurt_boost := 0.35
@export var hurt_memory := 4.0
## Напряжённость растёт и спадает с этой скоростью, в долях в секунду: вспыхивает быстро, утихает медленно.
@export var rise_rate := 0.8
@export var fall_rate := 0.12
## Боевой трек включается, когда напряжённость дошла до battle_on, и уходит, когда она battle_hold секунд
## подряд не выше battle_off (запас между порогами — чтобы музыка не дёргалась туда-сюда).
@export var battle_on := 0.55
@export var battle_off := 0.2
@export var battle_hold := 6.0
## Смена эмбиента и боевого трека — быстрее обычной, с.
@export var battle_crossfade := 1.5
## В затишье эмбиент глуше: срез низких частот, Гц, и тише, дБ; с напряжённостью звук раскрывается.
@export var calm_cutoff_hz := 2200.0
@export var calm_volume_db := -3.0

@export_group("Interface")
@export var ui_hover: AudioStream
@export var ui_confirm: AudioStream
@export var ui_equip: AudioStream
@export var ui_level_up: AudioStream
@export var ui_magic: AudioStream
## Громкость звуков интерфейса до ползунка «Звуки», дБ.
@export var ui_db := -6.0
## Наведение на кнопки подряд (список карт, сетка навыков) звучит не чаще раза в столько секунд.
@export var hover_cooldown := 0.07


## Звук интерфейса по имени: hover, confirm, equip, level_up, magic; неизвестное — null.
func ui(sound: StringName) -> AudioStream:
	match sound:
		&"hover": return ui_hover
		&"confirm": return ui_confirm
		&"equip": return ui_equip
		&"level_up": return ui_level_up
		&"magic": return ui_magic
	return null
