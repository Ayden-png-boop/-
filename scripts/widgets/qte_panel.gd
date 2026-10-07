class_name QtePanel
extends Control
## QtePanel —— 限时动作段（例如「30 秒内完成 3 次精准撞击」）。
##
## 玩法：光标在轨道上来回扫动，在它进入高亮区间时按下空格 / 点击即算命中。
## 每命中一次，轨道变快、区间变窄，直到完成目标次数或时间耗尽。

signal finished(success: bool)

var _active: bool = false
var _duration: float = 30.0
var _time_left: float = 30.0
var _need: int = 3
var _hits: int = 0
var _misses: int = 0
var _cursor: float = 0.0
var _dir: float = 1.0
var _speed: float = 0.62
var _zone_c: float = 0.5
var _zone_h: float = 0.085
var _flash: float = 0.0
var _flash_col: Color = GameDefs.C_COOP
var _result: int = 0                 ## 0=进行中 1=成功 -1=失败
var _input_lock: float = 0.0
var _rng := RandomNumberGenerator.new()
var _on_done: Callable = Callable()

var _title: Label
var _timer: Label
var _hits_l: Label
var _hint: Label
var _verdict: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	_build()


func _build() -> void:
	_title = UiKit.label("", 30, GameDefs.C_ICE, HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_font_override("font", UiKit.bold_font())
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 68
	_title.offset_bottom = 116
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_timer = UiKit.label("30.0", 46, GameDefs.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_timer.add_theme_font_override("font", UiKit.bold_font())
	_timer.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_timer.offset_top = 118
	_timer.offset_bottom = 182
	_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_timer)

	_hits_l = UiKit.label("", 20, GameDefs.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_hits_l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hits_l.offset_top = 186
	_hits_l.offset_bottom = 216
	_hits_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hits_l)

	_hint = UiKit.label("按 空格 或 点击 撞击", 19, GameDefs.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -132
	_hint.offset_bottom = -102
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	_verdict = UiKit.label("", 40, GameDefs.C_COOP, HORIZONTAL_ALIGNMENT_CENTER)
	_verdict.add_theme_font_override("font", UiKit.bold_font())
	_verdict.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_verdict.offset_left = -320
	_verdict.offset_right = 320
	_verdict.offset_top = -40
	_verdict.offset_bottom = 40
	_verdict.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_verdict.visible = false
	add_child(_verdict)


func is_active() -> bool:
	return _active


func start(prompt: String, config: Dictionary, on_done: Callable = Callable()) -> void:
	_on_done = on_done
	_duration = maxf(float(config.get("duration", 30.0)), 3.0)
	_time_left = _duration
	_need = maxi(int(config.get("targets", 3)), 1)
	_hits = 0
	_misses = 0
	_cursor = 0.12
	_dir = 1.0
	_speed = 0.55
	_zone_h = 0.10
	_rng.randomize()
	_zone_c = _rng.randf_range(0.30, 0.70)
	_result = 0
	_input_lock = 0.45
	_active = true
	visible = true
	modulate.a = 0.0
	set_process(true)
	_title.text = prompt
	_verdict.visible = false
	_hits_l.text = _hits_text()
	_timer.text = "%.1f" % _time_left
	_hint.text = "按 空格 或 点击 撞击 — 光标进入高亮区才算命中"
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	queue_redraw()


func _hits_text() -> String:
	var s := "命中 "
	for i: int in range(_need):
		s += "●" if i < _hits else "○"
	s += "  %d/%d" % [_hits, _need]
	if _misses > 0:
		s += "　落空 %d" % _misses
	return s


func _process(delta: float) -> void:
	if not _active:
		return
	if _input_lock > 0.0:
		_input_lock = maxf(_input_lock - delta, 0.0)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.6, 0.0)
	if _result != 0:
		queue_redraw()
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_timer.text = "%.1f" % _time_left
	_timer.add_theme_color_override("font_color",
		GameDefs.C_DANGER if _time_left < 6.0 else GameDefs.C_TEXT)
	_cursor += _dir * _speed * delta
	if _cursor >= 1.0:
		_cursor = 1.0
		_dir = -1.0
	elif _cursor <= 0.0:
		_cursor = 0.0
		_dir = 1.0
	if _time_left <= 0.0:
		_finish(false)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not _active or _result != 0 or _input_lock > 0.0:
		return
	var strike := false
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER
				or k.keycode == KEY_KP_ENTER or k.keycode == KEY_J):
			strike = true
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			strike = true
	if strike:
		get_viewport().set_input_as_handled()
		_strike()


