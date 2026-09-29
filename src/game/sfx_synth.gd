class_name SfxSynth
extends RefCounted

## Procedural sound placeholders. Every clip is synthesised from maths at startup
## (16-bit mono PCM), so the project ships no audio files.

const MIX_RATE: int = 22050
const NAMES: Array[String] = ["place", "sell", "deploy", "tower_fire", "hit", "destroy", "win", "lose"]

const PLACE_S: float = 0.08
const PLACE_HZ: float = 660.0
const PLACE_AMP: float = 0.5
const PLACE_DECAY: float = 5.0

const SELL_S: float = 0.10
const SELL_HZ_FROM: float = 660.0
const SELL_HZ_TO: float = 330.0
const SELL_AMP: float = 0.5
const SELL_DECAY: float = 3.0

const DEPLOY_S: float = 0.05
const DEPLOY_HZ: float = 880.0
const DEPLOY_AMP: float = 0.12
const DEPLOY_DECAY: float = 3.0

const TOWER_FIRE_S: float = 0.04
const TOWER_FIRE_AMP: float = 0.16
const TOWER_FIRE_DECAY: float = 3.0

const HIT_S: float = 0.03
const HIT_AMP: float = 0.05
const HIT_DECAY: float = 2.0

const DESTROY_S: float = 0.25
const DESTROY_HZ: float = 110.0
const DESTROY_NOISE_AMP: float = 0.5
const DESTROY_SINE_AMP: float = 0.4
const DESTROY_DECAY: float = 7.0

const NOTE_S: float = 0.12
const NOTE_AMP: float = 0.4
const NOTE_DECAY: float = 4.0
const WIN_NOTES_HZ: Array[float] = [523.0, 659.0, 784.0]
const LOSE_NOTES_HZ: Array[float] = [392.0, 330.0, 262.0]

const NOISE_SEED: int = 12345


## Builds every clip, keyed by name.
static func build_all() -> Dictionary:
	var clips: Dictionary = {}
	for clip_name: String in NAMES:
		clips[clip_name] = make_stream(samples_for(clip_name))
	return clips


static func samples_for(clip_name: String) -> PackedFloat32Array:
	match clip_name:
		"place":
			return _voice(PLACE_S, PLACE_HZ, PLACE_HZ, PLACE_AMP, false, PLACE_DECAY)
		"sell":
			return _voice(SELL_S, SELL_HZ_FROM, SELL_HZ_TO, SELL_AMP, false, SELL_DECAY)
		"deploy":
			return _voice(DEPLOY_S, DEPLOY_HZ, DEPLOY_HZ, DEPLOY_AMP, true, DEPLOY_DECAY)
		"tower_fire":
			return _noise(TOWER_FIRE_S, TOWER_FIRE_AMP, TOWER_FIRE_DECAY, true)
		"hit":
			return _noise(HIT_S, HIT_AMP, HIT_DECAY, false)
		"destroy":
			return _destroy()
		"win":
			return _arpeggio(WIN_NOTES_HZ)
		"lose":
			return _arpeggio(LOSE_NOTES_HZ)
	return PackedFloat32Array()


static func make_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = to_pcm16(samples)
	return stream


## Little-endian signed 16-bit PCM, samples clamped to [-1, 1].
static func to_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return bytes


static func sample_count(seconds: float) -> int:
	return int(roundf(seconds * float(MIX_RATE)))


static func _envelope(index: int, count: int, decay: float) -> float:
	return exp(-decay * float(index) / float(maxi(count, 1)))


## Sine or square tone whose pitch glides linearly from f_from to f_to.
static func _voice(seconds: float, f_from: float, f_to: float, amp: float, square: bool, decay: float) -> PackedFloat32Array:
	var count: int = sample_count(seconds)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var freq: float = lerpf(f_from, f_to, float(i) / float(maxi(count - 1, 1)))
		phase = fposmod(phase + TAU * freq / float(MIX_RATE), TAU)
		var wave: float = sin(phase)
		if square:
			wave = 1.0 if wave >= 0.0 else -1.0
		out[i] = wave * amp * _envelope(i, count, decay)
	return out


## Deterministic white noise. `smooth` averages 2 neighbouring samples (rough band-limiting).
static func _noise(seconds: float, amp: float, decay: float, smooth: bool) -> PackedFloat32Array:
	var count: int = sample_count(seconds)
	var raw: PackedFloat32Array = _white(count)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		var value: float = raw[i]
		if smooth and i > 0:
			value = 0.5 * (raw[i] + raw[i - 1])
		out[i] = value * amp * _envelope(i, count, decay)
	return out


static func _white(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	var state: int = NOISE_SEED
	for i in range(count):
		state = (state * 1103515245 + 12345) & 0x7fffffff
		out[i] = float((state >> 8) & 0xffff) / 32768.0 - 1.0
	return out


static func _destroy() -> PackedFloat32Array:
	var count: int = sample_count(DESTROY_S)
	var noise: PackedFloat32Array = _white(count)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		var env: float = _envelope(i, count, DESTROY_DECAY)
		var tone: float = sin(TAU * DESTROY_HZ * float(i) / float(MIX_RATE))
		out[i] = (noise[i] * DESTROY_NOISE_AMP + tone * DESTROY_SINE_AMP) * env
	return out


static func _arpeggio(notes_hz: Array[float]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for hz: float in notes_hz:
		out.append_array(_voice(NOTE_S, hz, hz, NOTE_AMP, false, NOTE_DECAY))
	return out
