class_name SoundBank
## Процедурные звуки: всё синтезируется при запуске, никаких сторонних файлов.

const RATE := 22050
static var _cache := {}


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func motor_loop(kind: int) -> AudioStreamWAV:
	var key := "motor%d" % kind
	if _cache.has(key):
		return _cache[key]
	var n := RATE  # 1 с — все частоты целые, петля без щелчка
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + kind
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		if kind == SimConst.Kind.COPTER:
			# Четыре мотора с чуть разной частотой дают «биения».
			for m in 4:
				var f := 190.0 + m * 3.0
				var ph := fmod(t * f, 1.0)
				v += (ph * 2.0 - 1.0) * 0.12
				v += sin(TAU * f * 2.0 * t) * 0.05
		else:
			var f := 96.0
			var ph := fmod(t * f, 1.0)
			v += (ph * 2.0 - 1.0) * 0.28 + sin(TAU * f * 3.0 * t) * 0.08
		lp = lerpf(lp, rng.randf_range(-1, 1), 0.25)
		v += lp * 0.18
		s[i] = v * 0.8
	var w := _wav(s, true)
	_cache[key] = w
	return w


static func noise_loop(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var n := RATE * 2
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	var b := 0.0
	for i in n:
		var w := rng.randf_range(-1, 1)
		if kind == "wind":
			b = clampf(b + w * 0.02, -1.0, 1.0) * 0.998
			s[i] = b * 0.9
		else: # «static» — треск помех
			var crack := 1.0 if rng.randf() < 0.002 else 0.0
			s[i] = w * 0.35 + crack * rng.randf_range(-1, 1)
	# Сглаживаем стык петли.
	for i in 400:
		var k := float(i) / 400.0
		s[i] = lerpf(s[n - 400 + i], s[i], k)
	var wav := _wav(s, true)
	_cache[kind] = wav
	return wav


static func explosion(big: bool) -> AudioStreamWAV:
	var key := "boom%d" % int(big)
	if _cache.has(key):
		return _cache[key]
	var dur := 2.6 if big else 1.8
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99 + int(big)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * (2.2 if big else 3.0))
		var cut := lerpf(0.5, 0.03, minf(1.0, t * 1.5))
		lp = lerpf(lp, rng.randf_range(-1, 1), cut)
		var thump := sin(TAU * (55.0 - t * 20.0) * t) * exp(-t * 6.0)
		var attack := minf(1.0, t * 300.0)
		s[i] = (lp * 1.6 * env + thump * 0.9) * attack
	var w := _wav(s, false)
	_cache[key] = w
	return w


static func beep(freq: float, dur: float) -> AudioStreamWAV:
	var key := "beep%d_%d" % [int(freq), int(dur * 1000)]
	if _cache.has(key):
		return _cache[key]
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 200.0) * minf(1.0, (dur - t) * 60.0)
		s[i] = sin(TAU * freq * t) * 0.3 * env
	var w := _wav(s, false)
	_cache[key] = w
	return w
