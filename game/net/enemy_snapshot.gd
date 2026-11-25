class_name EnemySnapshot
extends Node
## Часть снимка состояния врагов (ФТ-14, НФТ-07). Свойство data синхронизирует MultiplayerSynchronizer
## хоста каждые NetSync.INTERVAL секунд (20 Гц).
##
## Почему снимок, а не синхронизатор на каждом враге: врагов до 300 (DESIGN 3); отдельный синхронизатор
## — это ~20 байт заголовков и Variant на каждого 20 раз в секунду, ~120 КБ/с на клиента — больше
## порога НФТ-07 (100 КБ/с). Здесь запись врага — RECORD_SIZE байт: номер, позиция с шагом 1/8 px,
## доля здоровья с шагом 1/65535, флаги. Состояние узла больше MTU (1350 байт) синхронизатор не
## отправляет, поэтому враги разложены по нескольким частям, в каждой не больше CAPACITY.
##
## Создание и удаление врагов идёт через MultiplayerSpawner (ФТ-13), здесь — только изменяемые свойства.

const RECORD_SIZE := 11
const CAPACITY := 110
const POS_SCALE := 8.0
const POS_LIMIT := 32767.0 / POS_SCALE
const HEALTH_SCALE := 65535.0
## Бит 0 — ярость; биты 1–7 — статусы, видимые клиентам (StatusEffectData.visual_bit, шаг 2): размер
## записи не меняется.
const FLAG_ENRAGED := 1

## Записи врагов этой части снимка.
var data := PackedByteArray()


## Хост: упаковать врагов (nid → Enemy). Лишние сверх CAPACITY не попадут — вернётся их число.
func pack(enemies: Array) -> int:
	var count := mini(enemies.size(), CAPACITY)
	var buffer := PackedByteArray()
	buffer.resize(count * RECORD_SIZE)
	for i in count:
		var enemy: Enemy = enemies[i]
		var at := i * RECORD_SIZE
		buffer.encode_u32(at, int(enemy.get_meta(WorldNet.NID_META, 0)))
		buffer.encode_s16(at + 4, roundi(clampf(enemy.position.x, -POS_LIMIT, POS_LIMIT) * POS_SCALE))
		buffer.encode_s16(at + 6, roundi(clampf(enemy.position.y, -POS_LIMIT, POS_LIMIT) * POS_SCALE))
		var share := clampf(enemy.health / enemy.max_health, 0.0, 1.0) if enemy.max_health > 0.0 else 0.0
		buffer.encode_u16(at + 8, ceili(share * HEALTH_SCALE))  # ceil: живой враг не покажет 0
		buffer.encode_u8(at + 10, (FLAG_ENRAGED if enemy.enraged else 0) | (enemy.status_flags & 0xFE))
	data = buffer
	return enemies.size() - count


## Клиент: разобрать записи → [[nid, позиция, доля здоровья, флаги], …]. Пакет пришёл по сети,
## поэтому неполная запись в конце просто отбрасывается.
func unpack() -> Array:
	var result: Array = []
	var count := data.size() / RECORD_SIZE
	for i in count:
		var at := i * RECORD_SIZE
		result.append([
			data.decode_u32(at),
			Vector2(data.decode_s16(at + 4), data.decode_s16(at + 6)) / POS_SCALE,
			data.decode_u16(at + 8) / HEALTH_SCALE,
			data.decode_u8(at + 10),
		])
	return result
