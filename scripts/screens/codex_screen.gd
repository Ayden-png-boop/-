extends Control
## 物种档案 —— 把剧情里遇到的人、物、数据整理成可翻阅的档案。
##
## 未获得的内容以「尚未记录」呈现，因为「还不知道自己不知道什么」
## 正是这场迁徙里最真实的处境。

const TABS := [
	{"id": "characters", "name": "角色", "color": "ice"},
	{"id": "evidence", "name": "证据", "color": "gold"},
	{"id": "tech", "name": "科技", "color": "coop"},
	{"id": "facts", "name": "冰川数据", "color": "warn"},
]

var _bg: BgArt
var _tab_row: HBoxContainer
var _content: VBoxContainer
var _scroll: ScrollContainer
var _current: String = "characters"
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	UiKit.apply(self)
	_bg = BgArt.new()
	_bg.scene_key = "ch2"
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_build()
	_show_tab("characters")


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
	var t := UiKit.label("物种档案", 32, GameDefs.C_TEXT)
	t.add_theme_font_override("font", UiKit.bold_font())
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(pad)
	col.add_child(head)

	# 标签栏
	_tab_row = UiKit.hbox(9)
	col.add_child(_tab_row)
	for tab: Dictionary in TABS:
		var tid := String(tab["id"])
		var b := UiKit.ghost_button(String(tab["name"]), 18, 42)
		b.custom_minimum_size = Vector2(150, 42)
		b.pressed.connect(func() -> void: _show_tab(tid))
		_tab_row.add_child(b)
		_tab_buttons[tid] = b
	var tpad := Control.new()
	tpad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_row.add_child(tpad)

	col.add_child(UiKit.hsep(GameDefs.C_LINE, 1))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	_content = UiKit.vbox(12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_content)


func _tab_color(tid: String) -> Color:
	match tid:
		"evidence":
			return GameDefs.C_GOLD
		"tech":
			return GameDefs.C_COOP
		"facts":
			return GameDefs.C_WARN
		_:
			return GameDefs.C_ICE


func _show_tab(tid: String) -> void:
	_current = tid
	for key: String in _tab_buttons.keys():
		var b: Button = _tab_buttons[key]
		var on := key == tid
		if on:
			var c := _tab_color(key)
			b.add_theme_stylebox_override("normal",
				UiKit.box(Color(c.r, c.g, c.b, 0.20), 10, c, 1))
			b.add_theme_color_override("font_color", c)
		else:
			b.add_theme_stylebox_override("normal",
				UiKit.box(Color(0, 0, 0, 0), 10, GameDefs.C_LINE, 1))
			b.add_theme_color_override("font_color", GameDefs.C_TEXT)

	for c: Node in _content.get_children():
		_content.remove_child(c)
		c.queue_free()

	# 立刻计算宽度，避免 autowrap 标签在容器首帧还没拿到宽度
	await get_tree().process_frame

	var sd := get_node_or_null("/root/StoryData")
	if sd == null:
		return
	var items: Array = sd.codex_section(tid)
	if items.is_empty():
		_content.add_child(UiKit.wrapped("这一部分还没有任何记录。", 19, GameDefs.C_MUTED))
		return

	var gs := get_node_or_null("/root/GameState")
	for item: Variant in items:
		if not (item is Dictionary):
			continue
		_content.add_child(_build_entry(Dictionary(item), tid, gs))


func _build_entry(d: Dictionary, tid: String, gs: Node) -> Control:
	var accent := _tab_color(tid)
	var unlocked := _is_unlocked(d, tid, gs)

	var card := UiKit.panel(
		Color(0.035, 0.082, 0.129, 0.94) if unlocked else Color(0.047, 0.063, 0.082, 0.86),
		12, Color(accent.r, accent.g, accent.b, 0.45) if unlocked else Color(0.16, 0.20, 0.24),
		1, 0)
	var m := UiKit.margin(20, 15, 20, 15)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(m)

	var col := UiKit.vbox(8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)

	var head := UiKit.hbox(10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_txt := String(d.get("name", "?"))
	if not unlocked and tid != "facts":
		name_txt = "？？？"
	var nl := UiKit.label(name_txt, 22, GameDefs.C_TEXT if unlocked else Color(0.50, 0.56, 0.62))
	nl.add_theme_font_override("font", UiKit.bold_font())
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(nl)

	if unlocked and d.has("species"):
		var sp := UiKit.chip(String(d["species"]), accent, 13)
		sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(sp)
	if unlocked and d.has("role"):
		head.add_child(UiKit.label(String(d["role"]), 14, GameDefs.C_MUTED))
	if unlocked and d.has("label"):
		head.add_child(UiKit.label(String(d["label"]), 15, accent))

	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(pad)

	if not unlocked and tid != "facts":
		head.add_child(UiKit.chip("尚未记录", GameDefs.C_MUTED, 13))
	col.add_child(head)

	var body := String(d.get("desc", ""))
	if not unlocked and tid != "facts":
		var ch := String(d.get("chapter", ""))
		var ci := GameDefs.chapter_index(ch)
		body = "继续迁徙，在第 %d 章附近你会遇到它。" % maxi(ci, 1)
	var bl := UiKit.wrapped(body, 16,
		Color("#b6d2e4") if unlocked else Color(0.52, 0.58, 0.64))
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bl)

	return card


func _is_unlocked(d: Dictionary, tid: String, gs: Node) -> bool:
	if tid == "facts":
		return true
	var id := String(d.get("id", d.get("name", "")))
	if gs == null:
		return false
	if tid == "evidence":
		return bool(gs.has_evidence(id))
	if tid == "tech":
		return bool(gs.has_tech(id))
	# 角色：按章节进度解锁
	if String(gs.finished_ending) != "":
		return true
	var need := GameDefs.chapter_index(String(d.get("chapter", "")))
	var cur := GameDefs.chapter_index(String(gs.current_chapter))
	return cur >= need and need > 0


func _on_back() -> void:
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.back()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_on_back()
