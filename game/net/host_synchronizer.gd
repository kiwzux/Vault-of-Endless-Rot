class_name HostSynchronizer
extends MultiplayerSynchronizer
## Синхронизатор с полномочиями хоста внутри узла, которым владеет игрок (ФТ-14).
## Player._enter_tree отдаёт владельцу весь свой узел вместе с детьми; дети входят в дерево позже
## родителя, поэтому здесь полномочия возвращаются хосту — здоровье, опыт, золото и экипировку
## героя меняет только он.


func _enter_tree() -> void:
	set_multiplayer_authority(1, false)
