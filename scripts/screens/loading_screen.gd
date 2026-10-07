extends Control
## 加载页 —— 启动后的第一屏。
##
## 一边用进度条交代「正在准备什么」，一边把作品的题眼先亮出来；
## 加载完成后再由玩家点击进入主菜单，避免音乐与画面在引擎预热期一起抖。
## 点击后进入主菜单。

const MAIN_MENU := "res://scenes/main_menu.tscn"

var _bg: BgArt
var _bar: ProgressBar
var _status: Label
var _hint: Label
var _pct: Label
var _progress: float = 0.0
var _ready_to_go: bool = false
var _steps: Array = []
var _step_index: int = 0
var _step_timer: float = 0.0
var _blink: float = 0.0
var _input_lock: float = 0.0


func _ready() -> void:
	UiKit.apply(self)
	_bg = BgArt.new()
	_bg.scene_key = "title"
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_bg.set_video("scene12c")
	_build()
	_steps = [
		"读取剧情数据…",
		"装载中文字形…",
		"合成冰原环境音…",
		"布置界面…",
	]
	_prepare()


func _prepare() -> void:
	var sd := get_node_or_null("/root/StoryData")
	if sd != null:
		sd.reload(false)


func _build() -> void:
	var margin := UiKit.margin(88, 0, 88, 0)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var row := UiKit.hbox(0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var left := UiKit.vbox(16)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(left)

	var badge := UiKit.chip("Ayden · 徐浚文　少年组作品", GameDefs.C_ICE, 14)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(badge)

	var spark := UiKit.label("❄", 34, GameDefs.C_ICE_DIM)
	left.add_child(spark)

	var title := UiKit.label("冰川信使", 76, GameDefs.C_TEXT)
	title.add_theme_font_override("font", UiKit.bold_font())
	left.add_child(title)

	var sub := UiKit.label("斑头雁的 2040", 32, GameDefs.C_ICE)
	left.add_child(sub)

	left.add_child(UiKit.spacer(6))

	var line := ColorRect.new()
	line.color = GameDefs.C_LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(line)

	left.add_child(UiKit.spacer(6))

	var meta := get_node_or_null("/root/StoryData")
	var blurb := "一只能飞越珠峰的候鸟，和一场正在消失的家园。"
	if meta != null and meta.meta is Dictionary and Dictionary(meta.meta).has("blurb"):
		blurb = String(Dictionary(meta.meta)["blurb"])
	left.add_child(UiKit.block([UiKit.wrapped(blurb, 19, Color("#b7d4e6"))], 560))

	var right := Control.new()
	right.custom_minimum_size = Vector2(280, 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	# ---- 底部进度区 ----
	var bottom := UiKit.margin(88, 0, 88, 46)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -132
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)

	var bcol := UiKit.vbox(9)
	bcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bcol)

	var srow := UiKit.hbox(10)
	srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status = UiKit.label("正在起飞…", 17, GameDefs.C_MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(_status)
	_pct = UiKit.label("0%", 17, GameDefs.C_ICE)
	srow.add_child(_pct)
	bcol.add_child(srow)

	_bar = ProgressBar.new()
	_bar.min_value = 0
	_bar.max_value = 100
	_bar.value = 0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.add_theme_stylebox_override("background",
		UiKit.box(Color(0.03, 0.07, 0.12, 0.85), 4, GameDefs.C_LINE, 1))
	_bar.add_theme_stylebox_override("fill", UiKit.box(GameDefs.C_ICE, 4))
	bcol.add_child(_bar)

	_hint = UiKit.label("正在准备…", 17, GameDefs.C_ICE_DIM)
	_hint.visible = false
	bcol.add_child(_hint)


func _process(delta: float) -> void:
	if _input_lock > 0.0:
		_input_lock = maxf(_input_lock - delta, 0.0)

	if not _ready_to_go:
		# 分段推进，让加载过程有可读的叙事感
		if _step_index < _steps.size():
			_step_timer += delta
			var seg := 1.0 / float(_steps.size())
			var local := clampf(_step_timer / 0.34, 0.0, 1.0)
			_progress = maxf(_progress, (float(_step_index) + local) * seg)
			_status.text = String(_steps[_step_index])
			if local >= 1.0:
				_step_index += 1
				_step_timer = 0.0
		else:
			_progress = 1.0
		_bar.value = _progress * 100.0
		_pct.text = "%d%%" % int(round(_progress * 100.0))
		if _step_index >= _steps.size():
			_ready_to_go = true
			_status.text = _done_text()
			_hint.visible = true
		return

	# 呼吸式提示
	_blink += delta
	_hint.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_blink * 3.2))


func _done_text() -> String:
	var sd := get_node_or_null("/root/StoryData")
	if sd != null and not bool(sd.ok):
		return "剧情数据有 %d 处错误（详见控制台）" % Array(sd.errors).size()
	return "准备就绪"


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_go or _input_lock > 0.0:
		return
	var go := false
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			go = true
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			go = true
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			go = true
	if go:
		_go()


func _go() -> void:
	if _input_lock > 0.0:
		return
	_input_lock = 1.0
	var am := get_node_or_null("/root/AudioMgr")
	if am != null:
		am.play_sfx("confirm")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.28)
	tw.tween_callback(func() -> void:
		var nav := get_node_or_null("/root/Navigator")
		if nav != null:
			nav.reset()
			nav.go(MAIN_MENU))
