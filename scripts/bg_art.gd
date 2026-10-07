class_name BgArt
extends Control
## BgArt —— 场景背景。既支持 res://assets/bg/<key>.png 的真实插画，
## 也能在没有任何图片素材时用程序化绘制（天空渐变 + 多层山脊 + 极光 + 粒子）
## 兜出一个可用的画面。这样工程永远不会出现「黑屏」。
##
## 还内置了两种演出效果：闪白（flash）与震屏（shake），剧情 JSON 里
## 用 fx 字段点名即可。

const BG_DIR := "res://assets/bg/"
const BG_EXTS := [".png", ".jpg", ".jpeg", ".webp"]

## 每个场景的画面配方
static var PRESETS := {
	"title": {
		"sky": ["#04101d", "#0d3350", "#2d6f92"],
		"mode": "mountain", "haze": "#8fd0ef", "layers": 4,
		"ridge": 0.20, "aurora": 0.85, "particles": "snow", "density": 1.15,
		"sun": "#d8f4ff", "sun_pos": Vector2(0.70, 0.26), "vignette": 0.62,
			"tex_dim": 0.3,
	},
	"ch1": {
		"sky": ["#041426", "#12496f", "#59a8cc"],
		"mode": "mountain", "haze": "#a9dcf5", "layers": 5,
		"ridge": 0.24, "aurora": 0.35, "particles": "snow", "density": 0.85,
		"sun": "#e8f9ff", "sun_pos": Vector2(0.76, 0.24), "vignette": 0.5,
			"tex_dim": 0.3,
	},
	"ch2": {
		"sky": ["#060b18", "#152148", "#3f4f86"],
		"mode": "ruins", "haze": "#8fa4d8", "layers": 4,
		"ridge": 0.14, "aurora": 0.25, "particles": "snow", "density": 0.5,
		"sun": "#ffeec4", "sun_pos": Vector2(0.22, 0.20), "vignette": 0.7,
			"tex_dim": 0.22,
	},
	"ch3": {
		"sky": ["#2a1608", "#7a4413", "#d9973f"],
		"mode": "skyline", "haze": "#ffd9a0", "layers": 4,
		"ridge": 0.10, "aurora": 0.0, "particles": "heat", "density": 0.8,
		"sun": "#fff4d6", "sun_pos": Vector2(0.60, 0.30), "vignette": 0.4,
			"tex_dim": 0.42,
	},
	"ch4": {
		"sky": ["#0a1723", "#2b4a63", "#7d94a6"],
		"mode": "mountain", "haze": "#cfe4ee", "layers": 5,
		"ridge": 0.30, "aurora": 0.15, "particles": "spray", "density": 1.0,
		"sun": "#eef7ff", "sun_pos": Vector2(0.34, 0.22), "vignette": 0.55,
			"tex_dim": 0.34,
	},
	"ch5": {
		"sky": ["#050c16", "#0f2637", "#39627d"],
		"mode": "ice", "haze": "#b7dcee", "layers": 5,
		"ridge": 0.22, "aurora": 0.55, "particles": "snow", "density": 1.4,
		"sun": "#cfe9ff", "sun_pos": Vector2(0.50, 0.30), "vignette": 0.72,
			"tex_dim": 0.3,
	},
	"ending_good": {
		"sky": ["#07203a", "#1d6c8a", "#a9e7f2"],
		"mode": "mountain", "haze": "#dff7ff", "layers": 4,
		"ridge": 0.18, "aurora": 0.7, "particles": "snow", "density": 0.7,
		"sun": "#ffffff", "sun_pos": Vector2(0.62, 0.24), "vignette": 0.42,
			"tex_dim": 0.26,
	},
	"ending_bad": {
		"sky": ["#0b0708", "#3a1414", "#8a2f22"],
		"mode": "flood", "haze": "#ffb08a", "layers": 4,
		"ridge": 0.16, "aurora": 0.0, "particles": "ash", "density": 1.0,
		"sun": "#ffd0a0", "sun_pos": Vector2(0.30, 0.34), "vignette": 0.78,
			"tex_dim": 0.18,
	},
}

var scene_key: String = "ch1"
var shake_offset: Vector2 = Vector2.ZERO
var dim: float = 0.0                  ## 额外压暗（过场 / 弹窗时用）

var _preset: Dictionary = {}
var _tex: Texture2D = null
var _snow: Array = []
var _t: float = 0.0
var _flash_col: Color = Color(1, 1, 1, 0)
var _rng := RandomNumberGenerator.new()

static var _tex_cache: Dictionary = {}
static var _grad_cache: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_scene(scene_key)


func set_scene(key: String) -> void:
	scene_key = key
	_preset = PRESETS.get(key, PRESETS["ch1"])
	_tex = _load_texture(key)
	_rebuild_particles()
	queue_redraw()


