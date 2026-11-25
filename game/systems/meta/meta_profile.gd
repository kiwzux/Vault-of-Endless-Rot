class_name MetaProfile
extends RefCounted
## Профиль игрока между забегами (CR-04): души и ранги талантов, последний выбранный герой,
## «Летопись» (счётчики, рекорды героев, бестиарий, трофеи), выполненные задания и открытия (шаг 10).
## Хранится локально в user://profile.json — у каждого участника кооператива свой; хосту ранги и
## закрытые навыки приходят вместе с героем и там проверяются данными (Net.sanitize_*).
## Общие таланты (TalentData.hero пусто) делят ранги на всех героев — ключ GLOBAL.
## Закрыто то, что открывает задание Доски (DataRegistry.quest_for_unlock), пока его награда не получена.
## Запись — SaveFile (шаг 10): временный файл, резервная копия, контрольная сумма. Данные из файла
## не доверяются: числа и ранги проверяются при загрузке. Персональных данных и адресов нет (ЛР2, 4.4.4).

const DEFAULT_PATH := "user://profile.json"
## Профиль до шага 10 (ConfigFile, версия 0): переносится один раз и остаётся рядом с пометкой .migrated.
const LEGACY_PATH := "user://profile.cfg"
const FORMAT := "vault-profile"
## 1 — души, таланты, забеги и победы; 2 — «Летопись», задания и открытия; 3 — финальный босс Владыка бездны
## вместо Владыки Гнили: его задание и запись лора переименованы (RENAMED_IDS).
const VERSION := 3
## id заданий и записей лора, переименованных в версии 3: старое → новое.
const RENAMED_IDS := {"rot_lord": "abyss_lord"}
const GLOBAL := "*"
## Счётчики «Летописи», где хранится лучший результат, а не сумма.
const BEST_COUNTERS: Array[StringName] = [&"depth", &"heat"]
## Предел списков из файла: файл мог править человек.
const MAX_ENTRIES := 512

## Проверки подменяют пути, чтобы не трогать настоящий профиль.
static var path := DEFAULT_PATH
static var legacy_path := LEGACY_PATH
static var souls := 0
static var last_hero: StringName = &""
## Печати Скверны последнего забега (шаг 12.3): Врата предлагают их снова. {id печати: ранг}.
static var last_seals := {}
## Ключ — id героя или GLOBAL → {id таланта: ранг}.
static var _ranks := {}
## «Летопись»: счётчик (QuestData.COUNTERS) → значение.
static var _counters := {}
## id героя → {"runs", "victories", "kills", "best_depth", "best_kills"}.
static var _hero_records := {}
## Бестиарий: id врага → сколько раз встречен.
static var _bestiary := {}
## Трофеи: id найденных легендарных предметов.
static var _trophies: Array[String] = []
## Записи лора, прочитанные хоть раз (шаг 8).
static var _lore: Array[String] = []
## Задания, награда за которые получена, и то, что открыто (награды и перенос старого профиля).
static var _claimed: Array[String] = []
static var _unlocked: Array[String] = []
static var _loaded := false
## Сообщение для хаба: профиль восстановлен из копии или не сохранился (ключ перевода).
static var _notice := ""


static func ensure_loaded() -> void:
	if not _loaded:
		load_profile()


static func load_profile() -> void:
	_loaded = true
	_apply({})
	var result := SaveFile.read(path, FORMAT)
	if result.source != SaveFile.Source.NONE:
		_apply(_migrate(result.data, result.version))
		if result.damaged:
			_notice = "PROFILE_RESTORED"
		if result.source != SaveFile.Source.MAIN or result.version != VERSION or result.damaged:
			save_profile()  # восстановленная или старая версия становится основным файлом, обрывки уходят
		return
	if result.damaged:
		_notice = "PROFILE_LOST"
		return
	if FileAccess.file_exists(legacy_path):
		_apply(_migrate(_read_legacy(legacy_path), 0))
		if save_profile() == OK:
			DirAccess.rename_absolute(legacy_path, legacy_path + ".migrated")


static func save_profile() -> Error:
	var err := SaveFile.write(path, FORMAT, VERSION, {
		"souls": souls,
		"last_hero": String(last_hero),
		"seals": _string_keys(last_seals),
		"talents": _ranks,
		"chronicle": {
			"counters": _counters,
			"heroes": _hero_records,
			"bestiary": _bestiary,
			"trophies": _trophies,
			"lore": _lore,
		},
		"quests": _claimed,
		"unlocked": _unlocked,
	})
	if err != OK:
		push_error("MetaProfile: профиль не сохранён (%s)" % error_string(err))
		_notice = "PROFILE_SAVE_FAILED"
	return err


