class_name TagDef
extends Resource
## Тег навыка и урона (шаг 2): стихия (огонь, холод…) или форма (снаряд, область…). По тегам работают
## прибавки «по тегу» (характеристика «might:fire»), сопротивления врагов стихиям и урон статусов.
## Каждому тегу DataRegistry выдаёт бит маски по порядку id: удар несёт все свои теги одним целым числом.

enum Kind { ELEMENT, FORM }

@export var id: StringName
@export var name_key: String
@export var kind := Kind.FORM
@export var color := Color.WHITE
