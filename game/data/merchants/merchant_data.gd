class_name MerchantData
extends Resource
## Торговец (CR-14): что продаёт и покупает. Тексты — ключи таблицы переводов (НФТ-08).

@export var id: StringName
@export var name_key: String
@export var greeting_key: String
## Временный цвет фигуры, пока нет спрайтов.
@export var robe_color := Color.WHITE
## Предметов экипировки на продажу и их минимальная редкость (ItemRoller.Rarity).
@export var item_count := 0
@export var item_min_rarity := 1
@export var goods: Array[GoodsData] = []
## Сколько сделок может заключить один герой у этого торговца за уровень; 0 — без ограничения.
@export var deals_per_player := 0
