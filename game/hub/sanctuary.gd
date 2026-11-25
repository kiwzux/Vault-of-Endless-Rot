class_name Sanctuary
extends Node2D
## Убежище — ходячий хаб между забегами (CR-04, шаг 10.3; техзадание docs/GAME_DESIGH.md, раздел 5).
## Герой ходит по залу и у станций нажимает E:
## - статуи классов (Зал героев) — встать другим героем; закрытый класс показывает задание, которое его открывает;
## - Алтарь душ — таланты героя; Доска заданий — цели «Летописи» и награды; Летопись — рекорды, бестиарий, трофеи;
## - Врата бездны — «Хардкор» и начало забега; стол кооператива — лобби; дверь — главное меню.
## Профиль — MetaProfile; зал — SanctuaryMap.
## Кооператив (14.10.2026): в сессии (Net.is_online) Убежище общее — сюда ведёт лобби после создания сервера или
## подключения, сюда же все возвращаются после забега. Свой герой рассылается остальным (Net.send_hub_state), чужие
## ходят по залу (HubHero.remote). Герой и таланты уходят хосту (Net.choose_hero) при выборе у статуи и после
## окон станций; забег у Врат начинает хост для всех, «Хардкор» — его; стол кооператива показывает отряд;
## дверь и Esc — выход из отряда в главное меню. Профиль у каждого участника свой.

const HERO_SCENE := preload("res://hub/hub_hero.tscn")
const NOTICE_TIME := 5.0
## Зал тёмный, главный свет — костёр (шаг 11.12: «строгий dark fantasy»).
const AMBIENT := Color(0.16, 0.14, 0.19)
const FIRE_LIGHT := Color(1.0, 0.62, 0.3)
const FIRE_ENERGY := 1.7
const PORTAL_LIGHT := Color(1.0, 0.45, 0.15)
const PROMPT_COLOR := Color(1.0, 0.9, 0.6)
const LOCKED_COLOR := Color(0.85, 0.45, 0.35)
## Как часто свой герой рассылается остальным участникам, с.
const SEND_INTERVAL := 0.05

## Герой, который уйдёт в забег (выбран у статуи).
var hero: HeroData
var hardcore := false
## Печати Скверны на следующий забег (шаг 12.3): {id печати: ранг}. В одиночной игре — с прошлого забега
## (профиль), в кооперативе — выбор хоста (Net.seals).
var seals := {}
var stations: Array[HubStation] = []

var _hero_node: HubHero
var _near: HubStation
var _windows := {}
var _notice_left := 0.0
var _fire_time := 0.0
var _fire_light: PointLight2D
## Кооператив: герои других участников (peer id → HubHero) и таймер рассылки своего.
var _remote := {}
var _send_left := 0.0

@onready var ground: TileMapLayer = $Level/Ground
@onready var art: TileMapLayer = $Level/Art
@onready var markers: TileMapLayer = $Level/Markers
@onready var props: Node2D = $Props
@onready var fire: Node2D = $Props/Fire
@onready var prompt: Label = %Prompt
@onready var souls_label: Label = %Souls
@onready var notice_label: Label = %Notice
@onready var hero_card: PanelContainer = %HeroCard
@onready var host_info: Label = %HostInfo


func _ready() -> void:
	MetaProfile.ensure_loaded()
	get_tree().paused = false
	var level := SanctuaryMap.make()
	LevelBuilder.build(level, ground, markers, art)
	hero = DataRegistry.hero(MetaProfile.last_hero)
	if hero == null or not MetaProfile.is_unlocked(hero.id):
		hero = DataRegistry.HEROES[0]
	_build_stations()
	_build_decor()
	_build_lights(level)
	_hero_node = HERO_SCENE.instantiate()
	_hero_node.hero = hero
	_hero_node.position = SanctuaryMap.point(SanctuaryMap.SPAWN)
	props.add_child(_hero_node)
	var hall := SanctuaryMap.HALL.grow(1)
	var tile := Palette.tile_size()
	_hero_node.set_camera_limits(Rect2i(hall.position * tile, hall.size * tile))

	for window: HubWindow in [TalentsWindow.new(), QuestWindow.new(), ChronicleWindow.new(), GateWindow.new(),
			SealsWindow.new()]:
		window.sanctuary = self
		window.closed.connect(_on_window_closed)
		%Windows.add_child(window)
	_windows = {&"altar": %Windows.get_child(0), &"board": %Windows.get_child(1),
			&"chronicle": %Windows.get_child(2), &"gate": %Windows.get_child(3), &"seals": %Windows.get_child(4)}
	_update_statues()
	seals = MetaProfile.last_seals.duplicate()
	if Net.is_online():
		hardcore = Net.hardcore
		if Net.is_host():
			Net.set_seals(seals)  # отряд сразу видит печати хоста
		else:
			seals = Net.seals.duplicate()
	Net.hub_state_received.connect(_on_hub_state)
	Net.roster_changed.connect(_on_roster_changed)
	Net.session_ended.connect(_on_session_ended)
	Net.port_mapper.changed.connect(refresh_status)
	_sync_choice()
	refresh_status()
	_greet()


