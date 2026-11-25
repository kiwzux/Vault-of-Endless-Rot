class_name UpgradeSystem
extends Node
## Опыт, повышение уровня и карты улучшений (ФТ-10).
## Хост начисляет опыт, раздаёт каждому игроку его собственные 3 карты и проверяет выбор (ФТ-16):
## принимается только карта из последнего предложения этому peer id. Редкость карты бросает хост
## при раздаче и хранит в предложении: клиент не может выдать обычную карту за легендарную.
## Переброс карт за золото (как в Vampire Survivors): хост списывает цену и раздаёт новые 3 карты;
## каждый следующий переброс дороже (EconomyTable.reroll_cost).
## Изгнание (Vampire Survivors): карта из предложения убирается из выпадения до конца забега, на её место
## встаёт другая; зарядов на забег — UpgradeRules.banishes. Антиповтор: хост помнит прошлые предложения
## игрока, и их карты выпадают реже (UpgradeRules.repeat_weights).
## Шаг 4: карты рун (руна забега в навык героя, UpgradePool.add_rune_cards) с уровня героя
## UpgradeRules.rune_unlock_level; выбор руны хост проверяет так же, как карту (Player.add_rune).
## Навыки сродства класса выпадают чаще (HeroData.affinity_tags).
## Ступени эволюции навыка (каждые 5 уровней, UpgradePool.evolution_card): выбор ступени хост проверяет
## в Player.add_evolution_stage, превращение в облик — карта облика (Player.apply_upgrade).
##
## Точки подключения сети (game/net):
##  - Events.level_up_offered(peer_id, cards) на хосте → доставить карты игроку peer_id;
##  - choice_submitted(card_id) на клиенте → RPC хосту → apply_choice(sender_id, card_id);
##  - reroll_submitted на клиенте → RPC хосту → apply_reroll(sender_id);
##  - banish_submitted(card_id) на клиенте → RPC хосту → apply_banish(sender_id, card_id).

signal choice_submitted(card_id: StringName)
signal reroll_submitted
signal banish_submitted(card_id: StringName)

var _world: World
var _rng := RandomNumberGenerator.new()
var _drop_rng := RandomNumberGenerator.new()
var _offers := {}  # peer_id -> Array карт {"id", "from", "level", "rarity", "evolution"}; у руны ещё "rune", "skill";
## у эволюции ещё "stage" (у карты ступени и "skill")
var _pending := {}  # peer_id -> число невыбранных повышений
var _history := {}  # peer_id -> Array прошлых предложений (id карт), свежее — первым
## Хост: кристаллы опыта на земле, старые — первыми (предел BalanceConfig.max_xp_gems).
var _gems: Array[Pickup] = []


func _ready() -> void:
	_world = World.of(self)
	_rng.seed = hash([RunConfig.run_seed, "upgrades"])
	_drop_rng.seed = hash([RunConfig.run_seed, "soul_magnet"])
	Events.player_spawned.connect(_on_player_spawned)


func _on_player_spawned(player: Player) -> void:
	if not multiplayer.is_server():
		return
	var weapon := DataRegistry.upgrade(player.hero.starting_weapon)
	if weapon != null and player.get_upgrade_level(weapon.id) == 0:
		# Талант «Мастер …» (CR-04): стартовое оружие сразу на несколько уровней выше.
		player.apply_upgrade(weapon, 1 + int(player.talent_value(TalentData.WEAPON_MASTERY)))


## Хост: опыт за подобранный кристалл. boosted — доля BalanceConfig.xp_gain_mult (−35 %) и бонус «Обучаемости»;
## дробная часть копится. Без boosted — ровно amount (опыт «до следующего уровня»).
func grant_xp(player: Player, amount: int, boosted: bool = true) -> void:
	if not multiplayer.is_server() or amount <= 0:
		return
	var peer := player.peer_id()
	var gained := amount
	if boosted:
		player.xp_carry += amount * DataRegistry.BALANCE.xp_gain_mult * (1.0 + player.stat(Player.STAT_XP_GAIN))
		gained = floori(player.xp_carry)
		player.xp_carry -= gained
	player.xp += gained
	Events.xp_collected.emit(peer, gained)
	while player.xp >= Player.xp_to_next(player.level):
		player.xp -= Player.xp_to_next(player.level)
		player.level += 1
		_pending[peer] = _pending.get(peer, 0) + 1
	player.pending_choices = _pending.get(peer, 0)
	if _pending.get(peer, 0) > 0 and not _offers.has(peer):
		_offer(player)


