extends Control
## 主菜单 —— 迁徙的出发点。
##
## 左侧是标题与入口，右侧是「上一段迁徙的档案」与一条会轮播的冰川数据。
## 有存档时「继续迁徙」会显示停在哪一章、剩多少族群，让玩家决定是接着飞还是重来。

const STORY_SCENE := "res://scenes/story_screen.tscn"
const CHAPTER_SCENE := "res://scenes/chapter_select.tscn"
const CODEX_SCENE := "res://scenes/codex_screen.tscn"
const SETTINGS_SCENE := "res://scenes/settings_screen.tscn"

var _bg: BgArt
var _fact_label: Label
var _fact_timer: float = 0.0
var _fact_index: int = 0
var _facts: Array = []


func _ready() -> void:
	UiKit.apply(self)
	_bg = BgArt.new()
	_bg.scene_key = "title"
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_build()
	var am := get_node_or_null("/root/AudioMgr")
	if am != null:
		am.play_bgm("menu")
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.reset()


func _build() -> void:
	# ---------- 左：标题 + 入口 ----------
	var left := UiKit.margin(76, 0, 0, 0)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.custom_minimum_size = Vector2(560, 0)
	left.offset_right = 600
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)

	var lcol := UiKit.vbox(0)
	lcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lcol.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(lcol)

	var badge := UiKit.chip("Ayden · 徐浚文　少年组作品", GameDefs.C_ICE, 14)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lcol.add_child(badge)
	lcol.add_child(UiKit.spacer(12))

	var title := UiKit.label("冰川信使", 62, GameDefs.C_TEXT)
	title.add_theme_font_override("font", UiKit.bold_font())
	lcol.add_child(title)
	var sub := UiKit.label("斑头雁的 2040", 26, GameDefs.C_ICE)
	lcol.add_child(sub)
	lcol.add_child(UiKit.spacer(14))

	var blurb := UiKit.wrapped(
		"你是一只斑头雁。珠峰的裂缝正在变宽，谈判桌上坐着人类，\n而你手里的数据，是最后一份没有被人改过的证词。",
		17, Color("#a9c9dd"))
	lcol.add_child(UiKit.block([blurb], 470))
	lcol.add_child(UiKit.spacer(22))

	var menu := UiKit.vbox(10)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lcol.add_child(UiKit.block([menu], 320))

	var gs := get_node_or_null("/root/GameState")

	var b_new := UiKit.primary_button("开始新的迁徙", 21, 52)
	b_new.pressed.connect(_on_new)
	menu.add_child(b_new)

	if gs != null and bool(gs.has_save()):
		var b_cont := UiKit.button("继续迁徙", 20, 48)
		b_cont.pressed.connect(_on_continue)
		menu.add_child(b_cont)

	var b_ch := UiKit.button("章节选择", 20, 48)
	b_ch.pressed.connect(func() -> void: _nav(CHAPTER_SCENE))
	menu.add_child(b_ch)

	var b_codex := UiKit.button("物种档案", 20, 48)
	b_codex.pressed.connect(func() -> void: _nav(CODEX_SCENE))
	menu.add_child(b_codex)

	var b_set := UiKit.button("设置", 20, 48)
	b_set.pressed.connect(func() -> void: _nav(SETTINGS_SCENE))
	menu.add_child(b_set)

	var b_quit := UiKit.ghost_button("退出", 19, 44)
	b_quit.pressed.connect(func() -> void: get_tree().quit())
	menu.add_child(b_quit)

	# ---------- 右：档案卡 ----------
	var right := UiKit.margin(0, 0, 68, 0)
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.custom_minimum_size = Vector2(400, 0)
	right.offset_left = -468
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)

	var rcol := UiKit.vbox(12)
	rcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rcol.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(rcol)
	rcol.add_child(_build_archive_card(gs))

	# 轮播数据
	var fact_box := UiKit.panel(Color(0.035, 0.078, 0.125, 0.92), 12, GameDefs.C_LINE, 1, 0)
	var fm := UiKit.margin(20, 14, 20, 14)
	fm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fact_box.add_child(fm)
	var fcol := UiKit.vbox(6)
	fcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fm.add_child(fcol)
	var ft := UiKit.label("冰川数据", 14, GameDefs.C_ICE_DIM)
	fcol.add_child(ft)
	_fact_label = UiKit.wrapped("", 16, Color("#c7dfee"))
	_fact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fcol.add_child(_fact_label)
	rcol.add_child(fact_box)

	# 底部版本信息
	var foot := UiKit.margin(76, 0, 68, 20)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -34
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(foot)
	var frow := UiKit.hbox(0)
	frow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(frow)
	var ver := UiKit.label("《冰川信使：斑头雁的 2040》　Godot 4 剧情原型　v1.0", 13,
		Color(0.42, 0.56, 0.66))
	ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(ver)
	frow.add_child(UiKit.label("F11 全屏　·　ESC 返回", 13, Color(0.42, 0.56, 0.66)))

	_load_facts()