func _load_texture(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	for ext: String in BG_EXTS:
		var p := BG_DIR + key + ext
		if ResourceLoader.exists(p):
			var t: Resource = load(p)
			if t is Texture2D:
				_tex_cache[key] = t
				return t
	_tex_cache[key] = null
	return null


func _rebuild_particles() -> void:
	_snow.clear()
	var kind := String(_preset.get("particles", "snow"))
	if kind == "none":
		return
	var density := float(_preset.get("density", 1.0))
	var count := int(90.0 * density)
	_rng.seed = hash(scene_key)
	for i: int in range(count):
		# 雪花尺寸整体调大（半径 2.4~7.0），并让大雪花更亮、下落更有分量，
		# 形成「近处大、远处小」的层次感。
		var rad := _rng.randf_range(2.4, 7.0)
		var heft := 0.55 + rad * 0.15
		_snow.append({
			"x": _rng.randf(),
			"y": _rng.randf(),
			"r": rad,
			"vy": _rng.randf_range(0.013, 0.052) * heft * (1.0 + density * 0.4),
			"vx": _rng.randf_range(-0.012, 0.012),
			"ph": _rng.randf() * TAU,
			"a": _rng.randf_range(0.34, 0.94),
		})


func _process(delta: float) -> void:
	_t += delta
	var H := maxf(size.y, 1.0)
	for p: Dictionary in _snow:
		p["y"] = float(p["y"]) + float(p["vy"]) * delta
		p["x"] = float(p["x"]) + (float(p["vx"]) + sin(_t * 0.7 + float(p["ph"])) * 0.006) * delta
		if float(p["y"]) > 1.08:
			p["y"] = -0.06
		if float(p["x"]) > 1.06:
			p["x"] = -0.04
		elif float(p["x"]) < -0.06:
			p["x"] = 1.04
	shake_offset = shake_offset.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))
	queue_redraw()
	# H 只是为了让编译器知道 size 参与了布局，避免未使用告警
	if H < 0.0:
		pass


# ===========================================================================
# 绘制
# ===========================================================================
func _draw() -> void:
	var R := Rect2(Vector2.ZERO, size)
	if R.size.x <= 1.0 or R.size.y <= 1.0:
		return
	draw_set_transform(shake_offset, 0.0, Vector2.ONE)

	if _tex != null:
		_draw_cover(_tex, R)
		# 真实照片底色需要压暗一层，保证前景 UI 文本的可读性
		var tex_dim := float(_preset.get("tex_dim", 0.0))
		if tex_dim > 0.001:
			draw_rect(R, Color(0.0, 0.0, 0.0, clampf(tex_dim, 0.0, 0.95)))
	else:
		_draw_sky(R)
		_draw_layers(R)

	if dim > 0.001:
		draw_rect(R, Color(0.0, 0.0, 0.0, clampf(dim, 0.0, 0.95)))
	_draw_overlays(R)
	_draw_particles(R)

	if _flash_col.a > 0.001:
		draw_rect(R, _flash_col)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 等比铺满（cover）：不拉伸变形，多余部分裁掉
func _draw_cover(tex: Texture2D, R: Rect2) -> void:
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var scale := maxf(R.size.x / ts.x, R.size.y / ts.y)
	var dst := Vector2(ts.x * scale, ts.y * scale)
	var pos := R.position + (R.size - dst) * 0.5
	draw_texture_rect(tex, Rect2(pos, dst), false)


func _draw_sky(R: Rect2) -> void:
	var key := scene_key + "|sky"
	var gt: GradientTexture2D = _grad_cache.get(key, null)
	if gt == null:
		var cols: Array = _preset.get("sky", ["#04101d", "#0d3350", "#2d6f92"])
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([
			Color(String(cols[0])), Color(String(cols[1])), Color(String(cols[2]))])
		gt = GradientTexture2D.new()
		gt.gradient = g
		gt.width = 8
		gt.height = 256
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		_grad_cache[key] = gt
	draw_texture_rect(gt, R, false)

	# 低垂的太阳 / 月亮
	var sun_col := Color(String(_preset.get("sun", "#ffffff")))
	var sp: Vector2 = _preset.get("sun_pos", Vector2(0.7, 0.28))
	var c := Vector2(R.position.x + R.size.x * sp.x, R.position.y + R.size.y * sp.y)
	var radius := R.size.y * 0.055
	for i: int in range(6):
		var k := float(i) / 5.0
		draw_circle(c, radius * (1.0 + k * 2.6), Color(sun_col.r, sun_col.g, sun_col.b,
			(1.0 - k) * 0.055))


