extends Control
## 结局页 —— 结算这场迁徙。
##
## 除了结局文本，还会回放玩家一路做过的关键抉择与最终数值。
## 这是把「我做了什么」和「世界变成了什么」摆在同一个画面里的地方。

const MENU_SCENE := "res://scenes/main_menu.tscn"
const STORY_SCENE := "res://scenes/story_screen.tscn"
const CODEX_SCENE := "res://scenes/codex_screen.tscn"

var _bg: BgArt
var _ending_id: String = ""


func _ready() -> void:
	UiKit.apply(self)
	_bg = BgArt.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	var nav := get_node_or_null("/root/Navigator")
	var eid := ""
	if nav != null and nav.params is Dictionary and Dictionary(nav.params).has("ending"):
		eid = String(Dictionary(nav.params)["ending"])
	if eid == "":
		var gs0 := get_node_or_null("/root/GameState")
		if gs0 != null:
			eid = String(gs0.finished_ending)
	if eid == "":
		eid = "ending_doom"
	_ending_id = eid

	var ed := GameDefs.ending_by_id(eid)
	_bg.set_scene(String(ed.get("bg", "ending_bad")))
	_build(ed)

	var am := get_node_or_null("/root/AudioMgr")
	if am != null:
		var tone := String(ed.get("tone", "neutral"))
		am.play_bgm("calm" if tone == "good" else ("collapse" if tone == "bad" else "menu"))
		# 结局旁白配音（文件按结局 id 命名）
		am.play_voice(eid)


func _exit_tree() -> void:
	var am := get_node_or_null("/root/AudioMgr")
	if am != null:
		am.stop_voice()