func _process(delta: float) -> void:
	_fire_time += delta
	if Net.is_online():
		_send_left -= delta
		if _send_left <= 0.0:
			_send_left = SEND_INTERVAL
			Net.send_hub_state(hero.id, _hero_node.position)
	# Костёр дышит: свет колышется двумя несоизмеримыми частотами, без рывков.
	_fire_light.energy = FIRE_ENERGY * (1.0 + 0.12 * sin(_fire_time * 7.3) * sin(_fire_time * 2.9 + 1.0))
	if _notice_left > 0.0:
		_notice_left -= delta
		notice_label.modulate.a = clampf(_notice_left, 0.0, 1.0)
	var blocked := window_open()
	_hero_node.blocked = blocked
	var near: HubStation = null if blocked else _nearest_station()
	if near != _near:
		_near = near
		_show_hero_card(near.hero if near != null and near.kind == HubStation.Kind.STATUE else null)
	prompt.visible = _near != null
	if _near != null:
		prompt.text = _prompt_text(_near)
		prompt.add_theme_color_override("font_color", LOCKED_COLOR if _near.locked else PROMPT_COLOR)
		# Подсказка — на слое интерфейса (свет зала её не затемняет): мировая точка → экран.
		prompt.size = Vector2.ZERO
		var anchor := get_viewport().get_canvas_transform() * (_near.position - Vector2(0, _near.height() + 6.0))
		prompt.position = anchor - Vector2(prompt.get_combined_minimum_size().x / 2.0, 10.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		var open := _open_window()
		if open != null:
			open.close_window()
		else:
			to_main_menu()
	elif event.is_action_pressed(&"interact") and not window_open() and _near != null:
		get_viewport().set_input_as_handled()
		interact(_near)


## Действие станции (E). Проверки вызывают его напрямую.
func interact(station: HubStation) -> void:
	match station.kind:
		HubStation.Kind.STATUE:
			if station.locked:
				show_notice(_locked_text(station.hero.id))
			elif station.hero != hero:
				choose_hero(station.hero)
		HubStation.Kind.WAR_TABLE:
			if Net.is_online():  # уже в отряде: стол показывает, кто в нём
				show_notice(party_text())
				return
			MetaProfile.set_last_hero(hero)
			get_tree().change_scene_to_file(ScenePaths.LOBBY)
		HubStation.Kind.EXIT:
			to_main_menu()
		_:
			open_window(station.id)


## В главное меню; в кооперативе — выйти из отряда.
func to_main_menu() -> void:
	Net.leave()
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)


func choose_hero(p_hero: HeroData) -> void:
	if not MetaProfile.is_unlocked(p_hero.id):
		return
	hero = p_hero
	_hero_node.set_hero(hero)
	MetaProfile.set_last_hero(hero)
	_update_statues()
	_sync_choice()
	show_notice(tr("HUB_HERO_CHOSEN").format({"name": tr(hero.name_key)}))


## Кооператив: свой герой, его таланты и закрытые навыки — хосту (с ними участник уйдёт в забег).
func _sync_choice() -> void:
	if Net.is_online():
		Net.choose_hero(hero, MetaProfile.talents_for(hero), MetaProfile.locked_skills())


## Состав отряда: «Отряд 2/4: Рыцарь-отступник (хост), Некромант (вы)».
func party_text() -> String:
	var names := PackedStringArray()
	for peer in Net.players():
		var member := DataRegistry.hero(Net.roster[peer].get("hero", &""))
		var text := tr(member.name_key) if member != null else "—"
		if peer == 1:
			text += " " + tr("LOBBY_MARK_HOST")
		if peer == multiplayer.get_unique_id():
			text += " " + tr("LOBBY_MARK_YOU")
		names.append(text)
	return tr("HUB_PARTY").format({"count": Net.players().size(), "max": Net.MAX_PLAYERS, "list": ", ".join(names)})