func _draw_layers(R: Rect2) -> void:
	var mode := String(_preset.get("mode", "mountain"))
	var n := int(_preset.get("layers", 5))
	var haze := Color(String(_preset.get("haze", "#9fd2ee")))
	var bottom := R.position.y + R.size.y + 4.0
	var base_rng := RandomNumberGenerator.new()
	base_rng.seed = hash(scene_key + "|" + mode)

	for i: int in range(n):
		var depth := float(i) / float(maxi(n - 1, 1))            # 0=最远 1=最近
		var y_base := R.size.y * (0.46 + depth * 0.46)
		var amp := R.size.y * float(_preset.get("ridge", 0.2)) * (0.5 + depth * 0.9)
		var col := haze.lerp(GameDefs.C_INK, 0.30 + depth * 0.68)
		col.a = 0.88 + depth * 0.12
		var top_pts: PackedVector2Array
		match mode:
			"skyline":
				top_pts = _skyline_line(R, y_base, amp, base_rng, depth)
			"ruins":
				top_pts = _ruins_line(R, y_base, amp, base_rng, depth)
			_:
				top_pts = _ridge_line(R, y_base, amp, base_rng, depth, mode == "ice")
		_fill_band(top_pts, bottom, col)


## 把一条「天际线」折线填到画面底部。
## 每个梯形拆成两个三角形绘制：三角形永远能三角化成功，
## 不会触发 draw_polygon 的「Invalid polygon data」。
func _fill_band(top_pts: PackedVector2Array, bottom_y: float, col: Color) -> void:
	if top_pts.size() < 2:
		return
	var cols := PackedColorArray([col, col, col])
	for i: int in range(top_pts.size() - 1):
		var a := top_pts[i]
		var b := top_pts[i + 1]
		if absf(b.x - a.x) < 0.01:
			continue
		var b2 := Vector2(b.x, bottom_y)
		var a2 := Vector2(a.x, bottom_y)
		draw_colored_polygon(PackedVector2Array([a, b, b2]), col)
		draw_colored_polygon(PackedVector2Array([a, b2, a2]), col)
	# cols 仅用于保持与 draw_colored_polygon 的色彩语义一致
	if cols.size() < 0:
		pass


func _ridge_line(R: Rect2, y_base: float, amp: float, rng: RandomNumberGenerator,
		depth: float, jagged: bool) -> PackedVector2Array:
	var segs := 26 + int(depth * 16.0)
	var pts := PackedVector2Array()
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var ph3 := rng.randf() * TAU
	var f1 := 1.0 + depth * 0.9
	var f2 := 2.6 + depth * 1.6
	var f3 := 5.2 + depth * 3.4
	for i: int in range(segs + 1):
		var u := float(i) / float(segs)
		var x := R.position.x + R.size.x * u
		var h := sin(u * TAU * f1 + ph1) * 0.55 \
			+ sin(u * TAU * f2 + ph2) * 0.28 \
			+ sin(u * TAU * f3 + ph3) * 0.17
		if jagged:
			h += absf(sin(u * TAU * (7.0 + depth * 6.0) + ph2)) * 0.22 - 0.11
		pts.append(Vector2(x, y_base - amp * h))
	return pts


