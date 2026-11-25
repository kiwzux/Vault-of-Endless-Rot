extends CanvasLayer
## Игровой интерфейс в духе Halls of Torment (шаг 11.7): две боковые панели на камне с решёткой, игровое поле —
## между ними. Слева — медальон уровня, полоса опыта, числа опыта, здоровья и маны (VitalsPanel), пояс зелий и
## сфера здоровья; справа — кнопка меню, навыки 2 × 3 с рунами (SkillGrid), пассивки, миникарта, таблички золота,
## убийств и таймера (RunCounters). Над полем — отметка ХК, полоса босса, баннеры событий, испытание; снизу — баффы.
## Экипировка, резонансы и лист характеристик — в меню (кнопка «Меню», Esc, I).
## Ориентиры: миникарта и стрелки у края поля на босса, Ключ и открытый портал (стрелки не заходят под панели).
## Экран конца забега (победа/поражение) — со статистикой забега (RunStatsView); в кооперативе в Убежище всех
## уводит хост, сессия остаётся (Net.return_to_hub).

const BANNER_TIME := 2.5
const BUFF_KEYS := {&"fountain": "BUFF_FOUNTAIN"}

var _player: Player
var _boss: Enemy
## Фаза босса, о которой уже был баннер (шаг 12): фаза считается из здоровья у всех участников.
var _boss_phase := 0
var _banner_left := 0.0
var _generation_failed := false
var _obelisks := 0
var _grail := false
## Идущее испытание (CR-16): какое и сколько секунд осталось — таймер под баннером.
var _challenge_kind: StringName = &""
var _challenge_left := 0.0
## Подсказка отложенного выбора улучшения (кооператив) и время для её пульсации.
var _level_hint: Label
var _hint_time := 0.0

@onready var hardcore_label: Label = %HardcoreLabel
@onready var banner: Label = %Banner
@onready var challenge_label: Label = %ChallengeLabel
@onready var health_orb: ResourceOrb = %HealthOrb
@onready var vitals: VitalsPanel = %Vitals
@onready var buffs_label: Label = %BuffsLabel
@onready var relic_label: Label = %RelicLabel
@onready var boss_box: Control = %BossBox
@onready var boss_name: Label = %BossName
@onready var boss_bar: ProgressBar = %BossBar
@onready var end_panel: Control = %EndPanel
@onready var end_title: Label = %EndTitle
@onready var end_details: Label = %EndDetails
@onready var minimap: Minimap = %Minimap
@onready var markers: OffscreenMarkers = %Markers
@onready var skills: SkillGrid = %Skills
@onready var left_panel: Control = %LeftPanel
@onready var right_panel: Control = %RightPanel
@onready var belt: PotionBelt = %Belt
@onready var counters: RunCounters = %Counters
@onready var passives: PassivesPanel = %Passives
@onready var allies: AlliesPanel = %Allies

## Свой герой был жив в прошлом кадре — чтобы заметить гибель (баннер «Последнего вздоха»).
var _was_alive := true
## Статистика забега на экране конца забега (как в Megabonk); сводка приходит синхронизацией героя.
var _run_stats: RunStatsView