## Хост: кристалл опыта value в точке pos (шаг 5). Кристаллов на земле не больше BalanceConfig.max_xp_gems:
## сверх предела опыт добавляется к самому старому кристаллу, который ещё никто не притягивает, — как
## красный кристалл в Vampire Survivors: узлов и посылок спавнера не прибавляется, опыт не теряется.
func drop_xp(pos: Vector2, value: int) -> void:
	if not multiplayer.is_server() or value <= 0:
		return
	if _gems.size() >= DataRegistry.BALANCE.max_xp_gems:
		for gem in _gems:
			if gem.absorb(value):
				return
	var gem := _world.spawn_pickup({"kind": Pickup.Kind.XP, "pos": pos, "value": value})
	if gem != null:
		_gems.append(gem)
		gem.tree_exiting.connect(func() -> void: _gems.erase(gem))


## Кристаллов опыта на земле (для проверок).
func gem_count() -> int:
	return _gems.size()


## Хост: Магнит душ с убитого врага — у элиты шанс выше (UpgradeRules).
func maybe_drop_magnet(pos: Vector2, elite: bool) -> void:
	var rules := DataRegistry.UPGRADE_RULES
	if _drop_rng.randf() < (rules.magnet_elite_chance if elite else rules.magnet_enemy_chance):
		_world.spawn_pickup({"kind": Pickup.Kind.MAGNET, "pos": pos})


## id карт последнего предложения игроку.
func current_offer(peer_id: int) -> Array:
	return _offers.get(peer_id, []).map(func(card: Dictionary) -> StringName: return card["id"])


## Вызывает интерфейс левел-апа своего игрока.
func submit_choice(card_id: StringName) -> void:
	if multiplayer.is_server():
		apply_choice(multiplayer.get_unique_id(), card_id)
	else:
		choice_submitted.emit(card_id)


func submit_reroll() -> void:
	if multiplayer.is_server():
		apply_reroll(multiplayer.get_unique_id())
	else:
		reroll_submitted.emit()


func submit_banish(card_id: StringName) -> void:
	if multiplayer.is_server():
		apply_banish(multiplayer.get_unique_id(), card_id)
	else:
		banish_submitted.emit(card_id)


## Хост: применить выбор. false — выбор отклонён и состояние не изменилось (ФТ-16).
## Карта руны вставляет руну в навык (Player.add_rune проверяет навык, руну и свободное гнездо).
func apply_choice(peer_id: int, card_id: StringName) -> bool:
	if not multiplayer.is_server():
		return false
	var card := {}
	for offered: Dictionary in _offers.get(peer_id, []):
		if offered["id"] == card_id:
			card = offered
	var player := _world.find_player(peer_id)
	if card.is_empty() or player == null:
		return false
	var socket := UpgradePool.parse_rune_card(card_id)
	var evolving := UpgradePool.parse_evolution_card(card_id)
	if not socket.is_empty():
		if not player.add_rune(socket[1], socket[0]):
			return false
	elif evolving != &"":
		if not player.add_evolution_stage(evolving):
			return false
	else:
		var upgrade := DataRegistry.upgrade(card_id)
		if upgrade == null:
			return false
		player.apply_upgrade(upgrade, UpgradePool.levels_for(card["rarity"]))
	_offers.erase(peer_id)
	_pending[peer_id] -= 1
	player.pending_choices = _pending[peer_id]
	if _pending[peer_id] > 0:
		_offer(player)
	return true


## Хост: перебросить карты за золото. false — предложения нет или золота не хватает (ФТ-16).
func apply_reroll(peer_id: int) -> bool:
	if not multiplayer.is_server() or not _offers.has(peer_id):
		return false
	var player := _world.find_player(peer_id)
	if player == null or not player.spend_gold(_world.economy.reroll_cost(player)):
		return false
	player.rerolls += 1
	_offer(player)
	return true


## Хост: изгнать карту из предложения до конца забега; на её место встаёт другая.
## У карты руны изгоняется руна целиком (UpgradePool.banish_key).
## false — карты нет в предложении, её нельзя изгнать или заряды кончились (ФТ-16).
func apply_banish(peer_id: int, card_id: StringName) -> bool:
	if not multiplayer.is_server():
		return false
	var cards: Array = _offers.get(peer_id, [])
	var index := cards.find_custom(func(card: Dictionary) -> bool: return card["id"] == card_id)
	var player := _world.find_player(peer_id)
	if index < 0 or player == null or player.banishes_left <= 0 \
			or not UpgradePool.can_banish(card_id, cards[index]["evolution"]):
		return false
	player.banishes_left -= 1
	player.banished.append(UpgradePool.banish_key(card_id))
	var blocked := _blocked(player)
	blocked.append_array(current_offer(peer_id))
	var replacement := UpgradePool.roll(player.upgrade_levels, _rng, _repeat_weights(peer_id), blocked, 1,
			_affinity(player), player.evolution_stages)
	cards = cards.duplicate()
	cards[index] = _make_card(player, replacement[0])
	_offers[peer_id] = cards
	Events.level_up_offered.emit(peer_id, cards)
	return true