## Сообщение для хаба (ключ перевода) — один раз; пусто — всё в порядке.
static func take_notice() -> String:
	var notice := _notice
	_notice = ""
	return notice


# --- Таланты ---

static func rank(talent: TalentData, hero: HeroData) -> int:
	ensure_loaded()
	var bucket: Dictionary = _ranks.get(_key(talent, hero), {})
	return clampi(int(bucket.get(String(talent.id), 0)), 0, talent.max_rank)


## Ранги талантов героя для забега: {id таланта: ранг}, только ненулевые.
static func talents_for(hero: HeroData) -> Dictionary:
	var result := {}
	for talent in DataRegistry.talents_for(hero):
		var r := rank(talent, hero)
		if r > 0:
			result[talent.id] = r
	return result


static func next_cost(talent: TalentData, hero: HeroData) -> int:
	return talent.cost(rank(talent, hero))


## Купить следующий ранг. false — предел или не хватает душ; профиль не меняется.
static func upgrade(talent: TalentData, hero: HeroData) -> bool:
	var price := next_cost(talent, hero)
	if price <= 0 or souls < price or not talent.fits(hero):
		return false
	souls -= price
	var key := _key(talent, hero)
	var bucket: Dictionary = _ranks.get(key, {})
	bucket[String(talent.id)] = rank(talent, hero) + 1
	_ranks[key] = bucket
	save_profile()
	return true


## Сброс талантов героя (только классовых; общие не трогаются). Возвращает, сколько душ вернулось.
static func respec(hero: HeroData) -> int:
	ensure_loaded()
	var refund := 0
	for talent in DataRegistry.talents_for(hero):
		if talent.is_global():
			continue
		for r in rank(talent, hero):
			refund += talent.cost(r)
	_ranks.erase(String(hero.id))
	refund = roundi(refund * DataRegistry.META_RULES.respec_refund)
	souls += refund
	save_profile()
	return refund


# --- Забег и «Летопись» ---

## Итог забега: души и запись в «Летопись» (summary — ChronicleRecorder.summary; пусто — только души).
static func grant(amount: int, victory: bool, summary: Dictionary = {}) -> void:
	ensure_loaded()
	souls += maxi(amount, 0)
	_add(&"runs", 1)
	if victory:
		_add(&"victories", 1)
	if not summary.is_empty():
		_record(summary, victory)
	save_profile()


static func set_last_hero(hero: HeroData) -> void:
	ensure_loaded()
	last_hero = hero.id
	save_profile()


## Печати, с которыми начат забег (шаг 12.3): в следующий раз Врата предложат их же.
static func set_last_seals(chosen: Dictionary) -> void:
	ensure_loaded()
	var clean := SealData.sanitize(chosen)
	if clean == last_seals:
		return
	last_seals = clean
	save_profile()