func _ready() -> void:
	var world := World.of(self)
	_level_hint = Label.new()  # кооператив: «R — выбрать улучшение» (отложенный выбор, LevelUpPanel)
	_level_hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_level_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_hint.add_theme_font_size_override("font_size", 11)
	_level_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_level_hint.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	_level_hint.add_theme_constant_override("outline_size", 4)
	_level_hint.hide()
	$Center.add_child(_level_hint)
	$Center.move_child(_level_hint, 0)
	minimap.world = world
	markers.world = world
	allies.world = world
	markers.obstacles.assign([left_panel, right_panel, allies])
	# Сложность забега над полем: «Хардкор», Скверна печатей (шаг 12.3) или обе через точку.
	var difficulty := PackedStringArray()
	if RunConfig.hardcore:
		difficulty.append(tr("HARDCORE"))
	if RunConfig.heat() > 0:
		difficulty.append(tr("HUD_HEAT").format({"heat": RunConfig.heat()}))
	hardcore_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hardcore_label.text = " · ".join(difficulty)
	hardcore_label.visible = not difficulty.is_empty()
	banner.hide()
	boss_box.hide()
	end_panel.hide()
	_run_stats = RunStatsView.new()
	end_details.add_sibling(_run_stats)
	relic_label.hide()
	Events.level_loaded.connect(_on_level_loaded)
	# ТЗ 4.4.4: сбой генерации — уведомить игрока. Сигнал приходит до level_loaded, баннер — после.
	Events.level_generation_failed.connect(func(_reason: String) -> void: _generation_failed = true)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.boss_defeated.connect(func() -> void:
		if not RunPlan.is_final(GameState.level_index):
			_show_banner(tr("BANNER_BOSS_DEFEATED")))
	Events.portal_activated.connect(func() -> void: _show_banner(tr("BANNER_PORTAL_OPEN")))
	Events.run_choice_offered.connect(func() -> void: _show_banner(tr("BANNER_RUN_CHOICE")))
	Events.statue_awakened.connect(func() -> void: _show_banner(tr("BANNER_STATUE")))
	Events.obelisk_visited.connect(_on_obelisk_visited)
	Events.grail_found.connect(func(_peer_id: int) -> void:
		_grail = true
		_update_relics()
		_show_banner(tr("BANNER_GRAIL")))
	Events.item_picked.connect(func(peer_id: int, item: Dictionary) -> void:
		if peer_id == multiplayer.get_unique_id():
			_show_banner(tr("BANNER_ITEM").format({"name": ItemRoller.display_name(item)})))
	Events.run_ended.connect(_on_run_ended)
	Events.second_wind.connect(func(peer_id: int) -> void:
		if peer_id == multiplayer.get_unique_id():
			_show_banner(tr("BANNER_SECOND_WIND")))
	Events.chest_opened.connect(func(peer_id: int, price: int) -> void:
		if peer_id == multiplayer.get_unique_id():
			_show_banner(tr("BANNER_CHEST_OPENED").format({"price": price})))
	Events.challenge_started.connect(func(kind: StringName, duration: float) -> void:
		_challenge_kind = kind
		_challenge_left = duration
		_show_banner(tr(ChallengeAltar.banner_key(kind, true))))
	Events.challenge_finished.connect(func(kind: StringName, success: bool) -> void:
		_challenge_left = 0.0
		challenge_label.hide()
		_show_banner(tr(ChallengeAltar.result_key(kind, success))))
	Events.player_revived.connect(_on_player_revived)
	Events.interactable_used.connect(_on_interactable_used)
	skills.evolved.connect(func(skill: SkillData, stage: int) -> void:  # шаг 11.18: эволюцию видно — баннер и вспышка
		var transformed := skill.is_evolution and stage == DataRegistry.UPGRADE_RULES.evolution_transform_stage
		_show_banner(tr("BANNER_EVOLUTION" if transformed else "BANNER_EVOLUTION_STAGE").format(
				{"name": tr(skill.name_key), "stage": UpgradePool.stage_name(stage)})))
	%MenuButton.pressed.connect(func() -> void: World.of(self).leave_run())
	%OpenMenu.pressed.connect(func() -> void:
		var menu: PauseMenu = World.of(self).get_node(^"PauseMenu")
		if menu.can_open():
			menu.open())


## Шаг 8: святилище, алтарь проклятий и сделка с бездной, стража пленника, освобождение, мимик.
## Разбитые бочки и урны баннера не дают — их много.
func _on_interactable_used(type_id: StringName, _peer_id: int, outcome: StringName) -> void:
	if type_id == &"golden_bucket":  # пасхалка 1-го уровня (17.10.2026) — разбивается касанием, но баннер нужен
		_show_banner(tr("BANNER_GOLDEN_BUCKET"))
		return
	if outcome == &"broken":
		return
	var name_key := "ENEMY_MIMIC"
	var point := DataRegistry.interactable(type_id)
	var goods := DataRegistry.goods(type_id)
	if point != null:
		name_key = point.name_key
	elif goods != null:
		name_key = goods.name_key
	_show_banner(tr("BANNER_POINT_" + String(outcome).to_upper()).format({"name": tr(name_key)}))


