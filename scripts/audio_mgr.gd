extends Node
## AudioMgr —— 全程序化音频（autoload 单例）。
##
## 项目不携带任何音频素材：风声、低频轰鸣与全部音效都在启动时用代码合成成
## AudioStreamWAV，既避免版权问题，也让整个工程保持自包含、体积可控。

const MIX_RATE := 22050
const AMBIENCE_SECONDS := 4.0

var _bgm: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _ui: AudioStreamPlayer
var _voice: AudioStreamPlayer
## 打字音需要短时间内连续触发，单个播放器会被 stop() 截断，
## 所以用一个轮播池，让相邻两声可以自然叠在一起。
var _type_pool: Array[AudioStreamPlayer] = []
var _type_idx: int = 0
var _type_rng := RandomNumberGenerator.new()

var _ambience_cache: Dictionary = {}
var _sfx_cache: Dictionary = {}
var _voice_cache: Dictionary = {}
var _current := ""
var _ready_audio := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "Bgm"
	_bgm.bus = "Master"
	add_child(_bgm)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "Sfx"
	add_child(_sfx)
	_ui = AudioStreamPlayer.new()
	_ui.name = "Ui"
	add_child(_ui)
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	add_child(_voice)
	for i: int in range(4):
		var tp := AudioStreamPlayer.new()
		tp.name = "Type%d" % i
		add_child(tp)
		_type_pool.append(tp)
	_type_rng.seed = 20401005
	_apply_volumes()
	# 合成放到首帧之后，避免拖慢启动
	_build_sfx.call_deferred()
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.settings_changed.connect(_apply_volumes)


# ===========================================================================
# 对外接口
# ===========================================================================
## kind: menu / calm / tense / finale / collapse
func play_bgm(kind: String) -> void:
	if _is_headless() or kind == "":
		return
	if _current == kind and _bgm.playing:
		return
	_current = kind
	if not _ambience_cache.has(kind):
		_ambience_cache[kind] = _to_wav(_synth_ambience(kind), true)
	_bgm.stream = _ambience_cache[kind]
	_bgm.volume_db = _db(_bgm_volume())
	_bgm.play()


func stop_bgm() -> void:
	_current = ""
	if _bgm != null:
		_bgm.stop()


## name: click / hover / confirm / warn / success / fail / type
func play_sfx(name: String) -> void:
	if _is_headless():
		return
	_ensure_sfx()
	if not _sfx_cache.has(name):
		return
	_ui.stop()
	_ui.stream = _sfx_cache[name]
	_ui.volume_db = _db(_sfx_volume())
	_ui.play()


func play_voice_thud() -> void:
	play_sfx("thud")


# ---------------------------------------------------------------------------
# 打字机音效：每次逐字显示时调用，内部随机挑一个变体、轮流用播放器池播放
# ---------------------------------------------------------------------------
func play_type() -> void:
	if _is_headless() or not typing_enabled():
		return
	_ensure_sfx()
	if _sfx_cache.is_empty():
		return
	_type_idx = (_type_idx + 1) % maxi(_type_pool.size(), 1)
	var p := _type_pool[_type_idx]
	var variant := 1 + _type_rng.randi_range(0, 3)
	var key := "type%d" % variant
	if not _sfx_cache.has(key):
		key = "type1"
	if not _sfx_cache.has(key):
		return
	p.stream = _sfx_cache[key]
	p.volume_db = _db(_sfx_volume() * 0.85)
	p.play()


func typing_enabled() -> bool:
	var gs := get_node_or_null("/root/GameState")
	return bool(gs.typing_on) if gs != null else true


# ---------------------------------------------------------------------------
# 剧情配音：res://assets/audio/vo/<id>.mp3
# ---------------------------------------------------------------------------
func has_voice(id: String) -> bool:
	if id == "":
		return false
	return _voice_path(id) != ""


func play_voice(id: String) -> void:
	if _is_headless() or id == "":
		return
	var gs := get_node_or_null("/root/GameState")
	if gs != null and not bool(gs.voice_on):
		return
	var path := _voice_path(id)
	if path == "":
		return
	if not _voice_cache.has(path):
		_voice_cache[path] = load(path)
	var st: Resource = _voice_cache.get(path, null)
	if st == null:
		return
	_voice.stop()
	_voice.stream = st
	_voice.volume_db = _db(_voice_volume())
	_voice.play()