func open_window(id: StringName) -> HubWindow:
	var window: HubWindow = _windows.get(id)
	if window != null:
		_show_hero_card(null)
		window.open()
	return window


func window_open() -> bool:
	return _open_window() != null


## Врата: забег с выбранным героем, его талантами и закрытыми навыками профиля.
## В кооперативе забег начинает хост — для всего отряда (Net.start_run); клиент ждёт хоста.
func start_run() -> void:
	MetaProfile.set_last_hero(hero)
	if Net.is_online():
		if not Net.is_host():
			show_notice(tr("HUB_GATE_WAIT_HOST"))
			return
		_sync_choice()
		Net.set_hardcore(hardcore)
		Net.set_seals(seals)
		MetaProfile.set_last_seals(seals)
		Net.start_run()
		return
	MetaProfile.set_last_seals(seals)
	RunConfig.start_new_run(hero, hardcore, 0, MetaProfile.talents_for(hero), MetaProfile.locked_skills(), seals)
	get_tree().change_scene_to_file(ScenePaths.WORLD)


## Ранг печати id на следующий забег (окно печатей); у клиента кооператива печати ставит хост.
func set_seal(id: StringName, rank: int) -> void:
	var seal := DataRegistry.seal(id)
	if seal == null or (Net.is_online() and not Net.is_host()):
		return
	var clamped := clampi(rank, 0, seal.max_rank)
	if clamped > 0:
		seals[id] = clamped
	else:
		seals.erase(id)
	if Net.is_online():
		Net.set_seals(seals)


func on_quest_claimed(quest: QuestData) -> void:
	var text := tr("HUB_QUEST_DONE").format({"name": tr(quest.name_key), "reward": QuestWindow.reward_text(quest)})
	show_notice(text)
	_update_statues()
	refresh_status()


func refresh_status() -> void:
	souls_label.text = tr("HUB_SOULS").format({"souls": MetaProfile.souls})
	if Net.is_online():
		souls_label.text = tr("HUB_PARTY_SHORT").format({"count": Net.players().size(), "max": Net.MAX_PLAYERS}) \
				+ "  " + souls_label.text
	var board := _station(&"board")
	if board != null:
		board.attention = not MetaProfile.claimable_quests().is_empty()
	host_info.visible = Net.is_host()
	if host_info.visible:
		host_info.text = host_info_text()


## Хост: куда подключаться друзьям — адреса ПК (локальная сеть, Radmin VPN) и итог UPnP для Интернета.
func host_info_text() -> String:
	var mapper := Net.port_mapper
	var lines := PackedStringArray([tr("HUB_HOST_LOCAL").format({"addresses": ", ".join(Net.local_addresses()),
			"port": Net.host_port})])
	var args := {"address": mapper.external_address, "port": Net.host_port, "code": mapper.error_code}
	match mapper.status:
		PortMapper.Status.WORKING:
			lines.append(tr("NET_UPNP_WORKING"))
		PortMapper.Status.OPEN:
			lines.append(tr("NET_UPNP_OPEN").format(args))
		PortMapper.Status.NO_ROUTER:
			lines.append(tr("NET_UPNP_NO_ROUTER").format(args))
		PortMapper.Status.REFUSED:
			lines.append(tr("NET_UPNP_REFUSED").format(args))
		PortMapper.Status.SHARED_ADDRESS:
			lines.append(tr("NET_UPNP_SHARED").format(args))
	return "\n".join(lines)


func show_notice(text: String) -> void:
	notice_label.text = text
	notice_label.modulate.a = 1.0
	_notice_left = NOTICE_TIME


# --- Сборка зала ---