func _build(ed: Dictionary) -> void:
	var accent: Color = ed.get("accent", GameDefs.C_ICE)

	var root := UiKit.margin(56, 30, 56, 26)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var outer := UiKit.vbox(16)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(outer)

	# ---- 标题区 ----
	var head_panel := UiKit.panel(Color(0.024, 0.059, 0.098, 0.94), 16,
		Color(accent.r, accent.g, accent.b, 0.55), 1, 0)
	var hm := UiKit.margin(30, 22, 30, 22)
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_panel.add_child(hm)
	var hcol := UiKit.vbox(12)
	hcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hm.add_child(hcol)

	var tagrow := UiKit.hbox(10)
	tagrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tagrow.add_child(UiKit.chip("本局结局", GameDefs.C_MUTED, 14))
	tagrow.add_child(UiKit.chip(String(ed.get("tag", "")), accent, 14))
	hcol.add_child(tagrow)

	var t := UiKit.label(String(ed.get("title", "结局")), 50, GameDefs.C_TEXT)
	t.add_theme_font_override("font", UiKit.bold_font())
	hcol.add_child(t)

	hcol.add_child(UiKit.hsep(Color(accent.r, accent.g, accent.b, 0.45), 1))

	var sum_l := UiKit.wrapped(String(ed.get("summary", "")), 20, Color("#d3e7f4"))
	sum_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hcol.add_child(sum_l)

	outer.add_child(head_panel)

	# ---- 数值 + 抉择 ----
	var gs := get_node_or_null("/root/GameState")
	var cols := UiKit.hbox(16)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(cols)

	# 最终数值
	var stat_card := UiKit.panel(Color(0.035, 0.082, 0.129, 0.94), 14, GameDefs.C_LINE, 1, 0)
	stat_card.custom_minimum_size = Vector2(420, 0)
	var sm := UiKit.margin(22, 18, 22, 18)
	sm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_card.add_child(sm)
	var scol := UiKit.vbox(9)
	scol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sm.add_child(scol)
	var sh := UiKit.label("最终数值", 20, GameDefs.C_ICE)
	sh.add_theme_font_override("font", UiKit.bold_font())
	scol.add_child(sh)
	scol.add_child(UiKit.hsep(GameDefs.C_LINE, 1))
	if gs != null:
		for key: String in GameDefs.STATS.keys():
			scol.add_child(_stat_row(key, float(gs.stats.get(key, 0))))
		var chips := UiKit.hbox(7)
		chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chips.add_child(UiKit.chip("证据 %d/%d" % [Array(gs.evidence).size(), 3],
			GameDefs.C_GOLD, 13))
		chips.add_child(UiKit.chip("科技 %d/%d" % [Array(gs.techs).size(), 3],
			GameDefs.C_COOP, 13))
		scol.add_child(chips)
	cols.add_child(stat_card)

	# 关键抉择回放
	var log_card := UiKit.panel(Color(0.035, 0.082, 0.129, 0.94), 14, GameDefs.C_LINE, 1, 0)
	log_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lm := UiKit.margin(22, 18, 22, 18)
	lm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_card.add_child(lm)
	var lcol := UiKit.vbox(9)
	lcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lm.add_child(lcol)
	var lh := UiKit.label("你一路上的抉择", 20, GameDefs.C_GOLD)
	lh.add_theme_font_override("font", UiKit.bold_font())
	lcol.add_child(lh)
	lcol.add_child(UiKit.hsep(GameDefs.C_LINE, 1))
	if gs != null and not Array(gs.choice_log).is_empty():
		for entry: Variant in gs.choice_log:
			if not (entry is Dictionary):
				continue
			var e: Dictionary = entry
			var row := UiKit.hbox(10)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var ch := GameDefs.chapter_by_id(String(e.get("chapter", "")))
			var ci := int(ch.get("index", 0))
			var idx_l := UiKit.label("第%d章" % ci, 14, GameDefs.C_MUTED)
			idx_l.custom_minimum_size = Vector2(58, 20)
			row.add_child(idx_l)
			var txt := UiKit.wrapped(String(e.get("text", "")), 16, Color("#cfe4f2"))
			txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(txt)
			lcol.add_child(row)
	else:
		lcol.add_child(UiKit.wrapped("这一局没有留下任何抉择记录。", 16, GameDefs.C_MUTED))
	cols.add_child(log_card)

	# ---- 按钮 ----
	var btnrow := UiKit.hbox(12)
	btnrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btnrow.alignment = BoxContainer.ALIGNMENT_CENTER
	var b_again := UiKit.primary_button("再来一次迁徙", 20, 50)
	b_again.custom_minimum_size = Vector2(220, 50)
	b_again.pressed.connect(_again)
	btnrow.add_child(b_again)
	var b_codex := UiKit.button("查看档案", 19, 48)
	b_codex.custom_minimum_size = Vector2(180, 48)
	b_codex.pressed.connect(func() -> void: _nav(CODEX_SCENE))
	btnrow.add_child(b_codex)
	var b_menu := UiKit.ghost_button("回到主菜单", 19, 48)
	b_menu.custom_minimum_size = Vector2(180, 48)
	b_menu.pressed.connect(func() -> void: _nav(MENU_SCENE))
	btnrow.add_child(b_menu)
	outer.add_child(btnrow)


func _stat_row(key: String, v: float) -> Control:
	var row := UiKit.hbox(9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := GameDefs.stat_color(key)
	var nl := UiKit.label(GameDefs.stat_label(key), 15, GameDefs.C_MUTED)
	nl.custom_minimum_size = Vector2(76, 20)
	row.add_child(nl)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = v
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background",
		UiKit.box(Color(0.03, 0.07, 0.12, 0.85), 4, GameDefs.C_LINE, 1))
	bar.add_theme_stylebox_override("fill", UiKit.box(col, 4))
	row.add_child(bar)
	var vl := UiKit.label("%d" % int(round(v)), 15, col, HORIZONTAL_ALIGNMENT_RIGHT)
	vl.custom_minimum_size = Vector2(34, 20)
	row.add_child(vl)
	return row


func _again() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.new_run()
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.go_with(STORY_SCENE, { "chapter": "ch1" })


func _nav(path: String) -> void:
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.go(path)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_nav(MENU_SCENE)
