class_name ItemBaseData
extends Resource
## База предмета экипировки (CR-07): слот и встроенная характеристика со случайным значением.

## Слоты экипировки в духе Diablo. 18.10.2026 — кольца: у баз слот RING, а на кукле два пальца — RING и RING_2
## (Player.receive_item кладёт кольцо на свободный палец или вместо слабейшего из двух). Номера прежних слотов
## не менялись (AffixData.slots, профиль трофеев).
enum Slot { WEAPON, HELM, ARMOR, GLOVES, BOOTS, AMULET, RING, RING_2 }

const SLOT_KEYS: PackedStringArray = [
	"SLOT_WEAPON", "SLOT_HELM", "SLOT_ARMOR", "SLOT_GLOVES", "SLOT_BOOTS", "SLOT_AMULET", "SLOT_RING", "SLOT_RING",
]

@export var id: StringName
@export var name_key: String
@export var slot := Slot.WEAPON
## Характеристика героя (Player.STAT_*) и диапазон её значения.
@export var implicit_stat: StringName
@export var implicit_min := 0.0
@export var implicit_max := 0.0
@export var icon_color := Color.WHITE
## Варианты значка (имена из атласа art/gen_icons.py, ItemIcon): выпавший предмет берёт один из них по своему
## значению встроенной характеристики (ItemRoller.icon_of) — у всех участников одинаково, по сети ничего лишнего.
@export var icons := PackedStringArray()
## Род названия (m — мужской, f — женский, n — средний, pl — множественное): префикс-прилагательное согласуется
## с ним («Пылающий клинок», «Пылающая кираса», «Пылающее кольцо», «Пылающие сапоги», AffixData.display_key).
@export var gender: StringName = &"m"
