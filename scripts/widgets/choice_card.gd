class_name ChoiceCard
extends Button
## ChoiceCard —— 一个剧情选项卡片。
##
## 由「选项正文 + 提示 + 数值变化预览 + 风险 + 未解锁条件」组成。
## 未满足条件的选项不会消失，而是以锁定态显示原因——让玩家知道
## 自己错过了什么，这比直接隐藏更有叙事张力。

var option_index: int = 0
var _locked: bool = false
var _inner: MarginContainer


func setup(opt: Dictionary, index: int, locked: bool) -> void:
	option_index = index
	_locked = locked
	focus_mode = Control.FOCUS_ALL if not locked else Control.FOCUS_NONE
	disabled = locked
	mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND
	text = ""
	clip_contents = false
	_build(opt)


func _build(opt: Dictionary) -> void:
	var accent: Color = opt.get("accent", GameDefs.C_ICE)
	if _locked:
		accent = GameDefs.C_MUTED

	# --- 按钮外观 ---
	if _locked:
		add_theme_stylebox_override("normal",
			UiKit.box(Color(0.05, 0.09, 0.13, 0.72), 12, Color(0.16, 0.22, 0.28), 1, 0))
		add_theme_stylebox_override("hover",
			UiKit.box(Color(0.05, 0.09, 0.13, 0.72), 12, Color(0.16, 0.22, 0.28), 1, 0))
		add_theme_stylebox_override("pressed",
			UiKit.box(Color(0.05, 0.09, 0.13, 0.72), 12, Color(0.16, 0.22, 0.28), 1, 0))
	else:
		add_theme_stylebox_override("normal",
			UiKit.box(Color(0.055, 0.129, 0.196, 0.90), 12,
				Color(accent.r, accent.g, accent.b, 0.42), 1, 0))
		add_theme_stylebox_override("hover",
			UiKit.box(Color(0.086, 0.204, 0.302, 0.96), 12, accent, 2, 0))
		add_theme_stylebox_override("pressed",
			UiKit.box(Color(0.035, 0.090, 0.145, 0.98), 12, accent, 2, 0))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_stylebox_override("disabled",
		UiKit.box(Color(0.05, 0.09, 0.13, 0.72), 12, Color(0.16, 0.22, 0.28), 1, 0))

	# --- 内容 ---
	_inner = UiKit.margin(18, 13, 18, 13)
	_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inner)

	var outer := UiKit.hbox(14)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.add_child(outer)

	# 左侧强调色竖条
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(3, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(bar)

	var col := UiKit.vbox(7)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(col)

	# 第一行：标签片 + 选项标题
	var head := UiKit.hbox(9)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := String(opt.get("tag", ""))
	if tag != "":
		var c := UiKit.chip(tag, accent if not _locked else GameDefs.C_MUTED, 14)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(c)
	var main_text := UiKit.label(String(opt.get("text", "")), 22,
		GameDefs.C_MUTED if _locked else GameDefs.C_TEXT)
	main_text.add_theme_font_override("font", UiKit.bold_font())
	main_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(main_text)
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(pad)
	if _locked:
		var lk := UiKit.label("未满足条件", 15, GameDefs.C_DANGER)
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(lk)
	col.add_child(head)

	# 第二行：说明
	var hint := String(opt.get("hint", ""))
	if hint != "":
		var h := UiKit.wrapped(hint, 17, GameDefs.C_MUTED if _locked else Color("#bcd8ea"))
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(h)

	# 第三行：效果预览片
	var chips := UiKit.hbox(7)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var has_chip := false
	var eff: Dictionary = opt.get("effects", {}) if opt.get("effects", {}) is Dictionary else {}
	var eff_stats: Dictionary = eff.get("stats", {}) if eff.get("stats", {}) is Dictionary else {}
	for key: String in eff_stats.keys():
		var delta := float(eff_stats[key])
		if is_zero_approx(delta):
			continue
		var col_c := GameDefs.stat_color(key)
		var txt := "%s %s%d" % [GameDefs.stat_label(key), "+" if delta > 0 else "", int(delta)]
		chips.add_child(UiKit.chip(txt, col_c, 13))
		has_chip = true
	var ev_list: Array = eff.get("evidence", []) if eff.get("evidence", []) is Array else []
	for e: Variant in ev_list:
		chips.add_child(UiKit.chip("证据 · %s" % String(e), GameDefs.C_GOLD, 13))
		has_chip = true
	var tk_list: Array = eff.get("tech", []) if eff.get("tech", []) is Array else []
	for t: Variant in tk_list:
		chips.add_child(UiKit.chip("科技 · %s" % String(t), GameDefs.C_COOP, 13))
		has_chip = true
	if has_chip:
		col.add_child(chips)

	# 第四行：风险
	var risk := String(opt.get("risk", ""))
	if risk != "":
		var r := UiKit.wrapped("风险：" + risk, 15, GameDefs.C_WARN)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(r)

	# 第五行：未解锁原因
	if _locked:
		var lh := String(opt.get("locked_hint", "尚未满足解锁条件。"))
		var l := UiKit.wrapped("✕ " + lh, 15, GameDefs.C_DANGER)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)

	_ignore_mouse_deep(_inner)
	# 按内容撑开按钮高度（Button 自身不是容器，不会自动撑高）
	await get_tree().process_frame
	if _inner != null:
		var need := _inner.get_combined_minimum_size().y
		custom_minimum_size.y = maxf(72.0, need)


func _ignore_mouse_deep(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Node in node.get_children():
		_ignore_mouse_deep(c)


## 被选中时的一小段强调动画
func play_chosen() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1.6, 1.6, 1.6, 1.0), 0.08)
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0.0), 0.22)