func _skyline_line(R: Rect2, y_base: float, amp: float,
		rng: RandomNumberGenerator, depth: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := R.position.x - 10.0
	var right := R.position.x + R.size.x + 10.0
	while x < right:
		var w := maxf(rng.randf_range(R.size.x * 0.022, R.size.x * 0.062), 6.0)
		var h := amp * rng.randf_range(0.35, 1.9) * (0.6 + depth * 0.7)
		var top := y_base - h
		pts.append(Vector2(x, y_base))
		pts.append(Vector2(x, top))
		pts.append(Vector2(x + w, top))
		pts.append(Vector2(x + w, y_base))
		x += w + rng.randf_range(1.0, R.size.x * 0.012)
	pts.append(Vector2(right, y_base))
	return pts


func _ruins_line(R: Rect2, y_base: float, amp: float,
		rng: RandomNumberGenerator, depth: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var segs := 30
	var block := float(int(rng.randf() * 3.0))
	for i: int in range(segs + 1):
		var u := float(i) / float(segs)
		var x := R.position.x + R.size.x * u
		# 断墙：方波状的残垣
		var step := 0.0
		if fmod(u * 9.0 + block, 1.0) > 0.55:
			step = amp * 0.5
		pts.append(Vector2(x, y_base + sin(u * TAU * 2.4) * amp * 0.20 - step))
	return pts


func _draw_overlays(R: Rect2) -> void:
	# 极光：几条随时间缓慢摆动的半透明丝带（逐段画四边形，保证三角化安全）
	var aurora := float(_preset.get("aurora", 0.0))
	if aurora <= 0.01:
		return
	var palette: Array = [
		Color(0.35, 1.0, 0.75), Color(0.45, 0.75, 1.0), Color(0.65, 0.55, 1.0)]
	var segs := 40
	for b: int in range(3):
		var col: Color = palette[b]
		var y0 := R.size.y * (0.10 + float(b) * 0.05)
		for i: int in range(segs):
			var u0 := float(i) / float(segs)
			var u1 := float(i + 1) / float(segs)
			var x0 := R.position.x + R.size.x * u0
			var x1 := R.position.x + R.size.x * u1
			var yt0 := y0 + sin(u0 * TAU * 1.3 + _t * 0.16 + float(b)) * R.size.y * 0.035 \
				+ sin(u0 * TAU * 3.4 - _t * 0.11) * R.size.y * 0.015
			var yt1 := y0 + sin(u1 * TAU * 1.3 + _t * 0.16 + float(b)) * R.size.y * 0.035 \
				+ sin(u1 * TAU * 3.4 - _t * 0.11) * R.size.y * 0.015
			var thick := R.size.y * 0.16
			var edge := sin(u0 * PI)
			var a := aurora * 0.075 * (0.35 + 0.65 * edge)
			var ca := Color(col.r, col.g, col.b, a)
			var cb := Color(col.r, col.g, col.b, a * 0.12)
			var p0 := Vector2(x0, yt0)
			var p1 := Vector2(x1, yt1)
			var p2 := Vector2(x1, yt1 + thick)
			var p3 := Vector2(x0, yt0 + thick)
			draw_polygon(PackedVector2Array([p0, p1, p2]),
				PackedColorArray([ca, ca, cb]))
			draw_polygon(PackedVector2Array([p0, p2, p3]),
				PackedColorArray([ca, cb, cb]))


func _draw_particles(R: Rect2) -> void:
	var kind := String(_preset.get("particles", "snow"))
	if kind == "none" or _snow.is_empty():
		return
	var base := Color(1, 1, 1)
	var glow := 1.0
	match kind:
		"ash":
			base = Color(1.0, 0.72, 0.55)
			glow = 0.7
		"spray":
			base = Color(0.90, 0.97, 1.0)
			glow = 1.15
		"heat":
			base = Color(1.0, 0.90, 0.62)
			glow = 0.6
		_:
			base = Color(0.94, 0.99, 1.0)
			glow = 1.0
	for p: Dictionary in _snow:
		var pos := Vector2(R.position.x + float(p["x"]) * R.size.x,
			R.position.y + float(p["y"]) * R.size.y)
		var a := float(p["a"]) * glow
		var r := float(p["r"]) * (0.8 if kind == "heat" else 1.0)
		# 大雪花画「柔光外圈 + 实心核心」两层，边缘才不会像硬圆点
		draw_circle(pos, r * 1.6, Color(base.r, base.g, base.b, clampf(a * 0.20, 0.0, 1.0)))
		draw_circle(pos, r, Color(base.r, base.g, base.b, clampf(a, 0.0, 1.0)))
	# 底部渐隐，让下方文字浮层更易读
	var key := scene_key + "|vig" + str(snapshot_vignette())
	var gt: GradientTexture2D = _grad_cache.get(key, null)
	if gt == null:
		var g := Gradient.new()
		var v := float(_preset.get("vignette", 0.5))
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([
			Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, v)])
		gt = GradientTexture2D.new()
		gt.gradient = g
		gt.width = 8
		gt.height = 64
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		_grad_cache[key] = gt
	draw_texture_rect(gt, R, false)


func snapshot_vignette() -> int:
	return int(float(_preset.get("vignette", 0.5)) * 100.0)


# ===========================================================================
# 演出效果
# ===========================================================================
func flash(color: Color = Color.WHITE, duration: float = 0.35) -> void:
	var tw := create_tween()
	_flash_col = Color(color.r, color.g, color.b, 0.85)
	tw.tween_method(_set_flash, 0.85, 0.0, duration)


func _set_flash(a: float) -> void:
	_flash_col.a = a
	queue_redraw()


func shake(strength: float = 12.0, duration: float = 0.45) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n := maxi(int(duration / 0.03), 3)
	var tw := create_tween()
	for i: int in range(n):
		var k := 1.0 - float(i) / float(n)
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * strength * k
		tw.tween_callback(func() -> void:
			shake_offset = off)


## 剧情 JSON 里 fx 字段的入口
func play_fx(fx: String) -> void:
	match fx:
		"shake":
			shake(14.0, 0.5)
		"bigshake":
			shake(26.0, 0.8)
		"flash":
			flash(Color(1, 1, 1), 0.35)
		"flashred":
			flash(GameDefs.C_DANGER, 0.45)
		"flashice":
			flash(GameDefs.C_ICE, 0.5)
		_:
			pass
