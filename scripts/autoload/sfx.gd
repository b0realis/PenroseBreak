extends Node
## Sfx — procedural sound effects (autoload "Sfx").
##
## Synth toolkit from the Prescription Games shared toolkit: every sound is
## built once in _ready() from swept-frequency oscillators and lowpass-swept
## noise with exponential decay envelopes, into 22050 Hz 16-bit mono
## AudioStreamWAV streams, played through a round-robin pool of 8 players
## with slight pitch randomization. No audio files shipped.
##
## Play with:  Sfx.play("paddle")
##             Sfx.play("block", 0.03, 1.2)   # pitch_base rises per hit stage
## Unknown names warn once and are otherwise ignored.

const RATE := 22050
const MASTER_DB := -8.0
const POOL_SIZE := 8

enum Wave { SINE, SQUARE, SAW, TRIANGLE }

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _rng := RandomNumberGenerator.new()  # synth + pitch jitter; NOT gameplay RNG
var _warned: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1889  # fixed seed → identical noise textures every boot
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = MASTER_DB
		add_child(p)
		_players.append(p)
	_build_all()


## Play a named sound at pitch_base × a random factor in
## [1-pitch_var, 1+pitch_var]. Names: "ui","launch","paddle","block","break",
## "wall","win","best","whoosh","boost".
func play(sound_name: String, pitch_var := 0.08, pitch_base := 1.0) -> void:
	if not _streams.has(sound_name):
		if not _warned.has(sound_name):
			_warned[sound_name] = true
			push_warning("Sfx: unknown sound '%s'" % sound_name)
		return
	if not Game.sfx_on:
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stop()
	p.stream = _streams[sound_name]
	p.pitch_scale = maxf(0.05, pitch_base * (1.0 + _rng.randf_range(-pitch_var, pitch_var)))
	p.play()


# ------------------------------------------------------------- recipes ------

## The nine game sounds. Comments give the sound-design intent so the recipes
## stay editable rather than magic.
func _build_all() -> void:
	# ui: neutral short blip for menu focus/press.
	_streams["ui"] = _to_stream(_tone(0.07, 920.0, 900.0, Wave.SINE, 22.0, 0.4))
	# launch: springy rising chirp — the ball leaves the paddle for the first time.
	_streams["launch"] = _to_stream(_mix([
		_tone(0.20, 320.0, 760.0, Wave.SINE, 8.0, 0.7),
		_tone(0.20, 160.0, 380.0, Wave.TRIANGLE, 10.0, 0.3),
	]))
	# paddle: the heavy deflect — a deep square knock with a sub-bass sine
	# thump and a bright noise crack on top. This is the "power up" moment,
	# so it must feel like a piston, not a ping.
	_streams["paddle"] = _to_stream(_mix([
		_tone(0.13, 220.0, 70.0, Wave.SQUARE, 18.0, 0.5),
		_tone(0.22, 110.0, 36.0, Wave.SINE, 9.0, 0.85),
		_noise_hiss(0.05, 45.0, 3600.0, 1200.0, 0.5),
	]))
	# block: glassy tick — short bright sine ding over a tiny knock. The game
	# re-pitches it upward per color stage so a block sings up a scale as it
	# whitens toward destruction.
	_streams["block"] = _to_stream(_mix([
		_tone(0.12, 1180.0, 1140.0, Wave.SINE, 16.0, 0.5),
		_tone(0.06, 300.0, 140.0, Wave.SQUARE, 26.0, 0.22),
	]))
	# break: crystal shatter — sharp noise crack, three inharmonic glass ring
	# partials fading at different rates, and a low bloom for weight.
	_streams["break"] = _to_stream(_mix([
		_noise_hiss(0.10, 30.0, 4600.0, 1700.0, 0.85),
		_delayed(_tone(0.40, 1860.0, 1810.0, Wave.SINE, 7.0, 0.26), 0.012),
		_delayed(_tone(0.36, 2620.0, 2540.0, Wave.SINE, 8.0, 0.20), 0.028),
		_delayed(_tone(0.28, 3350.0, 3240.0, Wave.SINE, 9.5, 0.13), 0.05),
		_tone(0.26, 140.0, 46.0, Wave.SINE, 8.0, 0.6),
	]))
	# wall: soft dull thud off the side rails and the floor.
	_streams["wall"] = _to_stream(_mix([
		_tone(0.09, 200.0, 90.0, Wave.SINE, 20.0, 0.55),
		_noise_hiss(0.04, 50.0, 1600.0, 500.0, 0.3),
	]))
	# whoosh: the ball leaving the screen overhead — air through a rising lowpass.
	_streams["whoosh"] = _to_stream(
		_noise_hiss(0.30, 8.0, 400.0, 2600.0, 0.45, 0.05))
	# boost: the Space kick — a rising afterburner whoosh over a sine up-chirp
	# and a short sub thump for punch.
	_streams["boost"] = _to_stream(_mix([
		_noise_hiss(0.24, 10.0, 500.0, 3400.0, 0.5, 0.02),
		_tone(0.18, 190.0, 620.0, Wave.SINE, 9.0, 0.55),
		_tone(0.12, 95.0, 48.0, Wave.SINE, 15.0, 0.5),
	]))
	# win: rising four-note fanfare (C5 E5 G5 C6), each doubled an octave
	# down on triangle for body — the wall is down.
	_streams["win"] = _to_stream(_mix([
		_tone(0.34, 523.25, 522.0, Wave.SINE, 7.0, 0.4),
		_tone(0.34, 261.6, 261.0, Wave.TRIANGLE, 7.0, 0.16),
		_delayed(_tone(0.34, 659.26, 658.0, Wave.SINE, 7.0, 0.4), 0.11),
		_delayed(_tone(0.34, 783.99, 782.5, Wave.SINE, 6.5, 0.42), 0.22),
		_delayed(_tone(0.6, 1046.5, 1043.0, Wave.SINE, 4.5, 0.5), 0.33),
		_delayed(_tone(0.6, 523.25, 521.5, Wave.TRIANGLE, 4.5, 0.2), 0.33),
	]))
	# best: extra shimmer stacked on "win" for a new record — two high detuned
	# sines chasing each other.
	_streams["best"] = _to_stream(_mix([
		_tone(0.5, 1568.0, 1560.0, Wave.SINE, 6.0, 0.35),
		_delayed(_tone(0.55, 2093.0, 2083.0, Wave.SINE, 5.5, 0.3), 0.09),
	]))


