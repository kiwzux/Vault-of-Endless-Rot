class_name LoreData
extends Resource
## Запись лора (шаг 8): надпись на камне, книга или записка у трупа искателя. Читается у точки лора
## (Interactable вида LORE), прочитанная попадает в «Летопись» (MetaProfile, вкладка «Записи»).
## Новая запись — новый .tres в data/lore/.

@export var id: StringName
@export var order := 0
@export var title_key: String
@export var text_key: String
## Облик точки: inscription, book, corpse.
@export var look: StringName = &"inscription"
