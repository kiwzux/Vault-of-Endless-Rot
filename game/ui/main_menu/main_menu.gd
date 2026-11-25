extends Control
## Главное меню: Начало (→ хаб) / Кооператив (→ лобби, ФТ-12) / Настройки / Выход.
## После разрыва сетевой сессии показывает, что случилось (например, хост покинул игру).
## В углу — метка сборки (BuildInfo): по ней игроки сверяют, что у всех одна версия игры для кооператива.


func _ready() -> void:
	%StartButton.pressed.connect(get_tree().change_scene_to_file.bind(ScenePaths.HUB))
	%CoopButton.pressed.connect(get_tree().change_scene_to_file.bind(ScenePaths.LOBBY))
	%SettingsButton.pressed.connect(get_tree().change_scene_to_file.bind(ScenePaths.SETTINGS))
	%ExitButton.pressed.connect(get_tree().quit)
	var notice := Net.take_notice()
	%Notice.visible = notice != ""
	%Notice.text = tr(notice) if notice != "" else ""
	%BuildLabel.text = tr("MENU_BUILD_DEV") if BuildInfo.is_dev() else tr("MENU_BUILD").format({"id": BuildInfo.id()})
	%StartButton.grab_focus()