## Три карты с редкостью; level — уровень после взятия, from — текущий. С уровня rune_unlock_level
## одна из карт может быть руной, а запасные карты руны заменяют всегда (UpgradePool.add_rune_cards).
func _offer(player: Player) -> void:
	var peer := player.peer_id()
	var cards: Array = []
	var repeat := _repeat_weights(peer)
	var ids := UpgradePool.roll(player.upgrade_levels, _rng, repeat, _blocked(player), UpgradePool.CARD_COUNT,
			_affinity(player), player.evolution_stages)
	if player.level >= DataRegistry.UPGRADE_RULES.rune_unlock_level:
		UpgradePool.add_rune_cards(ids, player.upgrade_levels, player.runes, player.stat(Player.STAT_CRIT), _rng,
				repeat, player.banished)
	for id in ids:
		cards.append(_make_card(player, id))
	_offers[peer] = cards
	var history: Array = _history.get(peer, [])
	history.push_front(ids)
	history.resize(mini(history.size(), DataRegistry.UPGRADE_RULES.repeat_weights.size()))
	_history[peer] = history
	Events.level_up_offered.emit(peer, cards)


## Карты, которых не может быть в предложении: изгнанные и ещё не открытые в профиле игрока (шаг 10).
## Закрытый навык не выпадает, поэтому и его эволюция недостижима.
func _blocked(player: Player) -> Array:
	var blocked: Array = player.banished.duplicate()
	blocked.append_array(player.locked_skills)
	return blocked


## Маска тегов сродства класса героя.
func _affinity(player: Player) -> int:
	return DataRegistry.tag_mask(player.hero.affinity_tags)


## Карта руны: from — сколько рун забега уже в навыке, level — сколько станет; редкость — у самой руны.
## Карта ступени эволюции («evo:<навык>»): skill — навык, from и level — ступень до и после.
## У карт эволюции (ступень и превращение) stage — какая ступень будет взята.
func _make_card(player: Player, id: StringName) -> Dictionary:
	var socket := UpgradePool.parse_rune_card(id)
	if not socket.is_empty():
		var rune := DataRegistry.skill_modifier(socket[0])
		var filled: int = player.runes.get(socket[1], []).size()
		return {
			"id": id, "rune": socket[0], "skill": socket[1], "from": filled, "level": filled + 1,
			"rarity": rune.rarity if rune != null else 0, "evolution": false,
		}
	var evolving := UpgradePool.parse_evolution_card(id)
	if evolving != &"":
		var stage := player.evolution_stage(evolving)
		return {
			"id": id, "skill": evolving, "from": stage, "level": stage + 1, "stage": stage + 1,
			"rarity": UpgradePool.Rarity.COMMON, "evolution": true,
		}
	var upgrade := DataRegistry.upgrade(id)
	var from := player.get_upgrade_level(id)
	var evolution := upgrade is SkillData and (upgrade as SkillData).is_evolution and from == 0
	var rarity := UpgradePool.Rarity.COMMON
	var to := from
	if evolution:  # эволюция берёт уровень и ступень базового оружия; превращение — сама ступень
		var base := DataRegistry.evolution_base(id)
		to = player.get_upgrade_level(base.id) if base != null else 1
		var stage: int = player.evolution_stage(base.id) + 1 if base != null \
				else DataRegistry.UPGRADE_RULES.evolution_transform_stage
		return {"id": id, "from": from, "level": to, "rarity": rarity, "evolution": true, "stage": stage}
	rarity = UpgradePool.roll_rarity(upgrade, from, player.stat(Player.STAT_CRIT), _rng)
	to = from + UpgradePool.levels_for(rarity)
	if upgrade.max_level > 0:
		to = mini(to, upgrade.max_level)
	return {"id": id, "from": from, "level": to, "rarity": rarity, "evolution": false}


## Антиповтор: id → множитель веса по прошлым предложениям игрока (свежее — реже).
func _repeat_weights(peer_id: int) -> Dictionary:
	var weights := {}
	var rules := DataRegistry.UPGRADE_RULES
	var history: Array = _history.get(peer_id, [])
	for i in mini(history.size(), rules.repeat_weights.size()):
		for id: StringName in history[i]:
			weights[id] = minf(weights.get(id, 1.0), rules.repeat_weights[i])
	return weights
