extends Node
## Глобальная шина сигналов. Сигналы объявлены здесь, а испускают их игровые системы.
@warning_ignore_start("unused_signal")

signal level_loaded(level: LevelData)
## Клетка карты сменилась посреди уровня (шаг 9: стена тайника стала полом) — у каждого участника, после
## World.apply_cell_tile: поле потока врагов и миникарта обновляются.
signal level_cell_changed(cell: Vector2i, tile: int)
signal level_timer_expired
signal player_spawned(player: Node)
signal player_died(peer_id: int)
## «Последний вздох» (кооператив): союзник by_peer_id поднял павшего героя peer_id.
signal player_revived(peer_id: int, by_peer_id: int)
signal enemy_died(enemy: Node, killer_peer_id: int)
signal xp_collected(peer_id: int, amount: int)
## cards: [{"id": StringName, "level": int}] — ровно 3 уникальные карты (ФТ-10).
signal level_up_offered(peer_id: int, cards: Array)
## index — номер записи в WaveTable.waves, испускается один раз за уровень (ФТ-09, событие ФТ-16).
signal wave_started(index: int)
signal boss_spawned(boss: Node)
signal boss_defeated
signal portal_activated
signal run_ended(victory: bool)
## Финальный босс повержен: открыты порталы «Завершить забег» и «Бесконечная гниль» (CR-08).
signal run_choice_offered
## Объекты карты (CR-06): обелиск — фрагмент карты Грааля; статуя — пробуждение мини-босса.
signal obelisk_visited(count: int, needed: int)
signal grail_found(peer_id: int)
signal statue_awakened
## Лут (CR-07): предмет подобран; экипировка или сумка игрока изменились.
signal item_picked(peer_id: int, item: Dictionary)
signal inventory_changed(peer_id: int)
## Хост: удар по врагу — для всплывающих цифр урона; game/net пересылает клиентам ненадёжным RPC.
signal damage_dealt(pos: Vector2, amount: float, crit: bool)
## Хост: сработала реакция статусов (StatusReaction) над врагом — надпись над ним (шаг 2).
signal status_reaction(pos: Vector2, reaction: StringName)
## Золото и торговцы (CR-14): монеты подобраны; покупка или продажа состоялась.
signal gold_collected(peer_id: int, amount: int)
signal trade_completed(peer_id: int, merchant_id: StringName)
## Платный сундук открыт за price золота.
signal chest_opened(peer_id: int, price: int)
## Пассивки: Оберег поглотил удар; Второе дыхание подняло героя.
signal ward_blocked(peer_id: int)
signal second_wind(peer_id: int)
## Испытания (CR-16): kind — id объекта (trial_altar, cursed_totem, statue); duration — секунд на испытание.
signal challenge_started(kind: StringName, duration: float)
signal challenge_finished(kind: StringName, success: bool)
## Интерактивная точка (шаг 8): type_id — InteractableData.id; outcome — shrine, cursed, guards, freed, broken
## (у мимика — mimic; шаг 9: secret — проломлена стена тайника). peer_id — кто её задействовал (0 — никто, стража
## перебита). game/net пересылает клиентам.
signal interactable_used(type_id: StringName, peer_id: int, outcome: StringName)
## Свой игрок прочёл запись лора (локально, в сеть не уходит) — для «Летописи».
signal lore_read(lore_id: StringName)
signal generation_logged(record: Dictionary)
## Все попытки генерации отбракованы (ФТ-05) — загружена запасная арена; reason — для журнала, не для UI.
signal level_generation_failed(reason: String)
