extends SceneTree
## Создаёт тестовую ONNX-модель с интерфейсом будущего декодера CVAE (DESIGN 2.3):
##   z[1,32], cond[1,8] → probs[1,12,32,32] (softmax по каналам).
## Внутри — Concat → MatMul → Add → Reshape → Softmax со случайными весами по фиксированному сиду.
## Это заготовка для проверки моста ONNX Runtime, а не генератор: настоящая модель обучается в ml/ на PyTorch.
## Запуск: godot --headless --path game --script res://tools/make_spike_model.gd

const OUTPUT := "res://models/spike/levelgen_spike.onnx"
const Z_DIM := 32
const COND_DIM := 8
const CHANNELS := 12
const SIZE := 32
const WEIGHT_SEED := 20261003

# Коды из onnx.proto
const FLOAT := 1
const INT64 := 7
const ATTR_INT := 2
const WIRE_VARINT := 0
const WIRE_BYTES := 2

## Априорный сдвиг каналов и разброс весов подобраны так, чтобы карты-заготовки проходили валидатор
## заметную долю раз: тогда сквозной путь «генерация → проверка → загрузка» проверяется и в игре.
## Порядок: VOID FLOOR WALL HAZARD RUBBLE PLAYER_SPAWN EXIT ENEMY_SPAWN CHEST FOUNTAIN STATUE OBELISK.
const CHANNEL_BIAS: PackedFloat32Array = [-1.0, 3.0, 1.0, 0.0, 0.5, -3.0, -3.0, -1.0, -2.0, -3.0, -3.0, -3.0]
const WEIGHT_STD := 0.25


## Минимальный писатель protobuf: только то, что нужно для ModelProto.
class Proto:
	var buf := PackedByteArray()

	func varint(value: int) -> void:
		assert(value >= 0)
		while value >= 0x80:
			buf.append((value & 0x7F) | 0x80)
			value >>= 7
		buf.append(value)

	func int_field(field: int, value: int) -> Proto:
		varint((field << 3) | WIRE_VARINT)
		varint(value)
		return self

	func bytes_field(field: int, data: PackedByteArray) -> Proto:
		varint((field << 3) | WIRE_BYTES)
		varint(data.size())
		buf.append_array(data)
		return self

	func string_field(field: int, text: String) -> Proto:
		return bytes_field(field, text.to_utf8_buffer())

	func message(field: int, inner: Proto) -> Proto:
		return bytes_field(field, inner.buf)


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = WEIGHT_SEED
	var in_dim := Z_DIM + COND_DIM
	var out_dim := CHANNELS * SIZE * SIZE

	var weights := PackedFloat32Array()
	weights.resize(in_dim * out_dim)
	for i in weights.size():
		weights[i] = rng.randfn(0.0, WEIGHT_STD)
	var bias := PackedFloat32Array()
	bias.resize(out_dim)
	for c in CHANNELS:
		for i in SIZE * SIZE:
			bias[c * SIZE * SIZE + i] = CHANNEL_BIAS[c]
	var shape := PackedInt64Array([1, CHANNELS, SIZE, SIZE])

	var graph := Proto.new()
	graph.message(1, _node("Concat", ["z", "cond"], ["h"], [_int_attr("axis", 1)]))
	graph.message(1, _node("MatMul", ["h", "W"], ["m"]))
	graph.message(1, _node("Add", ["m", "B"], ["logits_flat"]))
	graph.message(1, _node("Reshape", ["logits_flat", "shape"], ["logits"]))
	graph.message(1, _node("Softmax", ["logits"], ["probs"], [_int_attr("axis", 1)]))
	graph.string_field(2, "levelgen_spike")
	graph.message(5, _initializer("W", [in_dim, out_dim], FLOAT, weights.to_byte_array()))
	graph.message(5, _initializer("B", [out_dim], FLOAT, bias.to_byte_array()))
	graph.message(5, _initializer("shape", [4], INT64, shape.to_byte_array()))
	graph.message(11, _value_info("z", [1, Z_DIM]))
	graph.message(11, _value_info("cond", [1, COND_DIM]))
	graph.message(12, _value_info("probs", [1, CHANNELS, SIZE, SIZE]))

	var model := Proto.new()
	model.int_field(1, 8)  # ir_version
	model.string_field(2, "vault-of-endless-rot/make_spike_model.gd")
	model.message(7, graph)
	model.message(8, Proto.new().string_field(1, "").int_field(2, 17))  # opset ai.onnx 17

	DirAccess.make_dir_recursive_absolute(OUTPUT.get_base_dir())
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		printerr("Не удалось записать %s: %s" % [OUTPUT, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_buffer(model.buf)
	file.close()
	print("Записано %s: %d байт, sha256 %s" % [OUTPUT, model.buf.size(), FileAccess.get_sha256(OUTPUT)])
	quit(0)


func _node(op: String, inputs: Array, outputs: Array, attributes: Array = []) -> Proto:
	var node := Proto.new()
	for name: String in inputs:
		node.string_field(1, name)
	for name: String in outputs:
		node.string_field(2, name)
	node.string_field(3, op.to_snake_case())
	node.string_field(4, op)
	for attribute: Proto in attributes:
		node.message(5, attribute)
	return node


func _int_attr(name: String, value: int) -> Proto:
	return Proto.new().string_field(1, name).int_field(3, value).int_field(20, ATTR_INT)


func _initializer(name: String, dims: Array, data_type: int, raw: PackedByteArray) -> Proto:
	var tensor := Proto.new()
	for dim: int in dims:
		tensor.int_field(1, dim)
	tensor.int_field(2, data_type)
	tensor.string_field(8, name)
	tensor.bytes_field(9, raw)  # raw_data, little-endian
	return tensor


func _value_info(name: String, dims: Array) -> Proto:
	var shape := Proto.new()
	for dim: int in dims:
		shape.message(1, Proto.new().int_field(1, dim))
	var tensor_type := Proto.new().int_field(1, FLOAT).message(2, shape)
	return Proto.new().string_field(1, name).message(2, Proto.new().message(1, tensor_type))
