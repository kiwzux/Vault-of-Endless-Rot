class_name NpzWriter
extends RefCounted
## Запись .npz (zip из .npy, формат numpy 1.0) — датасет читается в Python через numpy.load без конвертеров.

var _arrays: Array[Dictionary] = []


## descr — тип numpy: "|u1" для uint8, "<i8" для int64; shape — размеры, произведение = числу элементов.
func add(name: String, descr: String, shape: Array, data: PackedByteArray) -> void:
	_arrays.append({"name": name, "descr": descr, "shape": shape, "data": data})


func save(path: String) -> Error:
	var zip := ZIPPacker.new()
	var err := zip.open(path)
	if err != OK:
		return err
	for array in _arrays:
		zip.start_file(array["name"] + ".npy")
		zip.write_file(_npy(array["descr"], array["shape"], array["data"]))
		zip.close_file()
	return zip.close()


static func _npy(descr: String, shape: Array, data: PackedByteArray) -> PackedByteArray:
	var dims := ", ".join(shape.map(func(d: int) -> String: return str(d)))
	if shape.size() == 1:
		dims += ","
	var header := "{'descr': '%s', 'fortran_order': False, 'shape': (%s), }" % [descr, dims]
	# Заголовок дополняется пробелами и \n так, чтобы данные начинались с кратного 64 смещения.
	var total := 10 + header.length() + 1
	header += " ".repeat((64 - total % 64) % 64) + "\n"
	var bytes := PackedByteArray([0x93])
	bytes.append_array("NUMPY".to_ascii_buffer())
	bytes.append_array(PackedByteArray([1, 0, header.length() & 0xFF, header.length() >> 8]))
	bytes.append_array(header.to_ascii_buffer())
	bytes.append_array(data)
	return bytes
