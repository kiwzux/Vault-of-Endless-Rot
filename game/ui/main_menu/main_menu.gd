extends Control
## Главное меню: Убежище, настройки и выход.


func _ready() -> void:
	%StartButton.pressed.connect(get_tree().change_scene_to_file.bind(ScenePaths.HUB))
	%SettingsButton.pressed.connect(get_tree().change_scene_to_file.bind(ScenePaths.SETTINGS))
	%ExitButton.pressed.connect(get_tree().quit)
	%BuildLabel.text = tr("MENU_BUILD_DEV") if BuildInfo.is_dev() else tr("MENU_BUILD").format({"id": BuildInfo.id()})
	%StartButton.grab_focus()