func _build_archive_card(gs: Node) -> Control:
	var card := UiKit.panel(Color(0.043, 0.098, 0.153, 0.94), 14, GameDefs.C_ICE_DIM, 1, 0)
	var m := UiKit.margin(22, 18, 22, 18)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(m)
	var col := UiKit.vbox(10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)

	var has_save := gs != null and bool(gs.has_save())
	var head := UiKit.hbox(9)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UiKit.label("迁徙档案", 20, GameDefs.C_ICE)
	t.add_theme_font_override("font", UiKit.bold_font())
	head.add_child(t)
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(pad)
	head.add_child(UiKit.chip("有存档" if has_save else "尚无记录",
		GameDefs.C_COOP if has_save else GameDefs.C_MUTED, 13))
	col.add_child(head)
	col.add_child(UiKit.hsep(GameDefs.C_LINE, 1))

	if not has_save or gs == null:
		col.add_child(UiKit.spacer(4))
		var d := UiKit.wrapped(
			"还没有任何一段迁徙被记录下来。\n\n从「开始新的迁徙」起飞，你的每一个选择都会写进 2040 年那份冰川报告里。",
			17, GameDefs.C_MUTED)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(d)
		col.add_child(UiKit.spacer(4))
		for row_i: int in range(3):
			var facts_row := UiKit.hbox(10)
			facts_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			facts_row.add_child(UiKit.chip(["6 项核心数值", "5 个章节", "5 种结局"][row_i],
				[GameDefs.C_ICE, GameDefs.C_GOLD, GameDefs.C_WARN][row_i], 13))
			col.add_child(facts_row)
		return card

	# 有存档：显示进度
	var ci := GameDefs.chapter_index(String(gs.current_chapter))
	var cm := GameDefs.chapter_by_id(String(gs.current_chapter))
	var l1 := UiKit.label("停在第 %d 章 · %s" % [ci, String(cm.get("title", ""))], 19,
		GameDefs.C_TEXT)
	l1.add_theme_font_override("font", UiKit.bold_font())
	col.add_child(l1)
	col.add_child(UiKit.label(String(cm.get("location", "")), 15, GameDefs.C_MUTED))

	col.add_child(UiKit.spacer(2))
	var stats_box := UiKit.vbox(7)
	stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key: String in GameDefs.STATS.keys():
		var lbl := GameDefs.stat_label(key)
		var col_c := GameDefs.stat_color(key)
		var v := float(gs.stats.get(key, 0))
		var row := UiKit.hbox(8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nl := UiKit.label(lbl, 14, GameDefs.C_MUTED)
		nl.custom_minimum_size = Vector2(70, 18)
		row.add_child(nl)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = v
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 9)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background",
			UiKit.box(Color(0.03, 0.07, 0.12, 0.85), 4, GameDefs.C_LINE, 1))
		bar.add_theme_stylebox_override("fill", UiKit.box(col_c, 4))
		row.add_child(bar)
		var vl := UiKit.label("%d" % int(round(v)), 14, col_c, HORIZONTAL_ALIGNMENT_RIGHT)
		vl.custom_minimum_size = Vector2(32, 18)
		row.add_child(vl)
		stats_box.add_child(row)
	col.add_child(stats_box)

	col.add_child(UiKit.spacer(2))
	var chips := UiKit.hbox(6)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_child(UiKit.chip("证据 %d" % Array(gs.evidence).size(), GameDefs.C_GOLD, 13))
	chips.add_child(UiKit.chip("科技 %d" % Array(gs.techs).size(), GameDefs.C_COOP, 13))
	col.add_child(chips)
	return card


func _load_facts() -> void:
	_facts.clear()
	var sd := get_node_or_null("/root/StoryData")
	if sd != null:
		for f: Variant in sd.codex_section("facts"):
			if f is Dictionary:
				_facts.append(f)
	if _facts.is_empty():
		_facts = [
			{"title": "25%", "label": "四十年冰川损失"},
			{"title": "1.5℃", "label": "温升红线"},
		]
	_advance_fact()


func _advance_fact() -> void:
	if _facts.is_empty() or _fact_label == null:
		return
	var f: Dictionary = _facts[_fact_index % _facts.size()]
	_fact_label.text = "%s　%s" % [String(f.get("title", "")), String(f.get("label", ""))]
	var tw := create_tween()
	_fact_label.modulate.a = 0.0
	tw.tween_property(_fact_label, "modulate:a", 1.0, 0.4)
	_fact_index += 1


func _process(delta: float) -> void:
	_fact_timer += delta
	if _fact_timer > 5.0:
		_fact_timer = 0.0
		_advance_fact()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ESCAPE or k.keycode == KEY_BACKSPACE):
			return


func _nav(path: String) -> void:
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.go(path)


func _on_new() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.new_run()
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.go_with(STORY_SCENE, { "chapter": "ch1" })


func _on_continue() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.load_progress():
		_on_new()
		return
	var node_id := String(gs.current_node)
	var chapter := String(gs.current_chapter)
	# 结束节点无法继续，回到该章开头
	var sd := get_node_or_null("/root/StoryData")
	if sd != null:
		var nd: Dictionary = sd.get_node_data(node_id)
		if node_id == "" or nd.is_empty() or String(nd.get("type", "")) == "ending":
			node_id = sd.chapter_start(chapter)
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.go_with(STORY_SCENE, { "chapter": chapter, "node": node_id, "resume": true })