## Ключи-строки для JSON: StringName в файл не пишется.
static func _string_keys(source: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in source:
		result[str(key)] = source[key]
	return result


## Значение счётчика «Летописи»: trophies и bestiary — сколько разных предметов и врагов.
static func count(counter: StringName) -> int:
	ensure_loaded()
	match counter:
		&"trophies":
			return _trophies.size()
		&"bestiary":
			return _bestiary.size()
		&"lore":
			return _lore.size()
	return int(_counters.get(String(counter), 0))


## Рекорды героя: {"runs", "victories", "kills", "best_depth", "best_kills"} (нет записи — нули).
static func hero_record(hero_id: StringName) -> Dictionary:
	ensure_loaded()
	var record: Dictionary = _hero_records.get(String(hero_id), {})
	var result := {}
	for field in ["runs", "victories", "kills", "best_depth", "best_kills"]:
		result[field] = int(record.get(field, 0))
	return result


## Сколько раз встречен враг (0 — не встречен: в бестиарии его облик скрыт).
static func seen(enemy_id: StringName) -> int:
	ensure_loaded()
	return int(_bestiary.get(String(enemy_id), 0))


static func has_trophy(unique_id: StringName) -> bool:
	ensure_loaded()
	return String(unique_id) in _trophies


static func has_lore(lore_id: StringName) -> bool:
	ensure_loaded()
	return String(lore_id) in _lore


# --- Задания и открытия ---

static func quest_progress(quest: QuestData) -> int:
	return mini(count(quest.counter), quest.target)


static func quest_done(quest: QuestData) -> bool:
	return count(quest.counter) >= quest.target


static func quest_claimed(quest: QuestData) -> bool:
	ensure_loaded()
	return String(quest.id) in _claimed


## Задания, награду за которые можно забрать (метка на Доске заданий).
static func claimable_quests() -> Array[QuestData]:
	var result: Array[QuestData] = []
	for quest: QuestData in DataRegistry.QUESTS:
		if quest_done(quest) and not quest_claimed(quest):
			result.append(quest)
	return result


## Забрать награду: души и открытие. false — задание не выполнено или награда уже получена.
static func claim(quest: QuestData) -> bool:
	if not quest_done(quest) or quest_claimed(quest):
		return false
	_claimed.append(String(quest.id))
	souls += quest.reward_souls
	if quest.unlock != &"" and not String(quest.unlock) in _unlocked:
		_unlocked.append(String(quest.unlock))
	save_profile()
	return true


## Открыт ли класс или навык: закрыто только то, что открывает задание, пока награда не получена.
static func is_unlocked(id: StringName) -> bool:
	if DataRegistry.quest_for_unlock(id) == null:
		return true
	ensure_loaded()
	return String(id) in _unlocked


## Навыки, которых нет в пуле левел-апа этого игрока (UpgradeSystem: как изгнанные карты).
static func locked_skills() -> Array[StringName]:
	var result: Array[StringName] = []
	for upgrade: UpgradeData in DataRegistry.UPGRADES:
		if not is_unlocked(upgrade.id):
			result.append(upgrade.id)
	return result


static func _record(summary: Dictionary, victory: bool) -> void:
	var kills := _int(summary.get("kills"))
	var depth := _int(summary.get("depth"))
	_add(&"kills", kills)
	_add(&"levels", _int(summary.get("levels")))
	_add(&"depth", depth)
	_add(&"bosses", _int(summary.get("bosses")))
	_add(&"chests", _int(summary.get("chests")))
	_add(&"revives", _int(summary.get("revives")))
	_add(&"rescued", _int(summary.get("rescued")))
	_add(&"secrets", _int(summary.get("secrets")))
	for lore: Variant in summary.get("lore", []):
		if DataRegistry.lore(StringName(str(lore))) != null and not str(lore) in _lore:
			_lore.append(str(lore))
	if victory and summary.get("hardcore", false):
		_add(&"hardcore_victories", 1)
	if victory:
		_add(&"heat", _int(summary.get("heat")))  # лучшая Скверна победного забега (шаг 12.3)
	var hero_id := str(summary.get("hero", ""))
	if DataRegistry.hero(StringName(hero_id)) != null:
		var record := hero_record(StringName(hero_id))
		record.runs += 1
		record.victories += 1 if victory else 0
		record.kills += kills
		record.best_depth = maxi(record.best_depth, depth)
		record.best_kills = maxi(record.best_kills, kills)
		_hero_records[hero_id] = record
	for unique: Variant in summary.get("uniques", []):
		if DataRegistry.unique_item(StringName(str(unique))) != null and not str(unique) in _trophies:
			_trophies.append(str(unique))
	var met: Variant = summary.get("seen", {})
	if met is Dictionary:
		for enemy_id: Variant in met:
			if DataRegistry.enemy(StringName(str(enemy_id))) != null:
				_bestiary[str(enemy_id)] = seen(StringName(str(enemy_id))) + maxi(_int(met[enemy_id]), 0)


## Счётчик: сумма или лучший результат (BEST_COUNTERS).
static func _add(counter: StringName, value: int) -> void:
	var key := String(counter)
	var current := int(_counters.get(key, 0))
	_counters[key] = maxi(current, value) if counter in BEST_COUNTERS else current + maxi(value, 0)


# --- Файл ---

## Данные из файла → поля профиля. Всё приводится к типам и пределам: файл мог править человек.
static func _apply(data: Dictionary) -> void:
	souls = maxi(_int(data.get("souls")), 0)
	last_hero = StringName(str(data.get("last_hero", "")))
	last_seals = SealData.sanitize(data.get("seals", {}))  # нет поля (профиль до шага 12.3) — без печатей
	_ranks = {}
	var talents := _dict(data.get("talents"))
	for key: String in talents:
		var bucket := _dict(talents[key])
		var ranks := {}
		for id: String in bucket:
			var r := _int(bucket[id])
			if r > 0:
				ranks[id] = r
		if not ranks.is_empty():
			_ranks[key] = ranks
	var chronicle := _dict(data.get("chronicle"))
	_counters = {}
	var counters := _dict(chronicle.get("counters"))
	for counter in QuestData.COUNTERS:
		var value := maxi(_int(counters.get(String(counter))), 0)
		if value > 0:
			_counters[String(counter)] = value
	_hero_records = {}
	var heroes := _dict(chronicle.get("heroes"))
	for hero_id: String in heroes:
		if DataRegistry.hero(StringName(hero_id)) == null:
			continue
		var record := {}
		var raw := _dict(heroes[hero_id])
		for field in ["runs", "victories", "kills", "best_depth", "best_kills"]:
			record[field] = maxi(_int(raw.get(field)), 0)
		_hero_records[hero_id] = record
	_bestiary = {}
	var bestiary := _dict(chronicle.get("bestiary"))
	for enemy_id: String in bestiary:
		var met := _int(bestiary[enemy_id])
		if met > 0 and DataRegistry.enemy(StringName(enemy_id)) != null:
			_bestiary[enemy_id] = met
	_trophies = _ids(chronicle.get("trophies"), func(id: StringName) -> bool: return DataRegistry.unique_item(id) != null)
	_lore = _ids(chronicle.get("lore"), func(id: StringName) -> bool: return DataRegistry.lore(id) != null)
	_claimed = _ids(data.get("quests"), func(id: StringName) -> bool: return DataRegistry.quest(id) != null)
	_unlocked = _ids(data.get("unlocked"), func(id: StringName) -> bool:
		return DataRegistry.hero(id) != null or DataRegistry.upgrade(id) != null)


## Старые версии формата → текущая.
## 0 (ConfigFile) и 1: забеги и победы были отдельными полями — теперь это счётчики «Летописи».
## Открытий тогда не было: последний герой остаётся открытым, чтобы старый профиль не потерял класс,
## которым уже играли. Остальное открывается заданиями.
## 2: задание и лор Владыки Гнили — под новыми id, иначе полученная награда снова ждала бы на Доске.
static func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version > VERSION:
		push_warning("MetaProfile: профиль из более новой версии игры (%d), читаются известные поля" % from_version)
	if from_version >= VERSION:
		return data
	var result := data.duplicate(true)
	if from_version < 2:
		result["chronicle"] = {"counters": {"runs": data.get("runs", 0), "victories": data.get("victories", 0)}}
		var hero := str(data.get("last_hero", ""))
		result["unlocked"] = [hero] if DataRegistry.hero(StringName(hero)) != null else []
	if result.get("quests") is Array:
		result["quests"] = _renamed(result["quests"])
	var chronicle: Variant = result.get("chronicle")
	if chronicle is Dictionary and chronicle.get("lore") is Array:
		chronicle["lore"] = _renamed(chronicle["lore"])
	return result


static func _renamed(ids: Array) -> Array:
	return ids.map(func(id: Variant) -> Variant: return RENAMED_IDS.get(str(id), id))


static func _read_legacy(file_path: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(file_path) != OK:
		return {}
	var data := {}
	for key in config.get_section_keys("meta") if config.has_section("meta") else PackedStringArray():
		data[key] = config.get_value("meta", key)
	return data


static func _key(talent: TalentData, hero: HeroData) -> String:
	return GLOBAL if talent.is_global() else String(hero.id)


## Словарь из файла со строковыми ключами (не словарь или слишком большой — пусто).
static func _dict(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() > MAX_ENTRIES:
		return {}
	var result := {}
	for key: Variant in value:
		result[str(key)] = value[key]
	return result


## Список id из файла: только строки, без повторов, только то, что пропускает known.
static func _ids(value: Variant, known: Callable) -> Array[String]:
	var result: Array[String] = []
	if not value is Array or value.size() > MAX_ENTRIES:
		return result
	for item: Variant in value:
		if (item is String or item is StringName) and not str(item) in result and known.call(StringName(item)):
			result.append(str(item))
	return result


## Число из JSON (там все числа — float) или из ConfigFile; мусор → 0.
static func _int(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_finite(value):
		return int(clampf(value, -1e9, 1e9))
	return 0
