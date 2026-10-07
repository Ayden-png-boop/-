extends Control
## 设置页 —— 文字速度、自动推进、字号、音量、全屏与存档管理。
##
## 所有改动即时写入 GameState 并持久化到 user://glacier_settings.cfg，
## 下次启动自动生效。

var _bg: BgArt
var _speed_row: HBoxContainer
var _font_row: HBoxContainer
var _auto_row: HBoxContainer
var _bgm_row: HBoxContainer
var _sfx_row: HBoxContainer
var _voice_row: HBoxContainer
var _fs_btn: Button
var _auto_toggle: Button
var _voice_toggle: Button
var _type_toggle: Button
var _save_note: Label
var _confirm_card: Control


func _ready() -> void:
	UiKit.apply(self)
	_bg = BgArt.new()
	_bg.scene_key = "ch2"
	_bg.dim = 0.25
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_build()


func _build() -> void:
	var root := UiKit.margin(44, 28, 44, 24)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var col := UiKit.vbox(14)
	root.add_child(col)

	var head := UiKit.hbox(14)
	var back := UiKit.ghost_button("◂ 返回", 17, 40)
	back.custom_minimum_size = Vector2(104, 40)
	back.pressed.connect(_on_back)
	head.add_child(back)
	var t := UiKit.label("设置", 32, GameDefs.C_TEXT)
	t.add_theme_font_override("font", UiKit.bold_font())
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	col.add_child(head)

	col.add_child(UiKit.hsep(GameDefs.C_LINE, 1))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var card := UiKit.panel(Color(0.031, 0.071, 0.114, 0.95), 14, GameDefs.C_LINE, 1, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)
	var m := UiKit.margin(28, 22, 28, 22)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(m)
	var v := UiKit.vbox(16)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)

	var gs := get_node_or_null("/root/GameState")
	var speed := float(gs.text_speed) if gs != null else 55.0
	var fscale := float(gs.font_scale) if gs != null else 1.0
	var bgm := float(gs.bgm_volume) if gs != null else 0.55
	var sfx := float(gs.sfx_volume) if gs != null else 0.7
	var delay := float(gs.auto_delay) if gs != null else 2.2

	_speed_row = _slider_row("文字速度", "字 / 秒", 12.0, 140.0, 1.0, speed,
		func(val: float) -> void:
			var g := get_node_or_null("/root/GameState")
			if g != null:
				g.text_speed = val
				g.save_settings())
	v.add_child(_speed_row)

	_font_row = _slider_row("正文字号", "倍", 0.85, 1.35, 0.05, fscale,
		func(val: float) -> void:
			var g := get_node_or_null("/root/GameState")
			if g != null:
				g.font_scale = val
				g.save_settings())
	v.add_child(_font_row)

	_auto_row = _slider_row("自动推进间隔", "秒", 0.8, 4.5, 0.1, delay,
		func(val: float) -> void:
			var g := get_node_or_null("/root/GameState")
			if g != null:
				g.auto_delay = val
				g.save_settings())
	v.add_child(_auto_row)

	v.add_child(UiKit.hsep(GameDefs.C_LINE, 1))

	_bgm_row = _slider_row("环境音音量", "", 0.0, 1.0, 0.05, bgm,
		func(val: float) -> void:
			var g := get_node_or_null("/root/GameState")
			if g != null:
				g.bgm_volume = val
				g.save_settings())
	v.add_child(_bgm_row)

	_sfx_row = _slider_row("音效音量", "", 0.0, 1.0, 0.05, sfx,
		func(val: float) -> void:
			var g := get_node_or_null("/root/GameState")
			if g != null:
				g.sfx_volume = val
				g.save_settings())
	v.add_child(_sfx_row)

	var voice := float(gs.voice_volume) if gs != null else 0.9
	_voice_row = _slider_row("配音音量", "", 0.0, 1.0, 0.05, voice,
		func(val: float) -> void:
			var g := get_node_or_null("/root/GameState")
			if g != null:
				g.voice_volume = val
				g.save_settings())
	v.add_child(_voice_row)

	v.add_child(UiKit.hsep(GameDefs.C_LINE, 1))

	# 开关行
	var toggles := UiKit.hbox(12)
	toggles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fs_btn = UiKit.button("", 18, 46)
	_fs_btn.custom_minimum_size = Vector2(220, 46)
	_fs_btn.pressed.connect(_toggle_fullscreen)
	toggles.add_child(_fs_btn)
	_auto_toggle = UiKit.button("", 18, 46)
	_auto_toggle.custom_minimum_size = Vector2(220, 46)
	_auto_toggle.pressed.connect(_toggle_auto)
	toggles.add_child(_auto_toggle)
	var b_wipe := UiKit.ghost_button("清除存档", 18, 46)
	b_wipe.custom_minimum_size = Vector2(180, 46)
	b_wipe.pressed.connect(_ask_wipe)
	toggles.add_child(b_wipe)
	v.add_child(toggles)

	var toggles2 := UiKit.hbox(12)
	toggles2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voice_toggle = UiKit.button("", 18, 46)
	_voice_toggle.custom_minimum_size = Vector2(220, 46)
	_voice_toggle.pressed.connect(_toggle_voice)
	toggles2.add_child(_voice_toggle)
	_type_toggle = UiKit.button("", 18, 46)
	_type_toggle.custom_minimum_size = Vector2(220, 46)
	_type_toggle.pressed.connect(_toggle_typing)
	toggles2.add_child(_type_toggle)
	var b_replay := UiKit.ghost_button("试听配音", 18, 46)
	b_replay.custom_minimum_size = Vector2(180, 46)
	b_replay.pressed.connect(_preview_voice)
	toggles2.add_child(b_replay)
	v.add_child(toggles2)

	_save_note = UiKit.wrapped("", 15, GameDefs.C_MUTED)
	v.add_child(_save_note)

	v.add_child(UiKit.spacer(4))
	var tip := UiKit.wrapped(
		"提示：按 F11 可在任何界面切换全屏；剧情中按 空格 / 回车 / 点击空白处 推进文本；ESC 返回主菜单。剧情文本配有中文旁白与逐字敲击音，可在此单独关闭。",
		15, Color(0.56, 0.68, 0.78))
	v.add_child(tip)

	_refresh_labels()