func stop_voice() -> void:
	if _voice != null and _voice.playing:
		_voice.stop()


func _voice_path(id: String) -> String:
	for ext: String in [".mp3", ".ogg", ".wav"]:
		var p := "res://assets/audio/vo/%s%s" % [id, ext]
		if ResourceLoader.exists(p):
			return p
	return ""


func _apply_volumes() -> void:
	if _bgm != null:
		_bgm.volume_db = _db(_bgm_volume())
	if _sfx != null:
		_sfx.volume_db = _db(_sfx_volume())
	if _voice != null:
		_voice.volume_db = _db(_voice_volume())


func _voice_volume() -> float:
	var gs := get_node_or_null("/root/GameState")
	return float(gs.voice_volume) if gs != null else 0.9


func _bgm_volume() -> float:
	var gs := get_node_or_null("/root/GameState")
	return float(gs.bgm_volume) if gs != null else 0.55


func _sfx_volume() -> float:
	var gs := get_node_or_null("/root/GameState")
	return float(gs.sfx_volume) if gs != null else 0.7


func _db(linear: float) -> float:
	var v := clampf(linear, 0.0, 1.0)
	return -80.0 if v <= 0.001 else linear_to_db(v)


# ===========================================================================
# 音效合成
# ===========================================================================
func _ensure_sfx() -> void:
	if _ready_audio:
		return
	_build_sfx()


func _build_sfx() -> void:
	if _ready_audio:
		return
	_ready_audio = true
	var specs := {
		"click":   {"notes": [1180.0],                    "dur": 0.055, "gain": 0.30, "harm": 2.0},
		"hover":   {"notes": [760.0],                     "dur": 0.030, "gain": 0.14, "harm": 1.0},
		"confirm": {"notes": [660.0, 990.0],              "dur": 0.150, "gain": 0.28, "harm": 1.6},
		"warn":    {"notes": [300.0, 240.0],              "dur": 0.240, "gain": 0.26, "harm": 1.0},
		"success": {"notes": [523.0, 659.0, 784.0, 1046.0], "dur": 0.420, "gain": 0.26, "harm": 1.4},
		"fail":    {"notes": [392.0, 262.0, 196.0],       "dur": 0.480, "gain": 0.28, "harm": 1.0},
		"thud":    {"notes": [120.0, 90.0],               "dur": 0.320, "gain": 0.34, "harm": 1.0},
	}
	for k: String in specs.keys():
		_sfx_cache[k] = _to_wav(_synth_notes(Dictionary(specs[k])), false)
	# 机械键盘敲击音：4 个变体，逐字显示时随机挑一个
	for v: int in range(1, 5):
		_sfx_cache["type%d" % v] = _to_wav(_synth_key_click(v * 977), false)
	_sfx_cache["type"] = _sfx_cache["type1"]