func _process(delta: float) -> void:
	var seconds := ceili(GameState.level_time_left)
	# В логове финального босса таймера нет: босс ждёт сразу.
	counters.time_text = "" if RunPlan.is_final(GameState.level_index) else "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
	_update_level_hint(delta)

	if _player == null or not is_instance_valid(_player):
		_player = _find_local_player()
		skills.player = _player
		vitals.player = _player
		belt.player = _player
		counters.player = _player
		passives.player = _player
	if _player != null:
		health_orb.max_value = _player.max_health
		health_orb.value = _player.health
		var buffs := PackedStringArray()
		for id: StringName in _player.buffs:
			buffs.append("%s %d" % [tr(_buff_key(id)), ceili(_player.buffs[id]["time"])])
		buffs_label.text = "  ".join(buffs)
		if _was_alive and not _player.alive and not allies.allies().is_empty():
			# Кооператив: подсказать, что делать призраку (в одиночной игре сразу экран поражения).
			_show_banner(tr("BANNER_FALLEN_HARDCORE" if RunConfig.hardcore else "BANNER_FALLEN_COOP"))
		_was_alive = _player.alive

	if end_panel.visible:
		_run_stats.refresh(_player, World.of(self).get_players())

	if boss_box.visible:
		if _boss == null or not is_instance_valid(_boss) or _boss.dead:
			boss_box.hide()
		else:
			boss_bar.value = 100.0 * _boss.health / _boss.max_health
			if _boss.phase > _boss_phase:
				_boss_phase = _boss.phase
				_show_banner(tr("BANNER_BOSS_PHASE").format({"name": tr(_boss.data.name_key), "phase": _boss_phase + 1}))

	challenge_label.visible = _challenge_left > 0.0
	if _challenge_left > 0.0:
		_challenge_left = maxf(_challenge_left - delta, 0.0)
		challenge_label.text = tr("HUD_CHALLENGE").format({
			"name": tr(ChallengeAltar.name_key(_challenge_kind)), "time": ceili(_challenge_left),
		})

	if _banner_left > 0.0:
		_banner_left -= delta
		banner.modulate.a = clampf(_banner_left, 0.0, 1.0)
		banner.visible = _banner_left > 0.0


func _on_level_loaded(_level: LevelData) -> void:
	var index := GameState.level_index
	if RunPlan.stage(index) == 0:  # новый круг — обелиски считаются заново
		_obelisks = 0
		_grail = false
		_update_relics()
	if _generation_failed:
		_generation_failed = false
		_show_banner(tr("BANNER_GENERATION_FAILED"))
		return
	var text := tr("BANNER_FINAL_LAIR") if RunPlan.is_final(index) else tr("BANNER_LEVEL").format({
		"biome": tr(RunPlan.biome_key(index)), "stage": RunPlan.stage(index) + 1,
		"total": RunPlan.levels_per_cycle() - 1,
	})
	if RunPlan.cycle(index) > 0:
		text = tr("BANNER_CYCLE").format({"cycle": RunPlan.cycle(index) + 1}) + " · " + text
	_show_banner(text)


func _on_boss_spawned(boss: Node) -> void:
	_boss = boss as Enemy
	if _boss == null:
		return
	boss_name.text = tr(_boss.data.name_key)
	boss_bar.value = 100.0
	_boss_phase = _boss.phase
	_mark_phases(_boss.data.phase_thresholds)
	boss_box.show()
	if not RunPlan.is_final(GameState.level_index):
		_show_banner(tr("BANNER_BOSS_AWAKENED"))