func _build_stations() -> void:
	var kinds := {
		&"altar": HubStation.Kind.ALTAR, &"board": HubStation.Kind.BOARD, &"chronicle": HubStation.Kind.CHRONICLE,
		&"gate": HubStation.Kind.GATE, &"war_table": HubStation.Kind.WAR_TABLE, &"exit": HubStation.Kind.EXIT,
	}
	for i in DataRegistry.HEROES.size():
		var statue := HubStation.new()
		statue.kind = HubStation.Kind.STATUE
		statue.hero = DataRegistry.HEROES[i]
		statue.id = StringName("statue_" + String(statue.hero.id))
		statue.position = SanctuaryMap.statue_point(i, DataRegistry.HEROES.size())
		_add_station(statue)
	for id: StringName in SanctuaryMap.STATIONS:
		var station := HubStation.new()
		station.kind = kinds[id]
		station.id = id
		station.position = SanctuaryMap.point(SanctuaryMap.STATIONS[id])
		_add_station(station)
	# Костёр — центр зала (шаг 11.12): большой, из атласа реквизита, герой его обходит.
	fire.position = SanctuaryMap.point(SanctuaryMap.FIRE)
	fire.add_child(HubProp.make(&"fire"))
	var fire_info := HubProp.info(&"fire")
	if not fire_info.is_empty():
		fire.add_child(HubStation.solid_body(Vector2(fire_info["body_half"][0], fire_info["body_half"][1])))


func _add_station(station: HubStation) -> void:
	stations.append(station)
	props.add_child(station)


## Тронный зал замка (17.10.2026): ковровая дорожка от статуй к южной стене (на слое пола), колонны и доспехи
## на стойках — облик зала, без станций; колонны и доспехи твёрдые, герой их обходит.
func _build_decor() -> void:
	var carpet := CastleCarpet.new()
	var top := SanctuaryMap.point(SanctuaryMap.CARPET_TOP)
	var bottom := SanctuaryMap.point(SanctuaryMap.CARPET_BOTTOM)
	carpet.position = (top + bottom) / 2.0
	carpet.rect = Rect2(-SanctuaryMap.CARPET_HALF_WIDTH, (top.y - bottom.y) / 2.0, SanctuaryMap.CARPET_HALF_WIDTH * 2.0,
			bottom.y - top.y)
	$Level.add_child(carpet)
	for entry: Array in SanctuaryMap.DECOR:
		var prop_id: StringName = entry[0]
		var holder := Node2D.new()
		holder.position = SanctuaryMap.point(entry[1])
		holder.add_child(HubProp.make(prop_id))
		var prop_info := HubProp.info(prop_id)
		if not prop_info.is_empty():
			holder.add_child(HubStation.solid_body(Vector2(prop_info["body_half"][0], prop_info["body_half"][1])))
		props.add_child(holder)


## Дешёвый свет (DESIGN 4): тёмный зал (CanvasModulate) и несколько точечных огней — костёр (главный, колышется),
## огненный портал, алтарь, свечи стола, летописи и фонарь доски; с 17.10.2026 — и факелы, нарисованные на стенах
## замка (свет атласа, LevelLights, как на уровнях забега).
func _build_lights(level: LevelData) -> void:
	var lights := [
		[fire.position + Vector2(0, -14), FIRE_LIGHT, FIRE_ENERGY, 5.0],
		[_station(&"gate").position + Vector2(0, -40), PORTAL_LIGHT, 1.0, 3.0],
		[_station(&"altar").position, HubStation.SOUL, 0.8, 1.6],
		[_station(&"war_table").position + Vector2(0, -16), FIRE_LIGHT, 0.55, 1.8],
		[_station(&"board").position + Vector2(30, -30), FIRE_LIGHT, 0.5, 1.4],
		[_station(&"chronicle").position + Vector2(-12, -30), FIRE_LIGHT, 0.5, 1.4],
	]
	var wall_lights := LevelLights.collect(level)
	for i in wall_lights.size():
		var c := wall_lights.colors[i]
		lights.append([wall_lights.positions[i], Color(c.r, c.g, c.b).clamp(), 0.6,
				clampf(wall_lights.radii[i] / 64.0, 0.8, 2.0)])
	var texture := GradientTexture2D.new()
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	# Спад резче линейного: яркое пятно у огня и тьма у стен, а не ровная заливка зала.
	texture.gradient = Gradient.new()
	texture.gradient.set_color(0, Color.WHITE)
	texture.gradient.set_color(1, Color(1, 1, 1, 0))
	texture.gradient.add_point(0.35, Color(1, 1, 1, 0.55))
	texture.gradient.add_point(0.7, Color(1, 1, 1, 0.12))
	for item: Array in lights:
		var light := PointLight2D.new()
		light.texture = texture
		light.position = item[0]
		light.color = item[1]
		light.energy = item[2]
		light.texture_scale = item[3]
		props.add_child(light)
		if _fire_light == null:
			_fire_light = light
	var ambient := CanvasModulate.new()
	ambient.color = AMBIENT
	add_child(ambient)