# ------------------------------------------------------- synth toolkit ------

## Oscillator with an exponential frequency sweep f0→f1 (Hz, both > 0) and an
## attack→exponential-decay envelope. decay is the exp() falloff rate (bigger
## = shorter); attack is the linear fade-in time in seconds (kills clicks).
func _tone(dur: float, f0: float, f1: float, wave: Wave, decay: float,
		amp := 1.0, attack := 0.004) -> PackedFloat32Array:
	var n := maxi(int(dur * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var ratio := f1 / f0
	for i in n:
		var t := float(i) / RATE
		phase += f0 * pow(ratio, t / dur) / RATE
		var cycle := fposmod(phase, 1.0)
		var s: float
		match wave:
			Wave.SINE:
				s = sin(TAU * phase)
			Wave.SQUARE:
				s = 1.0 if cycle < 0.5 else -1.0
			Wave.SAW:
				s = 2.0 * cycle - 1.0
			_:
				s = 4.0 * absf(cycle - 0.5) - 1.0  # TRIANGLE
		out[i] = s * amp * minf(t / attack, 1.0) * exp(-decay * t)
	return out


## White noise through a one-pole lowpass whose cutoff sweeps cut0→cut1 (Hz).
## Sweeping up = "whoosh", sweeping down = "thud/rumble". Envelope as _tone.
func _noise_hiss(dur: float, decay: float, cut0: float, cut1: float,
		amp := 1.0, attack := 0.003) -> PackedFloat32Array:
	var n := maxi(int(dur * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var cut := lerpf(cut0, cut1, t / dur)
		var a := clampf(TAU * cut / RATE, 0.0, 1.0)
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * 2.2 * amp * minf(t / attack, 1.0) * exp(-decay * t)
	return out


## Sum several sample buffers (result is as long as the longest part). Parts
## shorter than the mix get a ~5 ms tail fade so the step to silence never clicks.
func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for part: PackedFloat32Array in parts:
		n = maxi(n, part.size())
	var out := PackedFloat32Array()
	out.resize(n)
	var fade := int(0.005 * RATE)  # 5 ms
	for part: PackedFloat32Array in parts:
		var pn := part.size()
		var tail := mini(fade, pn) if pn < n else 0
		for i in pn:
			var v := part[i]
			if i >= pn - tail:
				v *= float(pn - 1 - i) / tail
			out[i] += v
	return out


## Prepend sec seconds of silence — for arpeggios and staggered layers.
func _delayed(samples: PackedFloat32Array, sec: float) -> PackedFloat32Array:
	var pad := PackedFloat32Array()
	pad.resize(maxi(int(sec * RATE), 0))
	pad.append_array(samples)
	return pad


## Convert float samples to a 16-bit mono AudioStreamWAV: soft-limit peaks,
## then fade the first/last few ms so no stream starts or ends off-zero.
func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(samples[i]))
	var gain := 1.0 if peak <= 0.95 else 0.95 / peak
	var fade_in := mini(int(0.002 * RATE), n)     # 2 ms
	var fade_out := mini(int(0.012 * RATE), n)    # 12 ms
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := samples[i] * gain
		if i < fade_in:
			v *= float(i) / fade_in
		if i >= n - fade_out:
			v *= float(n - 1 - i) / fade_out
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