## Пороги фаз босса — тонкие отметки на полосе здоровья.
func _mark_phases(thresholds: PackedFloat32Array) -> void:
	for child in boss_bar.get_children():
		if child.is_in_group(&"phase_mark"):
			child.queue_free()
	for threshold in thresholds:
		var mark := ColorRect.new()
		mark.add_to_group(&"phase_mark")
		mark.color = Color(1.0, 0.9, 0.6, 0.85)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.anchor_left = threshold
		mark.anchor_right = threshold
		mark.anchor_bottom = 1.0
		mark.offset_left = -0.5
		mark.offset_right = 0.5
		boss_bar.add_child(mark)


## «Последний вздох»: своего героя подняли — или союзник снова в бою.
func _on_player_revived(peer_id: int, _by_peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_show_banner(tr("BANNER_REVIVED_YOU"))
		return
	var ally := World.of(self).find_player(peer_id)
	if ally != null:
		_show_banner(tr("BANNER_ALLY_REVIVED").format({"hero": tr(ally.hero.name_key)}))


func _on_obelisk_visited(count: int, needed: int) -> void:
	_obelisks = count
	_update_relics()
	_show_banner(tr("BANNER_OBELISK").format({"count": count, "needed": needed}))


func _update_relics() -> void:
	relic_label.visible = _obelisks > 0 or _grail
	relic_label.text = tr("HUD_OBELISKS").format({"count": _obelisks, "needed": LevelFlow.GRAIL_OBELISKS})
	if _grail:
		relic_label.text += " · " + tr("HUD_GRAIL")


func _on_run_ended(victory: bool) -> void:
	var reached := _player.level if _player != null else 1
	var index := GameState.level_index
	end_title.text = "VICTORY_TITLE" if victory else "DEFEAT_TITLE"  # ключ — Label переведёт сам
	end_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35) if victory else Color(0.85, 0.2, 0.15))
	if victory:
		end_details.text = tr("VICTORY_DETAILS").format({"level": reached, "cycles": RunPlan.cycle(index) + 1})
	else:
		end_details.text = tr("DEFEAT_DETAILS").format({"level": reached, "depth": index + 1})
	end_details.text += "\n" + tr("RUN_SOULS").format({"souls": World.of(self).souls_earned()})
	# Кооператив: в Убежище всех уводит хост (сессия остаётся); клиент ждёт его, а не покидает отряд.
	var waiting := Net.is_online() and not Net.is_host()
	%MenuButton.disabled = waiting
	%MenuButton.text = "END_WAIT_HOST" if waiting else ("RETURN_TO_HUB_ALL" if Net.is_online() else "RETURN_TO_HUB")
	end_panel.show()
	_run_stats.refresh(_player, World.of(self).get_players())
	%MenuButton.grab_focus()


## Кооператив: есть повышения, ждущие выбора, а окно закрыто — пульсирующая подсказка «R — выбрать».
func _update_level_hint(delta: float) -> void:
	var panel := World.of(self).get_node_or_null(^"LevelUpPanel")
	var waiting: bool = panel != null and panel.deferred() and panel.has_offer() and not panel.visible
	_level_hint.visible = waiting
	if not waiting:
		return
	_hint_time += delta
	var count := _player.pending_choices if _player != null and is_instance_valid(_player) else 1
	_level_hint.text = tr("LEVEL_UP_READY_MANY").format({"count": count}) if count > 1 else tr("LEVEL_UP_READY")
	_level_hint.modulate.a = 0.7 + 0.3 * sin(_hint_time * 5.0)


func _show_banner(text: String) -> void:
	banner.text = text
	banner.modulate.a = 1.0
	banner.show()
	_banner_left = BANNER_TIME


## Название баффа: фонтан или эликсир алхимика (CR-14).
func _buff_key(id: StringName) -> String:
	if BUFF_KEYS.has(id):
		return BUFF_KEYS[id]
	var goods := DataRegistry.goods(id)
	return goods.name_key if goods != null else String(id)


func _find_local_player() -> Player:
	for node in get_tree().get_nodes_in_group(Player.GROUP):
		if node is Player and node.is_multiplayer_authority():
			return node
	return null