func _slider_row(label: String, unit: String, mn: float, mx: float, step: float,
		value: float, on_change: Callable) -> HBoxContainer:
	var row := UiKit.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(label, 18, GameDefs.C_TEXT)
	l.custom_minimum_size = Vector2(150, 26)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)

	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 26)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)

	var vl := UiKit.label("", 17, GameDefs.C_ICE, HORIZONTAL_ALIGNMENT_RIGHT)
	vl.custom_minimum_size = Vector2(110, 26)
	vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vl)

	var fmt: Callable = func(val: float) -> String:
		var txt := "%.2f" % val if step < 0.5 else "%.0f" % val
		return txt + (" " + unit if unit != "" else "")

	vl.text = fmt.call(value)
	s.value_changed.connect(func(val: float) -> void:
		vl.text = fmt.call(val)
		on_change.call(val))
	return row


func _refresh_labels() -> void:
	var gs := get_node_or_null("/root/GameState")
	var fs_on := false
	var dm := get_node_or_null("/root/DisplayMgr")
	if dm != null and dm.is_fullscreen():
		fs_on = true
	elif gs != null:
		fs_on = bool(gs.wants_fullscreen())
	if _fs_btn != null:
		_fs_btn.text = "显示：全屏" if fs_on else "显示：窗口"
	if _auto_toggle != null and gs != null:
		_auto_toggle.text = "自动推进：开" if bool(gs.auto_advance) else "自动推进：关"
	if _voice_toggle != null and gs != null:
		_voice_toggle.text = "剧情配音：开" if bool(gs.voice_on) else "剧情配音：关"
	if _type_toggle != null and gs != null:
		_type_toggle.text = "打字音效：开" if bool(gs.typing_on) else "打字音效：关"
	if _save_note != null and gs != null:
		if bool(gs.has_save()):
			var cm := GameDefs.chapter_by_id(String(gs.current_chapter))
			_save_note.text = "已有存档：停在第 %d 章 · %s。清除后「继续迁徙」将从头开始。" % [
				GameDefs.chapter_index(String(gs.current_chapter)), String(cm.get("title", ""))]
		else:
			_save_note.text = "当前没有任何存档。"


func _toggle_fullscreen() -> void:
	var dm := get_node_or_null("/root/DisplayMgr")
	if dm != null:
		dm.toggle()
	_refresh_labels()


func _toggle_auto() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.auto_advance = not bool(gs.auto_advance)
	gs.save_settings()
	_refresh_labels()


func _toggle_voice() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.voice_on = not bool(gs.voice_on)
	gs.save_settings()
	_refresh_labels()
	var am := get_node_or_null("/root/AudioMgr")
	if am != null:
		am.stop_voice()
		if bool(gs.voice_on):
			am.play_voice("c1_01")     # 打开时立刻给一句样本


func _toggle_typing() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.typing_on = not bool(gs.typing_on)
	gs.save_settings()
	_refresh_labels()
	var am := get_node_or_null("/root/AudioMgr")
	if am != null and bool(gs.typing_on):
		for i: int in range(3):
			am.play_type()
	else:
		am.play_sfx("click")


func _preview_voice() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and not bool(gs.voice_on):
		gs.voice_on = true
		gs.save_settings()
		_refresh_labels()
	var am := get_node_or_null("/root/AudioMgr")
	if am != null:
		am.play_voice("c1_01")


func _ask_wipe() -> void:
	if _confirm_card != null:
		return
	_confirm_card = UiKit.margin(0, 0, 0, 0)
	_confirm_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_confirm_card)

	var scrim := ColorRect.new()
	scrim.color = Color(0.006, 0.020, 0.035, 0.80)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_card.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_card.add_child(center)

	var card := UiKit.panel(Color(0.043, 0.098, 0.153, 0.98), 14, GameDefs.C_DANGER, 2, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)
	var m := UiKit.margin(30, 24, 30, 22)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(m)
	var col := UiKit.vbox(12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	col.add_child(UiKit.label("清除存档？", 26, GameDefs.C_TEXT))
	col.add_child(UiKit.hsep(Color(0.70, 0.30, 0.30, 0.7), 1))
	col.add_child(UiKit.wrapped(
		"这会删除当前进度、选择记录与章节解锁状态。设置项不会受影响，且此操作无法撤销。",
		18, Color("#cfe6f4")))
	var row := UiKit.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	var b_yes := UiKit.button("确认清除", 18, 44)
	b_yes.custom_minimum_size = Vector2(150, 44)
	b_yes.pressed.connect(_do_wipe)
	row.add_child(b_yes)
	var b_no := UiKit.primary_button("保留", 18, 44)
	b_no.custom_minimum_size = Vector2(130, 44)
	b_no.pressed.connect(_close_confirm)
	row.add_child(b_no)
	col.add_child(row)


func _do_wipe() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear_save()
		gs.new_run()
	_close_confirm()
	_refresh_labels()


func _close_confirm() -> void:
	if _confirm_card == null:
		return
	var c := _confirm_card
	_confirm_card = null
	c.queue_free()


func _on_back() -> void:
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.back()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			if _confirm_card != null:
				_close_confirm()
			else:
				_on_back()
