extends GutTest

const EXPECTED_SECONDS: Dictionary = {
	"place": 0.08,
	"sell": 0.10,
	"deploy": 0.05,
	"tower_fire": 0.04,
	"hit": 0.03,
	"destroy": 0.25,
	"win": 0.36,
	"lose": 0.36,
}


func _peak(samples: PackedFloat32Array) -> float:
	var peak: float = 0.0
	for s: float in samples:
		peak = maxf(peak, absf(s))
	return peak


func _zero_crossings(samples: PackedFloat32Array) -> int:
	var count: int = 0
	for i in range(1, samples.size()):
		if (samples[i - 1] < 0.0) != (samples[i] < 0.0):
			count += 1
	return count


func test_all_eight_clips_are_built_as_16_bit_mono_22050() -> void:
	var clips: Dictionary = SfxSynth.build_all()
	assert_eq(clips.size(), 8)
	for clip_name: String in EXPECTED_SECONDS:
		assert_true(clips.has(clip_name), "missing clip %s" % clip_name)
		var stream: AudioStreamWAV = clips[clip_name]
		assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS)
		assert_eq(stream.mix_rate, 22050)
		assert_false(stream.stereo)


func test_clip_durations_match_the_spec() -> void:
	for clip_name: String in EXPECTED_SECONDS:
		var samples: PackedFloat32Array = SfxSynth.samples_for(clip_name)
		var expected: int = int(roundf(float(EXPECTED_SECONDS[clip_name]) * 22050.0))
		assert_almost_eq(samples.size(), expected, 3, "%s length" % clip_name)
		var stream: AudioStreamWAV = SfxSynth.make_stream(samples)
		assert_eq(stream.data.size(), samples.size() * 2, "%s byte size" % clip_name)


func test_clips_are_audible_but_never_clip() -> void:
	for clip_name: String in EXPECTED_SECONDS:
		var peak: float = _peak(SfxSynth.samples_for(clip_name))
		assert_gt(peak, 0.01, "%s should not be silent" % clip_name)
		assert_lt(peak, 1.0, "%s should not clip" % clip_name)


func test_quiet_clips_are_quieter_than_place() -> void:
	var place_peak: float = _peak(SfxSynth.samples_for("place"))
	for clip_name: String in ["deploy", "tower_fire", "hit"]:
		assert_lt(_peak(SfxSynth.samples_for(clip_name)), place_peak * 0.5, "%s is low volume" % clip_name)
	assert_lt(_peak(SfxSynth.samples_for("hit")), _peak(SfxSynth.samples_for("tower_fire")), "hit is the quietest")


func test_place_is_a_660_hz_tone() -> void:
	var samples: PackedFloat32Array = SfxSynth.samples_for("place")
	# 2 zero crossings per cycle: 0.08 s * 660 Hz * 2 = 105.6
	assert_almost_eq(_zero_crossings(samples), 106, 4)


func test_sell_sweeps_downward() -> void:
	var samples: PackedFloat32Array = SfxSynth.samples_for("sell")
	var half: int = samples.size() / 2
	var first: int = _zero_crossings(samples.slice(0, half))
	var second: int = _zero_crossings(samples.slice(half))
	assert_gt(first, second, "pitch falls from 660 Hz to 330 Hz")


func test_deploy_is_a_square_wave() -> void:
	var samples: PackedFloat32Array = SfxSynth.samples_for("deploy")
	# One half-cycle at 880 Hz is about 12 samples; the level stays flat apart from the decay.
	for i in range(1, 11):
		assert_gt(samples[i], samples[1] * 0.9, "flat top at sample %d" % i)
	assert_almost_eq(_zero_crossings(samples), 88, 4)


func test_destroy_decays() -> void:
	var samples: PackedFloat32Array = SfxSynth.samples_for("destroy")
	var early: float = _peak(samples.slice(0, 500))
	var late: float = _peak(samples.slice(samples.size() - 500))
	assert_lt(late, early * 0.3)


func test_arpeggios_rise_and_fall() -> void:
	var win: PackedFloat32Array = SfxSynth.samples_for("win")
	var lose: PackedFloat32Array = SfxSynth.samples_for("lose")
	var note: int = SfxSynth.sample_count(SfxSynth.NOTE_S)
	assert_eq(win.size(), note * 3)
	var win_crossings: Array[int] = []
	var lose_crossings: Array[int] = []
	for i in range(3):
		win_crossings.append(_zero_crossings(win.slice(i * note, (i + 1) * note)))
		lose_crossings.append(_zero_crossings(lose.slice(i * note, (i + 1) * note)))
	assert_true(win_crossings[0] < win_crossings[1] and win_crossings[1] < win_crossings[2], "win rises: %s" % str(win_crossings))
	assert_true(lose_crossings[0] > lose_crossings[1] and lose_crossings[1] > lose_crossings[2], "lose falls: %s" % str(lose_crossings))


func test_synthesis_is_deterministic() -> void:
	for clip_name: String in EXPECTED_SECONDS:
		assert_eq(SfxSynth.make_stream(SfxSynth.samples_for(clip_name)).data, SfxSynth.make_stream(SfxSynth.samples_for(clip_name)).data)


func test_pcm_encoding_is_little_endian_and_clamped() -> void:
	var bytes: PackedByteArray = SfxSynth.to_pcm16(PackedFloat32Array([0.0, 1.0, -1.0, 5.0]))
	assert_eq(bytes.size(), 8)
	assert_eq(bytes.decode_s16(0), 0)
	assert_eq(bytes.decode_s16(2), 32767)
	assert_eq(bytes.decode_s16(4), -32767)
	assert_eq(bytes.decode_s16(6), 32767)


func test_unknown_clip_is_empty() -> void:
	assert_eq(SfxSynth.samples_for("nope").size(), 0)
