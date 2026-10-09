class_name StatsHud
extends VBoxContainer
## StatsHud —— 右侧数值面板：六项核心数值 + 证据/科技计数。
##
## 数值变动时条会平滑过渡并闪一下，让玩家清楚看到「刚才那个选择改变了什么」。

var _rows: Dictionary = {}          ## key -> {bar, value_label, display, target, flash}
var _title_label: Label
var _chapter_label: Label
var _inv_label: Label
var _inv_chips: HBoxContainer
var _inv_chips2: HBoxContainer
var _warn_label: Label
var _t: float = 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	var gs := _state()
	if gs != null:
		if not gs.stats_changed.is_connected(refresh):
			gs.stats_changed.connect(refresh)
		if not gs.inventory_changed.is_connected(refresh):
			gs.inventory_changed.connect(refresh)
	refresh()


func _state() -> Node:
	var t := Engine.get_main_loop()
	if t is SceneTree:
		return (t as SceneTree).root.get_node_or_null("GameState")
	return null


func _build() -> void:
	var header := UiKit.hbox(8)
	_title_label = UiKit.label("迁徙状态", 16, GameDefs.C_ICE)
	_title_label.add_theme_font_override("font", UiKit.bold_font())
	header.add_child(_title_label)
	header.add_child(UiKit.hspacer(0))
	var flex := Control.new()
	flex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(flex)
	_chapter_label = UiKit.label("第 1 章", 13, GameDefs.C_MUTED)
	header.add_child(_chapter_label)
	add_child(header)
	add_child(UiKit.hsep(GameDefs.C_LINE, 1))
	add_child(UiKit.spacer(2))

	for key: String in GameDefs.STATS.keys():
		add_child(_build_row(key))

	add_child(UiKit.spacer(4))
	add_child(UiKit.hsep(GameDefs.C_LINE, 1))
	add_child(UiKit.spacer(2))

	_inv_label = UiKit.label("随身档案", 15, GameDefs.C_GOLD)
	_inv_label.add_theme_font_override("font", UiKit.bold_font())
	add_child(_inv_label)
	_inv_chips = UiKit.hbox(6)
	_inv_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inv_chips)
	_inv_chips2 = UiKit.hbox(6)
	_inv_chips2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inv_chips2)

	_warn_label = UiKit.wrapped("", 12, GameDefs.C_WARN)
	_warn_label.visible = false
	add_child(_warn_label)
	# 让面板内容顶部对齐、底部留白
	var tail := Control.new()
	tail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tail)


func _build_row(key: String) -> Control:
	var d: Dictionary = GameDefs.STATS[key]
	var row := UiKit.hbox(6)
	# PASS：允许鼠标悬浮，悬浮时显示该数值的含义提示
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = "%s：%s" % [String(d.get("label", key)), String(d.get("hint", ""))]
	var col: Color = d.get("color", GameDefs.C_ICE)

	var name_l := UiKit.label(String(d.get("label", key)), 13, GameDefs.C_MUTED)
	name_l.custom_minimum_size = Vector2(62, 18)
	name_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	row.add_child(name_l)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = float(GameDefs.STAT_MAX)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 9)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", UiKit.box(Color(0.02, 0.05, 0.09, 0.9), 5,
		Color(0.10, 0.20, 0.28, 1.0), 1))
	bar.add_theme_stylebox_override("fill", UiKit.box(col, 5))
	row.add_child(bar)

	var val := UiKit.label("0", 13, col, HORIZONTAL_ALIGNMENT_RIGHT)
	val.custom_minimum_size = Vector2(28, 18)
	row.add_child(val)

	_rows[key] = {
		"bar": bar, "value": val, "display": 0.0,
		"target": 0.0, "flash": 0.0, "color": col,
	}
	return row


func _process(delta: float) -> void:
	var dirty := false
	for key: String in _rows.keys():
		var r: Dictionary = _rows[key]
		var disp := float(r["display"])
		var target := float(r["target"])
		if not is_equal_approx(disp, target):
			disp = lerpf(disp, target, clampf(delta * 6.5, 0.0, 1.0))
			if absf(disp - target) < 0.35:
				disp = target
			r["display"] = disp
			_apply_row(key, r)
			dirty = true
		var fl := float(r["flash"])
		if fl > 0.001:
			fl = maxf(fl - delta * 1.8, 0.0)
			r["flash"] = fl
			var bar: ProgressBar = r["bar"]
			var col: Color = r["color"]
			bar.add_theme_stylebox_override("fill",
				UiKit.box(col.lerp(Color.WHITE, fl * 0.75), 5))
			dirty = true
	if dirty:
		pass


func _apply_row(key: String, r: Dictionary) -> void:
	var bar: ProgressBar = r["bar"]
	var val: Label = r["value"]
	var v := float(r["display"])
	bar.value = v
	val.text = "%d" % int(round(v))


func refresh() -> void:
	var gs := _state()
	if gs == null:
		return
	for key: String in _rows.keys():
		var r: Dictionary = _rows[key]
		var v := float(gs.stats.get(key, 0))
		if absf(float(r["target"]) - v) > 0.01:
			r["flash"] = 1.0
		r["target"] = v
		if float(r["display"]) <= 0.0:
			r["display"] = v
			_apply_row(key, r)

	_title_label.text = "迁徙状态"
	if _chapter_label != null:
		var ci := GameDefs.chapter_index(String(gs.current_chapter))
		if ci <= 0:
			ci = 1
		_chapter_label.text = "第 %d 章" % ci

	# 随身档案
	_clear_children(_inv_chips)
	_clear_children(_inv_chips2)
	var ev: Array = gs.evidence
	var tk: Array = gs.techs
	if ev.is_empty() and tk.is_empty():
		_inv_chips.add_child(UiKit.chip("尚无", GameDefs.C_MUTED, 12))
	else:
		for e: Variant in ev:
			_inv_chips.add_child(UiKit.chip(String(e), GameDefs.C_GOLD, 12))
		for t: Variant in tk:
			_inv_chips2.add_child(UiKit.chip(String(t), GameDefs.C_COOP, 12))

	# 危急提示
	var msgs: Array[String] = []
	if float(gs.stats.get("population", 100)) <= 30.0:
		msgs.append("族群数量告急")
	if float(gs.stats.get("trust", 100)) <= 30.0:
		msgs.append("内部信任濒临瓦解")
	if float(gs.stats.get("stamina", 100)) <= 20.0:
		msgs.append("体力见底")
	if float(gs.stats.get("glacier", 100)) <= 20.0:
		msgs.append("冰川已进入不可逆区间")
	_warn_label.text = "⚠ " + "　".join(msgs) if not msgs.is_empty() else ""
	_warn_label.visible = not msgs.is_empty()


func _clear_children(node: Node) -> void:
	for c: Node in node.get_children():
		node.remove_child(c)
		c.queue_free()
