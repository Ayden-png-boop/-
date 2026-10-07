extends Control
## 章节选择 —— 五张章节卡横向排开。
##
## 每张卡交代「在哪、什么天气、会发生什么」，已解锁的可直接进入，
## 未解锁的显示解锁条件而不是简单隐藏，方便回顾进度。

const STORY_SCENE := "res://scenes/story_screen.tscn"

var _bg: BgArt
var _cards_row: HBoxContainer


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


func _build() -> void:
	var root := UiKit.margin(44, 30, 44, 26)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var col := UiKit.vbox(16)
	root.add_child(col)

	# 顶部
	var head := UiKit.hbox(14)
	var back := UiKit.ghost_button("◂ 返回", 17, 40)
	back.custom_minimum_size = Vector2(104, 40)
	back.pressed.connect(_on_back)
	head.add_child(back)
	var t := UiKit.label("章节选择", 32, GameDefs.C_TEXT)
	t.add_theme_font_override("font", UiKit.bold_font())
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(pad)
	var prog := UiKit.label("按顺序体验全部五次抉择", 15, GameDefs.C_MUTED)
	prog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(prog)
	col.add_child(head)

	# 卡片行
	_cards_row = UiKit.hbox(16)
	_cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_cards_row)

	var gs := get_node_or_null("/root/GameState")
	for ch: Dictionary in GameDefs.CHAPTERS:
		var cid := String(ch["id"])
		var unlocked := true
		if gs != null:
			unlocked = bool(gs.is_chapter_unlocked(cid))
		_cards_row.add_child(_build_card(ch, unlocked))


func _build_card(ch: Dictionary, unlocked: bool) -> Control:
	var accent: Color = ch.get("accent", GameDefs.C_ICE)
	var cid := String(ch["id"])
	var idx := int(ch.get("index", 1))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 430)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.text = ""
	btn.focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE
	btn.disabled = not unlocked
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if unlocked else Control.CURSOR_ARROW
	if unlocked:
		btn.add_theme_stylebox_override("normal",
			UiKit.box(Color(0.035, 0.082, 0.129, 0.92), 14, Color(accent.r, accent.g, accent.b, 0.40), 1, 0))
		btn.add_theme_stylebox_override("hover",
			UiKit.box(Color(0.063, 0.153, 0.235, 0.96), 14, accent, 2, 0))
		btn.add_theme_stylebox_override("pressed",
			UiKit.box(Color(0.027, 0.063, 0.106, 0.98), 14, accent, 2, 0))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(func() -> void: _enter(cid))
	else:
		var sb := UiKit.box(Color(0.043, 0.067, 0.094, 0.80), 14, Color(0.15, 0.20, 0.26), 1, 0)
		for st: String in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(st, sb)

	# 卡片内容
	var wrap := UiKit.margin(16, 16, 16, 16)
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(wrap)

	var col := UiKit.vbox(9)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(col)

	# 顶部强调条
	var bar := ColorRect.new()
	bar.color = accent if unlocked else Color(0.22, 0.26, 0.30)
	bar.custom_minimum_size = Vector2(0, 3)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bar)

	var tag := UiKit.chip("第 %d 章" % idx, accent if unlocked else GameDefs.C_MUTED, 13)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(tag)

	var title := UiKit.wrapped(String(ch.get("title", "")), 24,
		GameDefs.C_TEXT if unlocked else Color(0.46, 0.53, 0.60))
	title.add_theme_font_override("font", UiKit.bold_font())
	col.add_child(title)

	var loc := UiKit.wrapped("%s\n%s" % [String(ch.get("location", "")), String(ch.get("weather", ""))],
		14, accent if unlocked else Color(0.40, 0.46, 0.52))
	col.add_child(loc)

	col.add_child(UiKit.hsep(Color(accent.r, accent.g, accent.b, 0.30) if unlocked
		else Color(0.18, 0.22, 0.26), 1))

	var sum_l := UiKit.wrapped(String(ch.get("summary", "")), 15,
		Color("#b6d2e4") if unlocked else Color(0.42, 0.48, 0.54))
	col.add_child(sum_l)

	# 撑开，把底部状态压到卡片末尾
	var flex := Control.new()
	flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	flex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(flex)

	if unlocked:
		var go := UiKit.label("进入本章　▸", 17, accent)
		go.add_theme_font_override("font", UiKit.bold_font())
		col.add_child(go)
	else:
		var lock := UiKit.wrapped("✕ 未解锁\n通关上一章后开启", 14, Color(0.52, 0.58, 0.64))
		col.add_child(lock)

	return btn


func _enter(cid: String) -> void:
	var gs := get_node_or_null("/root/GameState")
	var sd := get_node_or_null("/root/StoryData")
	var start := ""
	if sd != null:
		start = String(sd.chapter_start(cid))
	if gs != null:
		gs.begin_from_chapter(cid, start)
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.go_with(STORY_SCENE, { "chapter": cid, "node": start })


func _on_back() -> void:
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.back()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_on_back()
