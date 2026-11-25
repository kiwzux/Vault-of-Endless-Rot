class_name LootSound
extends RefCounted
## Звук выпавшего предмета по редкости (шаг 7, раздел 9 техзадания): синтезируется кодом при первом
## использовании — без звуковых файлов, как графика проекта. Магический — одна мягкая нота, редкий — две
## восходящие, легендарный — яркое арпеджио, проклятый — низкий диссонанс с дрожанием.
## Играет у каждого участника сам: узел предмета есть у всех (MultiplayerSpawner), по сети ничего не идёт.
## Громкость — общая шина (Settings.master_volume); одновременно звучит не больше MAX_VOICES.

const MIX_RATE := 22050
const MAX_VOICES := 6
const VOLUME_DB := -8.0
## Ноты по редкости (ItemRoller.Rarity): [частота, Гц; начало, с]; длительность звука, с; дрожание (проклятый).
const NOTES := {
	1: [[880.0, 0.0]],
	2: [[660.0, 0.0], [990.0, 0.09]],
	3: [[523.25, 0.0], [659.25, 0.08], [783.99, 0.16], [1046.5, 0.24]],
	4: [[155.56, 0.0], [220.0, 0.0], [233.08, 0.05]],
}
const LENGTH := {1: 0.35, 2: 0.45, 3: 0.9, 4: 0.8}

static var _streams := {}
static var _voices := 0


## Сыграть звук редкости rarity в точке node (узел предмета). Обычные предметы молчат.
static func play(node: Node2D, rarity: int) -> void:
	var world := World.of(node)
	if not NOTES.has(rarity) or _voices >= MAX_VOICES or world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream_for(rarity)
	player.volume_db = VOLUME_DB
	player.bus = &"SFX"  # ползунок «Звуки» (шаг 11.13)
	# Звук не обрывается, если предмет тут же подобрали: проигрыватель — узел мира, а не предмета
	# (и не контейнера World/Pickups, за которым следит спавнер).
	world.add_child(player)
	player.global_position = node.global_position
	_voices += 1
	player.tree_exited.connect(func() -> void: _voices -= 1)  # и при смене сцены посреди звука
	player.finished.connect(player.queue_free)
	player.play()


## Готовый звук редкости (кэш): 16 бит, моно.
static func stream_for(rarity: int) -> AudioStreamWAV:
	if _streams.has(rarity):
		return _streams[rarity]
	var length: float = LENGTH[rarity]
	var count := int(length * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var notes: Array = NOTES[rarity]
	for i in count:
		var t := float(i) / MIX_RATE
		var sample := 0.0
		for note: Array in notes:
			var local := t - float(note[1])
			if local < 0.0:
				continue
			var envelope := minf(local / 0.005, 1.0) * exp(-local * (3.0 if rarity == 3 else 6.0))
			var tone := sin(TAU * float(note[0]) * local) + 0.3 * sin(TAU * float(note[0]) * 2.0 * local)
			sample += tone * envelope
		if rarity == 4:  # проклятый: дрожание громкости
			sample *= 0.7 + 0.3 * sin(TAU * 9.0 * t)
		data.encode_s16(i * 2, int(clampf(sample / notes.size() * 0.9, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	_streams[rarity] = stream
	return stream