func _strike() -> void:
	var a := get_node_or_null("/root/AudioMgr")
	if absf(_cursor - _zone_c) <= _zone_h:
		_hits += 1
		_flash = 1.0
		_flash_col = GameDefs.C_COOP
		_speed = minf(_speed * 1.22, 2.4)
		_zone_h = maxf(_zone_h * 0.84, 0.042)
		_zone_c = _rng.randf_range(_zone_h + 0.04, 1.0 - _zone_h - 0.04)
		if a != null:
			a.play_sfx("confirm")
		if _hits >= _need:
			_finish(true)
	else:
		_misses += 1
		_flash = 1.0
		_flash_col = GameDefs.C_DANGER
		_time_left = maxf(_time_left - 4.0, 0.05)
		if a != null:
			a.play_sfx("fail")
	_hits_l.text = _hits_text()


func _finish(success: bool) -> void:
	if _result != 0:
		return
	_result = 1 if success else -1
	_verdict.visible = true
	_verdict.text = "撞击成功！" if success else "时间耗尽"
	_verdict.add_theme_color_override("font_color",
		GameDefs.C_COOP if success else GameDefs.C_DANGER)
	var a := get_node_or_null("/root/AudioMgr")
	if a != null:
		a.play_sfx("success" if success else "fail")
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		_active = false
		visible = false
		set_process(false)
		finished.emit(success)
		if _on_done.is_valid():
			_on_done.call(success))


# ===========================================================================
# 绘制
# ===========================================================================
func _track_rect() -> Rect2:
	var mx := 110.0
	var h := 46.0
	return Rect2(Vector2(mx, size.y * 0.5 - h * 0.5), Vector2(size.x - mx * 2.0, h))


func _draw() -> void:
	var R := Rect2(Vector2.ZERO, size)
	draw_rect(R, Color(0.008, 0.024, 0.043, 0.90))

	var track := _track_rect()
	if track.size.x <= 10.0:
		return

	# 轨道底
	draw_style_box(UiKit.box(Color(0.02, 0.05, 0.09, 0.95), 10, GameDefs.C_LINE, 1), track)

	# 高亮命中区
	var zx := track.position.x + ( _zone_c - _zone_h) * track.size.x
	var zw := _zone_h * 2.0 * track.size.x
	var zone_col: Color = GameDefs.C_COOP if _result == 0 else GameDefs.C_MUTED
	zone_col.a = 0.30 + 0.16 * sin(_t_phase())
	draw_style_box(UiKit.box(zone_col, 8, Color(zone_col.r, zone_col.g, zone_col.b, 0.9), 2),
		Rect2(Vector2(zx, track.position.y - 6.0), Vector2(zw, track.size.y + 12.0)))

	# 光标
	var cx := track.position.x + _cursor * track.size.x
	var ccol: Color = GameDefs.C_ICE
	if _flash > 0.0:
		ccol = _flash_col.lerp(Color.WHITE, _flash * 0.6)
	draw_rect(Rect2(Vector2(cx - 2.5, track.position.y - 18.0), Vector2(5, track.size.y + 36.0)),
		ccol)
	draw_circle(Vector2(cx, track.position.y - 24.0), 7.0, ccol)
	draw_circle(Vector2(cx, track.position.y + track.size.y + 24.0), 7.0, ccol)

	# 进度刻度
	var seg := track.size.x / float(maxi(_need, 1))
	for i: int in range(_need):
		var x := track.position.x + seg * (float(i) + 0.5)
		var done := i < _hits
		draw_circle(Vector2(x, track.position.y + track.size.y + 56.0), 6.0,
			GameDefs.C_COOP if done else Color(0.20, 0.32, 0.42, 0.9))

	# 剩余时间条
	var frac := clampf(_time_left / maxf(_duration, 0.001), 0.0, 1.0)
	var bar := Rect2(Vector2(track.position.x, track.position.y - 44.0),
		Vector2(track.size.x, 7.0))
	draw_style_box(UiKit.box(Color(0.05, 0.10, 0.16, 0.9), 4, Color(0.12, 0.22, 0.30), 1), bar)
	var tcol: Color = GameDefs.C_DANGER if frac < 0.22 else GameDefs.C_ICE
	draw_style_box(UiKit.box(tcol, 4),
		Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)))

	if _flash > 0.0:
		draw_rect(R, Color(_flash_col.r, _flash_col.g, _flash_col.b, _flash * 0.14))


func _t_phase() -> float:
	return float(Time.get_ticks_msec()) * 0.003
