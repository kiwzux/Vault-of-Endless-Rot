extends Control
## Лобби кооператива (ФТ-12, УС-2, УС-3): создать сессию или подключиться по IP:порт, выбрать героя,
## дождаться друзей. Хост видит свои адреса для друзей, включает «Хардкор» и начинает забег —
## у всех участников загружается сцена уровня (Net._begin_run). Таланты героя берутся из профиля
## (их покупают в Убежище); лобби их только передаёт хосту — вместе с навыками, ещё не открытыми заданиями.
## В списке героев — только открытые классы (шаг 10).
## 14.10.2026: лобби — только окно подключения. Сессия создана или найдена — сразу общее Убежище (Sanctuary):
## там участники видят друг друга, выбирают героя, а хост начинает забег у Врат.

const ROW_COLOR := Color(0.86, 0.8, 0.68)
const SELF_COLOR := Color(1.0, 0.9, 0.6)
const ERROR_COLOR := Color(0.95, 0.45, 0.35)
const INFO_COLOR := Color(0.9, 0.75, 0.5)

## Открытые классы в порядке списка героев.
var _heroes: Array[HeroData] = []

@onready var hero_option: OptionButton = %HeroOption
@onready var address_edit: LineEdit = %Address
@onready var port_edit: LineEdit = %Port
@onready var hardcore_toggle: CheckButton = %HardcoreToggle
@onready var status_label: Label = %Status
@onready var players_title: Label = %PlayersTitle
@onready var players_box: VBoxContainer = %Players
@onready var host_info: Label = %HostInfo


func _ready() -> void:
	MetaProfile.ensure_loaded()
	for hero: HeroData in DataRegistry.HEROES:
		if MetaProfile.is_unlocked(hero.id):
			_heroes.append(hero)
			hero_option.add_item(tr(hero.name_key))
	var last := _heroes.find(DataRegistry.hero(MetaProfile.last_hero))
	hero_option.select(maxi(last, 0))
	address_edit.text = "127.0.0.1"
	port_edit.text = str(Net.DEFAULT_PORT)

	hero_option.item_selected.connect(func(_index: int) -> void: Net.choose_hero(_hero(), _talents(), MetaProfile.locked_skills()))
	hardcore_toggle.toggled.connect(Net.set_hardcore)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%LeaveButton.pressed.connect(func() -> void:
		Net.leave()
		_set_status(""))
	%StartButton.pressed.connect(Net.start_run)
	%BackButton.pressed.connect(_back)
	Net.session_started.connect(_on_session_started)
	Net.roster_changed.connect(_refresh)
	Net.session_failed.connect(func(reason: String) -> void:
		_set_status(tr(reason).format(Net.failure_args.merged({"port": port_edit.text})), true)
		_refresh())
	Net.session_ended.connect(func(reason: String) -> void:
		Net.take_notice()  # сообщение уже показано здесь — главному меню повторять не нужно
		_set_status(tr(reason) if reason != "" else "", true)
		_refresh())
	_set_status(tr("LOBBY_HINT"))
	_refresh()
	%HostButton.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()


func _hero() -> HeroData:
	return _heroes[clampi(hero_option.selected, 0, _heroes.size() - 1)]


func _talents() -> Dictionary:
	return MetaProfile.talents_for(_hero())


## Порт из поля; 0 — введено не число или вне диапазона.
func _port() -> int:
	var text := port_edit.text.strip_edges()
	var port := text.to_int() if text.is_valid_int() else 0
	return port if port >= 1024 and port <= 65535 else 0


func _on_host_pressed() -> void:
	if _port() == 0:
		_set_status(tr("LOBBY_BAD_PORT"), true)
		return
	if Net.host(_port(), _hero(), _talents(), MetaProfile.locked_skills()) == OK:
		MetaProfile.set_last_hero(_hero())
		Net.port_mapper.open(_port())  # друзьям по Интернету — порт на роутере (UPnP), итог видно в Убежище


func _on_join_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address == "" or _port() == 0:
		_set_status(tr("LOBBY_BAD_ADDRESS"), true)
		return
	if Net.join(address, _port(), _hero(), _talents(), MetaProfile.locked_skills()) == OK:
		MetaProfile.set_last_hero(_hero())
		_set_status(tr("LOBBY_CONNECTING").format({"address": address, "port": _port()}))
		_refresh()


## Сессия есть — в общее Убежище (хост создал сервер, клиент подключился).
func _on_session_started() -> void:
	_set_status(tr("LOBBY_HOSTING") if Net.is_host() else tr("LOBBY_WAIT_HOST"))
	_refresh()
	get_tree().change_scene_to_file.call_deferred(ScenePaths.HUB)


func _back() -> void:
	Net.leave()
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)


func _refresh() -> void:
	var online := Net.is_online()
	var busy := online or Net.state == Net.State.CONNECTING
	%ConnectBox.visible = not online
	%ConnectButtons.visible = not online
	%HostButton.disabled = busy
	%JoinButton.disabled = busy
	%LeaveButton.visible = busy
	%StartButton.visible = Net.is_host()
	hardcore_toggle.disabled = not Net.is_host()
	hardcore_toggle.set_pressed_no_signal(Net.hardcore if online else false)

	for child in players_box.get_children():
		players_box.remove_child(child)
		child.queue_free()
	var ids := Net.players()
	players_title.text = tr("LOBBY_PLAYERS").format({"count": ids.size(), "max": Net.MAX_PLAYERS})
	for i in ids.size():
		players_box.add_child(_player_row(i, ids[i]))
	host_info.visible = Net.is_host()
	if Net.is_host():
		host_info.text = tr("LOBBY_HOST_INFO").format({"addresses": ", ".join(Net.local_addresses()), "port": _port()})


func _player_row(index: int, peer_id: int) -> Label:
	var entry: Dictionary = Net.roster[peer_id]
	var hero := DataRegistry.hero(entry.get("hero", &""))
	var text := tr("LOBBY_PLAYER_ROW").format({"n": index + 1, "hero": tr(hero.name_key) if hero != null else "—"})
	if peer_id == 1:
		text += " " + tr("LOBBY_MARK_HOST")
	if peer_id == multiplayer.get_unique_id():
		text += " " + tr("LOBBY_MARK_YOU")
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # текст уже переведён через tr()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", SELF_COLOR if peer_id == multiplayer.get_unique_id() else ROW_COLOR)
	return label


func _set_status(text: String, error: bool = false) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", ERROR_COLOR if error else INFO_COLOR)
