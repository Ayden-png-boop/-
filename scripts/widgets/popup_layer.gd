class_name PopupLayer
extends Control
## PopupLayer —— 剧情里的全屏弹窗（冰川报告 / 新闻 / IPCC 报告 / 倒计时预警）。
##
## 打开时压暗背景、逐行浮现内容，关闭后回调通知剧情页继续推进。

signal closed()

var _on_close: Callable = Callable()
var _panel: PanelContainer
var _lines_box: VBoxContainer
var _btn: Button
var _input_lock: float = 0.0
var _open: bool = false

## 快速模式：关闭时不等淡出动画，立即回调。见 StoryScreen.fast_mode。
var fast_mode: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)


func is_open() -> bool:
	return _open


func open(title: String, lines: Array, tone: String = "info",
		on_close: Callable = Callable()) -> void:
	_on_close = on_close
	_open = true
	visible = true
	set_process(true)
	_input_lock = 0.3
	_build(title, lines, tone)
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	if _panel != null:
		_panel.pivot_offset = Vector2.ZERO
		_panel.scale = Vector2(0.94, 0.94)
		var tw2 := create_tween()
		tw2.tween_property(_panel, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _tone_color(tone: String) -> Color:
	match tone:
		"danger":
			return GameDefs.C_DANGER
		"warn":
			return GameDefs.C_WARN
		"good":
			return GameDefs.C_COOP
		_:
			return GameDefs.C_ICE


func _build(title: String, lines: Array, tone: String) -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()

	var accent := _tone_color(tone)

	var scrim := ColorRect.new()
	scrim.color = Color(0.008, 0.024, 0.043, 0.82)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_bg_input)
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = UiKit.panel(Color(0.043, 0.098, 0.153, 0.985), 14, accent, 2, 0)
	_panel.custom_minimum_size = Vector2(700, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_panel)

	var margin := UiKit.margin(30, 26, 30, 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)

	var col := UiKit.vbox(14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var head := UiKit.hbox(11)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := UiKit.chip(_tone_tag(tone), accent, 14)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(badge)
	var tl := UiKit.label(title, 27, GameDefs.C_TEXT)
	tl.add_theme_font_override("font", UiKit.bold_font())
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tl)
	col.add_child(head)

	col.add_child(UiKit.hsep(Color(accent.r, accent.g, accent.b, 0.45), 1))
	col.add_child(UiKit.spacer(2))

	_lines_box = UiKit.vbox(11)
	_lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_lines_box)

	var shown := 0
	for ln: Variant in lines:
		var txt := String(ln)
		if txt.begins_with("🔥") or txt.begins_with("⚠"):
			var l := UiKit.wrapped(txt, 19, accent)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_lines_box.add_child(l)
		else:
			var row := UiKit.hbox(10)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var dot := ColorRect.new()
			dot.color = Color(accent.r, accent.g, accent.b, 0.85)
			dot.custom_minimum_size = Vector2(4, 4)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(dot)
			var l2 := UiKit.wrapped(txt, 19, Color("#cfe6f4"))
			l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l2)
			_lines_box.add_child(row)
		shown += 1

	# 逐行浮现
	for i: int in range(_lines_box.get_child_count()):
		var child: Control = _lines_box.get_child(i)
		child.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.10 + float(i) * 0.10)
		tw.tween_property(child, "modulate:a", 1.0, 0.24)

	col.add_child(UiKit.spacer(6))
	var footer := UiKit.hbox(10)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.alignment = BoxContainer.ALIGNMENT_END
	_btn = UiKit.primary_button("继续  ▸", 19, 44)
	_btn.custom_minimum_size = Vector2(160, 44)
	_btn.pressed.connect(_close)
	footer.add_child(_btn)
	col.add_child(footer)


func _tone_tag(tone: String) -> String:
	match tone:
		"danger":
			return "紧急"
		"warn":
			return "警告"
		"good":
			return "转机"
		_:
			return "简报"


func _process(delta: float) -> void:
	if _input_lock > 0.0:
		_input_lock = maxf(_input_lock - delta, 0.0)


func _on_bg_input(event: InputEvent) -> void:
	if _input_lock > 0.0:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_close()


func _input(event: InputEvent) -> void:
	if not _open or _input_lock > 0.0:
		return
	var hit := false
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER
				or k.keycode == KEY_KP_ENTER or k.keycode == KEY_ESCAPE):
			hit = true
	if hit:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if not _open:
		return
	_open = false
	if fast_mode:
		_teardown()
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(_teardown)


func _teardown() -> void:
	visible = false
	modulate.a = 1.0
	set_process(false)
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	closed.emit()
	if _on_close.is_valid():
		_on_close.call()