## 合成一声机械键盘敲击：
##   ① 极短白噪声瞬态 —— 键轴触底的「咔」
##   ② 键帽回弹的低频共鸣（两个泛音）
##   ③ 高频「嗒」声，让它在嘈杂环境里也听得见
func _synth_key_click(seed_val: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var dur := 0.052
	var n := int(MIX_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := rng.randf_range(148.0, 232.0)          # 共鸣基频：每个变体略不同
	var jitter := rng.randf_range(-0.08, 0.08)
	var lp := 0.0
	for i: int in range(n):
		var t := float(i) / float(MIX_RATE)
		var white := rng.randf_range(-1.0, 1.0)
		# ① 敲击瞬态：先过一级低通，去掉刺耳的纯白噪
		lp = lp * 0.55 + white * 0.45
		var click := lp * exp(-t * 420.0)
		# ② 键帽回弹
		var body := sin(TAU * f * t) * exp(-t * 118.0) * 0.52 \
			+ sin(TAU * f * 2.68 * t) * exp(-t * 205.0) * 0.20
		# ③ 高频「嗒」
		var tick := sin(TAU * (2480.0 + jitter * 900.0) * t) * exp(-t * 760.0) * 0.20
		out[i] = click * 0.72 + body + tick
	return _fade_edges(out, 0.002)


func _synth_notes(spec: Dictionary) -> PackedFloat32Array:
	var notes: Array = spec.get("notes", [440.0])
	var dur := float(spec.get("dur", 0.15))
	var gain := float(spec.get("gain", 0.3))
	var harm := float(spec.get("harm", 1.0))
	var n := int(MIX_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var seg := dur / float(maxi(notes.size(), 1))
	for i: int in range(n):
		var t := float(i) / float(MIX_RATE)
		var idx := mini(int(t / seg), notes.size() - 1)
		var f := float(notes[idx])
		var local := t - float(idx) * seg
		var env := exp(-local * (5.0 / maxf(seg, 0.005)))
		var attack := clampf(local / 0.006, 0.0, 1.0)
		var s := sin(TAU * f * t) + sin(TAU * f * harm * t) * 0.28
		out[i] = s * env * attack * gain
	return _fade_edges(out, 0.004)


# ===========================================================================
# 环境氛围合成
# ===========================================================================
func _synth_ambience(kind: String) -> PackedFloat32Array:
	var n := int(MIX_RATE * AMBIENCE_SECONDS)
	var out := PackedFloat32Array()
	out.resize(n)

	var drone_freq := 48.0
	var drone_amp := 0.20
	var hiss := 0.030
	var gust_amp := 2.0
	match kind:
		"menu":
			drone_freq = 58.0
			drone_amp = 0.16
			hiss = 0.024
			gust_amp = 1.6
		"calm":
			drone_freq = 52.0
			drone_amp = 0.18
			hiss = 0.026
			gust_amp = 1.8
		"tense":
			drone_freq = 41.0
			drone_amp = 0.26
			hiss = 0.036
			gust_amp = 2.2
		"finale":
			drone_freq = 34.5
			drone_amp = 0.34
			hiss = 0.046
			gust_amp = 3.0
		"collapse":
			drone_freq = 30.0
			drone_amp = 0.40
			hiss = 0.060
			gust_amp = 3.6
		_:
			pass

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var lp_a := 0.0
	var lp_b := 0.0
	var drone2_freq := drone_freq * 1.493
	for i: int in range(n):
		var white := rng.randf_range(-1.0, 1.0)
		# 两级低通滤波 → 风声
		lp_a = lp_a * (1.0 - hiss) + white * hiss
		lp_b = lp_b * 0.05 + lp_a * 0.95
		var t := float(i) / float(MIX_RATE)
		# 缓慢阵风包络
		var env := 0.55 + 0.45 * sin(TAU * 0.043 * t + 0.7) * sin(TAU * 0.017 * t)
		# 低频轰鸣（两个相近频率形成缓慢的拍频）
		var drone := sin(TAU * drone_freq * t) * drone_amp \
			+ sin(TAU * drone2_freq * t) * drone_amp * 0.35
		out[i] = lp_b * gust_amp * env + drone * (0.7 + 0.3 * sin(TAU * 0.021 * t))
	# 收尾渐入渐出，让循环点不爆音
	return _fade_edges(out, 0.45)


func _fade_edges(src: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var n := src.size()
	if n == 0:
		return src
	var k := mini(int(MIX_RATE * seconds), n / 2)
	if k <= 1:
		return _normalize(src)
	for i: int in range(k):
		var g := float(i) / float(k)
		src[i] = src[i] * g
		src[n - 1 - i] = src[n - 1 - i] * g
	return _normalize(src)


func _normalize(src: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for v: float in src:
		peak = maxf(peak, absf(v))
	if peak <= 0.0001:
		return src
	var k := 0.62 / peak
	for i: int in range(src.size()):
		src[i] = src[i] * k
	return src


func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = MIX_RATE
	s.stereo = false
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i: int in range(n):
		bytes.encode_s16(i * 2, int(round(clampf(samples[i], -1.0, 1.0) * 32000.0)))
	s.data = bytes
	if loop and n > 0:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	return s


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
