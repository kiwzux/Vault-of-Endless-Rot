class_name BuildInfo
extends RefCounted
## Метка сборки — по ней хост пускает в кооператив только ту же сборку игры (Net, рукопожатие при подключении).
## Сборку (.exe) метит при экспорте addons/build_stamp: коммит, «+», если в рабочей копии были незакоммиченные
## правки, и время экспорта — у двух разных экспортов меток-двойников не бывает. Запуск из редактора — метка DEV:
## такой запуск подключается только к такому же (два окна на одном ПК, tools/net_test).

const PATH := "res://build_id.txt"
const DEV := "dev"

static var _id := ""


static func id() -> String:
	if _id == "":
		var text := FileAccess.get_file_as_string(PATH).strip_edges() if FileAccess.file_exists(PATH) else ""
		_id = text if text != "" else DEV
	return _id


static func is_dev() -> bool:
	return id() == DEV


## Только для tools/net_test: процесс выдаёт себя за другую сборку.
static func override_for_tests(value: String) -> void:
	_id = value