# --- Состояние станций и подсказки ---

func _update_statues() -> void:
	for station in stations:
		if station.kind == HubStation.Kind.STATUE:
			station.locked = not MetaProfile.is_unlocked(station.hero.id)
			station.selected = station.hero == hero


func _station(id: StringName) -> HubStation:
	for station in stations:
		if station.id == id:
			return station
	return null


func _nearest_station() -> HubStation:
	var best: HubStation = null
	var best_score := 1.0
	for station in stations:
		# Доля радиуса станции: у крупного стола и портала «нажать E» дальше, чем у статуи.
		var score := station.position.distance_to(_hero_node.position) / station.reach()
		if score <= best_score:
			best = station
			best_score = score
	return best


func _prompt_text(station: HubStation) -> String:
	if station.kind == HubStation.Kind.STATUE:
		var name_text := tr(station.hero.name_key)
		if station.locked:
			return _locked_text(station.hero.id)
		if station.hero == hero:
			return tr("HUB_STATUE_CHOSEN").format({"name": name_text})
		return tr("HUB_STATUE_CHOOSE").format({"name": name_text})
	return tr("HUB_PROMPT").format({"action": tr("HUB_STATION_" + String(station.id).to_upper())})


func _locked_text(id: StringName) -> String:
	var quest := DataRegistry.quest_for_unlock(id)
	return tr("HUB_LOCKED").format({"quest": tr(quest.name_key) if quest != null else "?"})


func _show_hero_card(p_hero: HeroData) -> void:
	for child in hero_card.get_children():
		hero_card.remove_child(child)
		child.queue_free()
	hero_card.visible = p_hero != null
	if p_hero != null:
		hero_card.add_child(HubWindow.hero_card(p_hero))


func _open_window() -> HubWindow:
	for window: HubWindow in _windows.values():
		if window.visible:
			return window
	return null


func _on_window_closed() -> void:
	_near = null  # подсказка и карточка героя вернутся на следующем кадре
	_sync_choice()  # у Алтаря могли смениться таланты
	refresh_status()


# --- Кооператив ---

## Герой участника peer_id в зале: появился — встаёт на место, дальше догоняет присланную позицию.
func _on_hub_state(peer_id: int, hero_id: StringName, pos: Vector2) -> void:
	var other: HubHero = _remote.get(peer_id)
	var member := DataRegistry.hero(hero_id)
	if other == null or not is_instance_valid(other):
		other = HERO_SCENE.instantiate()
		other.remote = true
		other.hero = member
		other.position = pos
		other.tag = tr("HUB_PLAYER_TAG").format({"n": Net.players().find(peer_id) + 1})
		props.add_child(other)
		_remote[peer_id] = other
	elif other.hero != member:
		other.set_hero(member)
	other.target = pos


## Ушедшие из отряда пропадают из зала.
func _on_roster_changed() -> void:
	for peer: int in _remote.keys():
		if not Net.roster.has(peer):
			_drop_remote(peer)
	if Net.is_online() and not Net.is_host() and seals != Net.seals:  # хост сменил печати — окна показывают новые
		seals = Net.seals.duplicate()
		for id: StringName in [&"gate", &"seals"]:
			var window: HubWindow = _windows.get(id)
			if window != null:
				window.refresh()
	refresh_status()


func _on_session_ended(reason: String) -> void:
	for peer: int in _remote.keys():
		_drop_remote(peer)
	refresh_status()
	if reason != "":
		show_notice(tr(reason))


func _drop_remote(peer: int) -> void:
	var other: HubHero = _remote.get(peer)
	_remote.erase(peer)
	if other != null and is_instance_valid(other):
		other.queue_free()


## Для проверок: герои других участников в зале.
func remote_heroes() -> Dictionary:
	return _remote


## При входе: награда за забег, сообщение профиля, награды на доске.
func _greet() -> void:
	var lines := PackedStringArray()
	if RunConfig.last_reward > 0:
		lines.append(tr("HUB_REWARD").format({"souls": RunConfig.last_reward}))
	RunConfig.last_reward = 0
	var notice := MetaProfile.take_notice()
	if not notice.is_empty():
		lines.append(tr(notice))
	if not MetaProfile.claimable_quests().is_empty():
		lines.append(tr("HUB_QUEST_READY"))
	if not lines.is_empty():
		show_notice("\n".join(lines))
