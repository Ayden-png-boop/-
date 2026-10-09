extends Control
## 剧情页 —— 整个游戏的主循环。
##
## 负责把 story.json 里的节点「演」出来：打字机文本、说话人、选项卡片、
## 全屏弹窗、限时 QTE、章节转场卡、结算浮层，并把玩家的选择写回 GameState。
## 所有节点类型都在 _goto() 里分发 —— 改剧情不需要动这里。

const CHAPTER_SCENE := "res://scenes/chapter_select.tscn"
const CODEX_SCENE := "res://scenes/codex_screen.tscn"
const ENDING_SCENE := "res://scenes/ending_screen.tscn"

const HUD_W := 186.0
## 对话框高度自适应范围：最矮约为原高的一半，长文本自动长高防裁切
const BOX_H_MIN := 96.0
const BOX_H_MAX := 180.0
const TOP_H := 62.0

var _hud_wrap: Control
var _hud_btn: Button
var _hud_hidden := false

var _bg: BgArt
var _top_chip: Label
var _top_title: Label
var _auto_btn: Button
var _hud: StatsHud

var _box: Control
var _speaker: Label
var _text: Label
var _caret: Label

var _choice_layer: Control
var _choice_head: Label
var _choice_box: VBoxContainer
var _choice_inline: VBoxContainer   ## 对话框内嵌的简洁选项列表（一行一个）

var _popup: PopupLayer
var _qte: QtePanel
var _card_layer: Control
var _fx_layer: Control

var _chapter: String = "ch1"
var _node_id: String = ""
var _node: Dictionary = {}
var _pending_choice: Dictionary = {}
var _pending_qte: Dictionary = {}

var _full: String = ""
var _typed: float = 0.0
var _typing: bool = false
var _advance_ready: bool = false
var _busy: bool = false
var _error_state: bool = false
var _auto_timer: float = 0.0
# 非自动模式下的闲置计时：文本展示完毕后长时间无点击则兜底推进
var _idle_timer: float = 0.0
var _blink: float = 0.0
var _type_marks: int = 0            ## 打字音的下一个触发字数门槛

## 快速模式：章节转场卡、结算浮层、弹窗一律不等动画，直接推进。
## 给「跳过演出」设置与无头回归测试用——演出时长不该影响逻辑正确性。
var fast_mode: bool = false


func _ready() -> void:
	UiKit.apply(self)
	_bg = BgArt.new()
	_bg.scene_key = "ch1"
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_build()
	_popup = PopupLayer.new()
	_popup.name = "PopupLayer"
	add_child(_popup)
	_qte = QtePanel.new()
	_qte.name = "QtePanel"
	add_child(_qte)
	_build_card_layer()
	_fx_layer = Control.new()
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)

	var sd := get_node_or_null("/root/StoryData")
	if sd == null or not bool(sd.ok):
		_toast_error("剧情数据不可用。请检查 res://data/story.json 后重新开始。")
		return
	_start_flow()


func _exit_tree() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.stats_changed.is_connected(_refresh_top):
		gs.stats_changed.disconnect(_refresh_top)
	_voice_stop()


# ===========================================================================
# 界面搭建
# ===========================================================================
func _build() -> void:
	_build_topbar()
	_build_hud()
	_build_textbox()
	_build_choice_layer()


func _build_topbar() -> void:
	var top := UiKit.margin(22, 13, 22, 0)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_H
	# STOP：顶栏空白处的点击被它吃掉，不会误触发「点击继续」
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)

	var trow := UiKit.hbox(10)
	top.add_child(trow)

	var back := UiKit.ghost_button("◂ 章节", 16, 36)
	back.custom_minimum_size = Vector2(96, 36)
	back.pressed.connect(func() -> void: _nav(CHAPTER_SCENE))
	trow.add_child(back)

	var chip := UiKit.chip("第 1 章", GameDefs.C_ICE, 14)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(chip)
	var cl: Variant = chip.get_meta("chip_label", null)
	if cl is Label:
		_top_chip = cl

	_top_title = UiKit.label("", 17, GameDefs.C_TEXT)
	_top_title.add_theme_font_override("font", UiKit.bold_font())
	_top_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(_top_title)

	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trow.add_child(pad)

	_auto_btn = UiKit.ghost_button("自动：关", 16, 36)
	_auto_btn.custom_minimum_size = Vector2(112, 36)
	_auto_btn.pressed.connect(_toggle_auto)
	trow.add_child(_auto_btn)

	var b_codex := UiKit.ghost_button("档案", 16, 36)
	b_codex.custom_minimum_size = Vector2(78, 36)
	b_codex.pressed.connect(func() -> void: _nav(CODEX_SCENE))
	trow.add_child(b_codex)

	var b_menu := UiKit.ghost_button("菜单", 16, 36)
	b_menu.custom_minimum_size = Vector2(78, 36)
	b_menu.pressed.connect(func() -> void:
		var nav := get_node_or_null("/root/Navigator")
		if nav != null:
			nav.home())
	trow.add_child(b_menu)


func _build_hud() -> void:
	var hud_wrap := UiKit.margin(0, 0, 16, 0)
	hud_wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	hud_wrap.offset_left = -(HUD_W + 16.0)
	hud_wrap.offset_top = TOP_H + 12.0
	hud_wrap.offset_bottom = -16
	hud_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_wrap)

	# 无框化：去掉底色与描边，只保留 STOP 语义（点击数值区不会推进剧情）
	var hud_panel := UiKit.panel(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 0)
	hud_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_wrap.add_child(hud_panel)
	var hud_margin := UiKit.margin(12, 11, 12, 11)
	hud_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_panel.add_child(hud_margin)
	_hud = StatsHud.new()
	hud_margin.add_child(_hud)

	# 原神式折叠页签：把状态栏收起来，把画面还给 CG
	_hud_btn = UiKit.ghost_button("»", 15, 30)
	_hud_btn.custom_minimum_size = Vector2(26, 56)
	_hud_btn.focus_mode = Control.FOCUS_NONE
	_hud_btn.tooltip_text = "收起 / 展开状态栏"
	_hud_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hud_btn.offset_left = -30.0
	_hud_btn.offset_right = -4.0
	_hud_btn.offset_top = TOP_H + 12.0
	_hud_btn.offset_bottom = TOP_H + 68.0
	_hud_btn.pressed.connect(_toggle_hud)
	add_child(_hud_btn)


func _toggle_hud() -> void:
	_hud_hidden = not _hud_hidden
	if _hud_btn != null:
		_hud_btn.text = "«" if _hud_hidden else "»"
	var tw := create_tween().set_parallel(true)
	if _hud_wrap != null:
		var dl := 0.0 if _hud_hidden else -(HUD_W + 16.0)
		var dr := float(HUD_W) if _hud_hidden else -16.0
		tw.tween_property(_hud_wrap, "offset_left", dl, 0.25)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_hud_wrap, "offset_right", dr, 0.25)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _box != null:
		var tr := -22.0 if _hud_hidden else -(HUD_W + 32.0)
		tw.tween_property(_box, "offset_right", tr, 0.25)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _choice_layer != null:
		var cr := -32.0 if _hud_hidden else -(HUD_W + 32.0)
		tw.tween_property(_choice_layer, "offset_right", cr, 0.25)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_textbox() -> void:
	_box = Control.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_box.offset_left = 22
	_box.offset_right = -(HUD_W + 32.0)
	_box.offset_top = -112
	_box.offset_bottom = -16
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel",
		UiKit.box(Color(0.024, 0.059, 0.098, 0.88), 14, Color(0.16, 0.36, 0.50, 0.85), 1, 0))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(frame)

	var accent := ColorRect.new()
	accent.color = GameDefs.C_ICE
	accent.position = Vector2(0, 12)
	accent.size = Vector2(3, 28)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(accent)

	var bm := UiKit.margin(22, 8, 22, 6)
	bm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(bm)
	var bcol := UiKit.vbox(4)
	bcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bm.add_child(bcol)

	_speaker = UiKit.label("", 16, GameDefs.C_ICE)
	_speaker.add_theme_font_override("font", UiKit.bold_font())
	bcol.add_child(_speaker)

	_text = UiKit.wrapped("", 19, GameDefs.C_TEXT)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_constant_override("line_spacing", 7)
	bcol.add_child(_text)

	# 内嵌简洁选项列表：显示选项时占用正文位置，一行一个
	_choice_inline = UiKit.vbox(6)
	_choice_inline.visible = false
	bcol.add_child(_choice_inline)

	# 继续指示符：悬浮在框右下角，不再占一整行高度
	_caret = UiKit.label("", 14, GameDefs.C_ICE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_caret.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_caret.offset_left = -140.0
	_caret.offset_top = -28.0
	_caret.offset_right = -12.0
	_caret.offset_bottom = -8.0
	_caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_caret)


## 依据文本行数收放对话框高度（矮文本约为一半高，长文本自动长高）
func _fit_box_after_frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _box == null or _text == null or _speaker == null:
		return
	var fs := float(_text.get_theme_font_size("font_size"))
	var sf := float(_speaker.get_theme_font_size("font_size")) if _speaker.visible else 0.0
	var gap := 4.0 if sf > 0.0 else 0.0
	var content := 14.0 + sf * 1.35 + gap + fs * 1.45 * float(_text.get_line_count())
	_fit_box_to(clampf(content, BOX_H_MIN, BOX_H_MAX))


## 直接把对话框高度收到指定值（底部锚点不变，向上收放）
func _fit_box_to(h: float) -> void:
	if _box == null:
		return
	var tw := create_tween()
	tw.tween_property(_box, "offset_top", -16.0 - h, 0.18)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_choice_layer() -> void:
	_choice_layer = Control.new()
	# 稳定名称：回归测试与调试都靠它定位选项层
	_choice_layer.name = "ChoiceLayer"
	_choice_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_choice_layer.offset_left = 22
	_choice_layer.offset_right = -(HUD_W + 32.0)
	_choice_layer.offset_top = 84
	_choice_layer.offset_bottom = 330
	_choice_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_layer.visible = false
	add_child(_choice_layer)

	var ccol := UiKit.vbox(8)
	ccol.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ccol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_layer.add_child(ccol)

	_choice_head = UiKit.label("", 17, GameDefs.C_GOLD)
	_choice_head.add_theme_font_override("font", UiKit.bold_font())
	ccol.add_child(_choice_head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	ccol.add_child(scroll)

	# 原神式：选项列不铺满整行，居中且限宽，视觉更轻
	_choice_box = UiKit.vbox(10)
	_choice_box.custom_minimum_size = Vector2(560, 0)
	_choice_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_choice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_choice_box)


func _refresh_top() -> void:
	var cm := GameDefs.chapter_by_id(_chapter)
	if _top_chip != null:
		_top_chip.text = "第 %d 章" % int(cm.get("index", 1))
	if _top_title != null:
		_top_title.text = "%s　·　%s" % [String(cm.get("title", "")), String(cm.get("location", ""))]


func _toggle_auto() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.auto_advance = not bool(gs.auto_advance)
	gs.save_settings()
	_auto_btn.text = "自动：开" if gs.auto_advance else "自动：关"


# ===========================================================================
# 流程分发
# ===========================================================================
func _start_flow() -> void:
	var sd := get_node_or_null("/root/StoryData")
	var gs := get_node_or_null("/root/GameState")
	var nav := get_node_or_null("/root/Navigator")

	var chapter := "ch1"
	if gs != null and String(gs.current_chapter) != "":
		chapter = String(gs.current_chapter)
	if nav != null and nav.params is Dictionary and Dictionary(nav.params).has("chapter"):
		var pc := String(Dictionary(nav.params)["chapter"])
		if pc != "":
			chapter = pc

	var target := String(gs.current_node) if gs != null else ""
	if target == "" or not bool(sd.has_node_data(target)):
		target = String(sd.chapter_start(chapter))
	else:
		var nd: Dictionary = sd.get_node_data(target)
		if String(nd.get("type", "")) == "ending":
			target = String(sd.chapter_start(chapter))

	# 章节起点仍取不到 → 从第一章开始兜底
	if target == "":
		chapter = "ch1"
		target = String(sd.chapter_start("ch1"))
	if target == "":
		_toast_error("剧情文件里找不到任何章节起点。")
		return

	_chapter = chapter
	_refresh_top()
	_apply_bgm()
	if gs != null:
		_auto_btn.text = "自动：开" if bool(gs.auto_advance) else "自动：关"
	_goto(target)


func _apply_bgm() -> void:
	var am := get_node_or_null("/root/AudioMgr")
	if am == null:
		return
	match _chapter:
		"ch3", "ch4":
			am.play_bgm("tense")
		"ch5":
			am.play_bgm("finale")
		_:
			am.play_bgm("calm")


func _goto(node_id: String) -> void:
	var sd := get_node_or_null("/root/StoryData")
	var gs := get_node_or_null("/root/GameState")
	if gs == null or sd == null:
		return
	if node_id == "":
		_toast_error("剧情在这里断了：上一节点没有指向任何 next。")
		return

	var nd: Dictionary = sd.get_node_data(node_id)
	if nd.is_empty():
		_toast_error("剧情节点缺失：%s" % node_id)
		return

	_node_id = node_id
	_node = nd
	_error_state = false
	gs.current_node = node_id
	var ntype := String(nd.get("type", "narration"))

	if ntype == "chapter":
		var cid := String(nd.get("chapter", _chapter))
		if cid != "":
			_chapter = cid
			gs.current_chapter = cid
			gs.unlock_chapter(cid)
			var nxtc := String(sd.next_chapter_id(cid))
			if nxtc != "":
				gs.unlock_chapter(nxtc)
		_apply_bgm()

	# 节点自带效果：只在首次抵达时结算，避免「去档案页再回来」重复加值
	var fresh: bool = gs.first_visit(node_id)
	var notes: Array[String] = []
	if fresh and nd.get("effects") is Dictionary:
		notes = gs.apply_effects(Dictionary(nd["effects"]))

	_refresh_top()
	gs.save_progress()
	_apply_visual(nd, ntype)

	# 族群归零 → 直接进入失败结局
	var death := String(gs.death_ending())
	if death != "" and ntype != "ending":
		_hide_choices()
		_set_box_visible(false)
		_busy = true
		_show_effects(notes, func() -> void:
			_busy = false
			_finish_ending(death))
		return

	match ntype:
		"narration", "dialogue":
			_hide_choices()
			_show_text(nd, ntype)
			if not notes.is_empty():
				_show_effects(notes, Callable())
		"choice":
			_hide_choices()
			_show_text(nd, "dialogue")
			_pending_choice = nd
			if not notes.is_empty():
				_show_effects(notes, Callable())
		"popup":
			_hide_choices()
			_set_box_visible(false)
			_busy = true
			_voice_stop()   # 弹窗内容不需要配音，掐掉上一句残留语音
			var p: Dictionary = nd.get("popup", {}) if nd.get("popup") is Dictionary else {}
			var lines: Array = p.get("lines", []) if p.get("lines") is Array else []
			var nxt_p := String(nd.get("next", ""))
			_popup.fast_mode = fast_mode
			_bg.set_video_paused(true)   # 弹窗打开时暂停后方视频
			_popup.open(String(p.get("title", "简报")), lines, String(p.get("tone", "info")),
				func() -> void:
					_busy = false
					_bg.set_video_paused(false)   # 关闭弹窗后恢复播放
					_goto(nxt_p))
		"qte":
			_hide_choices()
			_show_text(nd, "dialogue")
			_pending_qte = nd
		"chapter":
			_hide_choices()
			_set_box_visible(false)
			_voice_stop()
			_busy = true
			var nxt_c := String(nd.get("next", ""))
			_show_chapter_card(String(nd.get("chapter", _chapter)),
				func() -> void:
					_busy = false
					_goto(nxt_c))
		"resolve":
			_hide_choices()
			_set_box_visible(false)
			var branches: Array = nd.get("branches", []) if nd.get("branches") is Array else []
			_goto(String(gs.resolve_branch(branches, String(nd.get("next", "")))))
		"ending":
			_hide_choices()
			_set_box_visible(false)
			_voice_stop()
			_finish_ending(String(nd.get("ending", "")))
		_:
			_hide_choices()
			_show_text(nd, "narration")
			if not notes.is_empty():
				_show_effects(notes, Callable())


func _apply_visual(nd: Dictionary, ntype: String) -> void:
	var gs := get_node_or_null("/root/GameState")
	if nd.has("bg"):
		var b := String(nd["bg"])
		if b != "":
			_bg.set_scene(b)
	elif ntype != "chapter":
		var cm := GameDefs.chapter_by_id(_chapter)
		_bg.set_scene(String(cm.get("bg", _chapter)))
	# CG 动画：节点自带 video 优先，其次章节卡用它所属章节的默认镜头。
	# 没写 video 的节点沿用上一个镜头（画面连续，不会每句话闪一次）。
	var vk := String(nd.get("video", ""))
	if vk == "" and ntype == "chapter":
		vk = String(GameDefs.chapter_by_id(String(nd.get("chapter", _chapter))).get("video", ""))
	if gs != null and not bool(gs.video_on):
		_bg.set_video_enabled(false)      # 设置里关了动画 → 回静态插画
	elif vk != "":
		_bg.set_video(vk)
	if nd.has("fx"):
		_bg.play_fx(String(nd["fx"]))


# ===========================================================================
# 文本演出
# ===========================================================================
func _show_text(nd: Dictionary, ntype: String) -> void:
	_set_box_visible(true)
	_text.visible = true
	if _choice_inline != null:
		_choice_inline.visible = false
	var full_text := String(nd.get("text", ""))
	var sp_raw := String(nd.get("speaker", ""))
	# 镜头语言/环境细节不进对话框：以电影字幕形式浮在画面上并自动推进
	if ntype == "narration" and (bool(nd.get("cinematic", false))
			or _is_cinematic_text(full_text) or _is_cinematic_speaker(sp_raw)):
		_show_cinematic_caption(full_text)
		return
	var speaker := String(nd.get("speaker", ""))
	if speaker == "":
		speaker = "雪翼" if ntype == "dialogue" else ""
	_speaker.text = speaker
	_speaker.visible = speaker != ""
	_speaker.add_theme_color_override("font_color",
		GameDefs.C_ICE if ntype == "dialogue" else GameDefs.C_GOLD)

	_full = String(nd.get("text", ""))
	_text.text = _full
	_fit_box_after_frame()
	_text.add_theme_color_override("font_color",
		GameDefs.C_TEXT if ntype == "dialogue" else Color("#cfe4f2"))
	var gs_t := get_node_or_null("/root/GameState")
	var fscale := float(gs_t.font_scale) if gs_t != null else 1.0
	_text.add_theme_font_size_override("font_size", int(round(20.0 * fscale)))
	_speaker.add_theme_font_size_override("font_size", int(round(17.0 * fscale)))
	_typed = 0.0
	_typing = true
	_advance_ready = false
	_text.visible_characters = 0
	_caret.text = ""
	_auto_timer = 0.0
	_idle_timer = 0.0
	_type_marks = 0
	# 配音：该节点有对应音频就播（换节点时上一句会被自动打断）
	if not fast_mode:
		var am_v := get_node_or_null("/root/AudioMgr")
		if am_v != null:
			am_v.play_voice(String(nd.get("id", "")))


func _set_box_visible(v: bool) -> void:
	if _box != null:
		_box.visible = v


# ===========================================================================
# 电影字幕：镜头语言/环境细节不走对话框，浮在画面下三分之一并自动推进
# ===========================================================================
var _caption: Label = null


func _is_cinematic_speaker(sp: String) -> bool:
	return sp.contains("镜头") or sp.contains("环境") or sp.contains("细节")


func _is_cinematic_text(t: String) -> bool:
	if t.length() >= 2 and t.begins_with("（") and t.ends_with("）"):
		return true
	for k: String in ["镜头", "远景", "全景", "特写", "俯拍", "俯冲", "航拍", "转场", "机位"]:
		if t.contains(k):
			return true
	return false


func _ensure_caption() -> Label:
	if _caption != null and is_instance_valid(_caption):
		return _caption
	var wrap := UiKit.margin(170, 0, 170, 0)
	wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.offset_top = -300
	wrap.offset_bottom = -220
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)
	_caption = UiKit.wrapped("", 21, Color("#dcecf7"))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_caption.add_theme_constant_override("shadow_offset_x", 0)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	_caption.add_theme_constant_override("shadow_outline_size", 8)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_caption)
	return _caption


func _show_cinematic_caption(text: String) -> void:
	_set_box_visible(false)
	_hide_choices()
	var cap := _ensure_caption()
	cap.text = text
	cap.visible = true
	cap.modulate.a = 0.0
	_advance_ready = false
	_typing = false
	# 镜头字幕不配语音，顺带掐掉上一节点残留的配音
	_voice_stop()
	var dur := clampf(2.0 + float(text.length()) * 0.045, 2.6, 6.0)
	var tw := create_tween()
	tw.tween_property(cap, "modulate:a", 1.0, 0.45)
	tw.tween_interval(dur)
	tw.tween_property(cap, "modulate:a", 0.0, 0.45)
	tw.tween_callback(func() -> void:
		cap.visible = false
		_goto(String(_node.get("next", ""))))


func _process(delta: float) -> void:
	_blink += delta
	var gs := get_node_or_null("/root/GameState")

	if _typing:
		var speed := 55.0
		if gs != null:
			speed = maxf(float(gs.text_speed), 8.0)
		_typed += delta * speed
		var total := _full.length()
		var shown := int(floor(_typed))
		_text.visible_characters = mini(shown, total)
		# 键盘敲击音：每显示 2 个字响一声，保证语速快时也不会糊成一片
		if shown > _type_marks and shown < total and not fast_mode:
			_type_marks = shown + 2
			_play_type_click(shown)
		if shown >= total:
			_typing = false
			_advance_ready = true
			_on_text_done()
		return

	if _advance_ready:
		_caret.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_blink * 4.0))
		if _busy or (_choice_layer != null and _choice_layer.visible):
			_idle_timer = 0.0
			return
		# 自动模式：按设置间隔推进
		if gs != null and bool(gs.auto_advance):
			_auto_timer += delta
			if _auto_timer >= float(gs.auto_delay):
				_auto_timer = 0.0
				_advance()
			return
		# 手动模式兜底：长时间无点击也继续走，避免画面停死
		_idle_timer += delta
		if _idle_timer >= _idle_limit():
			_idle_timer = 0.0
			_advance()


## 手动模式的闲置推进上限：给足阅读时间（按文本长度放宽），封顶 30 秒
func _idle_limit() -> float:
	return clampf(10.0 + float(_full.length()) * 0.12, 12.0, 30.0)


## 逐字显示时的键盘敲击音。标点与空白不发声——否则语速一快就成了
## 一串没有节奏的「哒哒哒」，听着像坏掉的打印机。
func _play_type_click(shown: int) -> void:
	var n := _full.length()
	if n > 0:
		var idx := clampi(shown - 1, 0, n - 1)
		var ch := _full.substr(idx, 1)
		if "，。！？；：、…—「」（）《》 \n\t".contains(ch):
			return
	var am := get_node_or_null("/root/AudioMgr")
	if am != null:
		am.play_type()


func _voice_stop() -> void:
	var am := get_node_or_null("/root/AudioMgr")
	if am != null:
		am.stop_voice()


func _on_text_done() -> void:
	if not _pending_choice.is_empty():
		var nd := _pending_choice
		_pending_choice = {}
		_show_choices(nd)
		return
	if not _pending_qte.is_empty():
		var nd2 := _pending_qte
		_pending_qte = {}
		_start_qte(nd2)
		return
	_caret.text = "▾ 点击继续"


func _advance() -> void:
	if _busy:
		return
	if _error_state:
		_error_state = false
		var nav := get_node_or_null("/root/Navigator")
		if nav != null:
			nav.home()
		return
	if _typing:
		_typing = false
		_text.visible_characters = -1
		_advance_ready = true
		_on_text_done()
		return
	if not _advance_ready:
		return
	if _choice_layer != null and _choice_layer.visible:
		return
	var ntype := String(_node.get("type", ""))
	if ntype != "narration" and ntype != "dialogue":
		return
	_advance_ready = false
	_caret.text = ""
	var nxt := String(_node.get("next", ""))
	if _node.get("branch") is Array and not Array(_node["branch"]).is_empty():
		var gs := get_node_or_null("/root/GameState")
		if gs != null:
			nxt = String(gs.resolve_branch(Array(_node["branch"]), nxt))
	_goto(nxt)


# ===========================================================================
# 选项
# ===========================================================================
func _hide_choices() -> void:
	if _choice_inline != null:
		_choice_inline.visible = false
		for c: Node in _choice_inline.get_children():
			_choice_inline.remove_child(c)
			c.queue_free()
	if _text != null:
		_text.visible = true
	if _choice_layer == null:
		return
	_choice_layer.visible = false
	for c: Node in _choice_box.get_children():
		_choice_box.remove_child(c)
		c.queue_free()


func _show_choices(nd: Dictionary) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or _choice_inline == null:
		return
	for c: Node in _choice_inline.get_children():
		_choice_inline.remove_child(c)
		c.queue_free()

	# 选项直接在对话框内展示：说话人行显示提示语，正文让位给选项列表
	_set_box_visible(true)
	_speaker.text = String(nd.get("prompt", "做出你的选择"))
	_speaker.add_theme_color_override("font_color", GameDefs.C_GOLD)
	_text.visible = false
	_text.text = ""
	_caret.text = ""
	_choice_inline.visible = true
	# 复用 _choice_layer.visible 作为状态位：等待选择期间点击不会推进剧情
	_choice_layer.visible = true

	var opts: Array = nd.get("options", []) if nd.get("options") is Array else []
	for i: int in range(opts.size()):
		var ov: Variant = opts[i]
		if not (ov is Dictionary):
			continue
		var o: Dictionary = ov
		var locked := false
		if o.has("require"):
			locked = not gs.check_all(o["require"])
		var btn := Button.new()
		# 简洁展示：只显示选项本身，不显示后果与数值变化
		btn.text = "▸ " + String(o.get("text", ""))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.custom_minimum_size = Vector2(0, 34)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color",
			GameDefs.C_MUTED if locked else GameDefs.C_TEXT)
		btn.add_theme_color_override("font_hover_color", GameDefs.C_ICE)
		btn.add_theme_color_override("font_pressed_color", GameDefs.C_ICE)
		btn.add_theme_color_override("font_disabled_color", GameDefs.C_MUTED)
		btn.add_theme_stylebox_override("normal",
			UiKit.box(Color(1, 1, 1, 0.04), 8, Color(0.16, 0.36, 0.5, 0.4), 1))
		btn.add_theme_stylebox_override("hover",
			UiKit.box(Color(0.12, 0.3, 0.42, 0.4), 8, Color(0.3, 0.6, 0.8, 0.8), 1))
		btn.add_theme_stylebox_override("pressed",
			UiKit.box(Color(0.16, 0.4, 0.55, 0.55), 8, Color(0.3, 0.6, 0.8, 0.9), 1))
		btn.add_theme_stylebox_override("disabled",
			UiKit.box(Color(1, 1, 1, 0.02), 8, Color(1, 1, 1, 0.08), 1))
		if locked:
			btn.disabled = true
		else:
			btn.pressed.connect(_on_choice.bind(o))
		_choice_inline.add_child(btn)

	# 高度按选项数量收放
	var n := float(_choice_inline.get_child_count())
	var h := clampf(14.0 + 17.0 * 1.35 + 6.0 + (34.0 * n + 6.0 * maxf(n - 1.0, 0.0)) + 8.0,
		BOX_H_MIN, 240.0)
	_fit_box_to(h)

	_choice_inline.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_choice_inline, "modulate:a", 1.0, 0.18)


func _on_choice(opt: Dictionary) -> void:
	if _busy:
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.choice_log.append({
		"node": _node_id,
		"chapter": _chapter,
		"text": String(opt.get("text", "")),
	})
	var notes: Array[String] = []
	if opt.get("effects") is Dictionary:
		notes = gs.apply_effects(Dictionary(opt["effects"]))
	if opt.get("flags") is Dictionary:
		for k: String in Dictionary(opt["flags"]).keys():
			gs.flags[k] = Dictionary(opt["flags"])[k]
	gs.save_progress()

	var nxt := String(opt.get("next", ""))
	if opt.get("branch") is Array and not Array(opt["branch"]).is_empty():
		nxt = String(gs.resolve_branch(Array(opt["branch"]), nxt))

	_hide_choices()
	_set_box_visible(false)
	var am := get_node_or_null("/root/AudioMgr")
	if am != null:
		am.play_sfx("confirm")
	if notes.is_empty():
		_goto(nxt)
	else:
		_busy = true
		_show_effects(notes, func() -> void:
			_busy = false
			_goto(nxt))


# ===========================================================================
# QTE
# ===========================================================================
func _start_qte(nd: Dictionary) -> void:
	var q: Dictionary = nd.get("qte", {}) if nd.get("qte") is Dictionary else {}
	_busy = true
	_set_box_visible(false)
	var nxt_ok := String(q.get("success_next", ""))
	var nxt_bad := String(q.get("fail_next", ""))
	_qte.start(String(nd.get("prompt", "限时动作")), q,
		func(success: bool) -> void:
			_busy = false
			var gs := get_node_or_null("/root/GameState")
			var notes: Array[String] = []
			var branch: Dictionary = {}
			if q.get("success") is Dictionary and success:
				branch = Dictionary(q["success"])
			elif q.get("fail") is Dictionary and not success:
				branch = Dictionary(q["fail"])
			if gs != null and branch.get("effects") is Dictionary:
				notes = gs.apply_effects(Dictionary(branch["effects"]))
				gs.save_progress()
			var nxt := nxt_ok if success else nxt_bad
			if notes.is_empty():
				_goto(nxt)
			else:
				_busy = true
				_show_effects(notes, func() -> void:
					_busy = false
					_goto(nxt)))


# ===========================================================================
# 章节转场卡
# ===========================================================================
func _build_card_layer() -> void:
	_card_layer = Control.new()
	_card_layer.name = "CardLayer"
	_card_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.visible = false
	add_child(_card_layer)


func _show_chapter_card(cid: String, on_done: Callable) -> void:
	var sd := get_node_or_null("/root/StoryData")
	var cm: Dictionary = sd.chapter_meta(cid) if sd != null else GameDefs.chapter_by_id(cid)
	var accent: Color = cm.get("accent", GameDefs.C_ICE)

	for c: Node in _card_layer.get_children():
		_card_layer.remove_child(c)
		c.queue_free()

	var scrim := ColorRect.new()
	scrim.color = Color(0.006, 0.020, 0.035, 0.90)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.add_child(center)

	var w := Control.new()
	w.custom_minimum_size = Vector2(760, 0)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(w)

	var inner := UiKit.vbox(12)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.add_child(inner)

	inner.add_child(UiKit.label("第 %d 章" % int(cm.get("index", 1)), 22, accent,
		HORIZONTAL_ALIGNMENT_CENTER))

	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(76, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(bar)

	var t := UiKit.label(String(cm.get("title", "")), 56, GameDefs.C_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_font_override("font", UiKit.bold_font())
	inner.add_child(t)

	inner.add_child(UiKit.label(String(cm.get("subtitle", "")), 21, accent,
		HORIZONTAL_ALIGNMENT_CENTER))
	inner.add_child(UiKit.spacer(4))

	inner.add_child(UiKit.label(
		"%s　·　%s" % [String(cm.get("location", "")), String(cm.get("weather", ""))],
		16, GameDefs.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	var sum_l := UiKit.wrapped(String(cm.get("summary", "")), 18, Color("#b6d2e4"))
	sum_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(sum_l)

	var am := get_node_or_null("/root/AudioMgr")
	if am != null:
		am.play_sfx("confirm")

	_card_layer.visible = true
	_card_layer.modulate.a = 1.0 if fast_mode else 0.0
	if fast_mode:
		if on_done.is_valid():
			on_done.call()
		return
	var tw := create_tween()
	tw.tween_property(_card_layer, "modulate:a", 1.0, 0.45)
	tw.tween_interval(1.8)
	tw.tween_property(_card_layer, "modulate:a", 0.0, 0.45)
	tw.tween_callback(func() -> void:
		_card_layer.visible = false
		if on_done.is_valid():
			on_done.call())


# ===========================================================================
# 结算浮层
# ===========================================================================
func _show_effects(notes: Array[String], on_done: Callable) -> void:
	# 快速模式不等结算动画，直接跳过——数值早已落地，演出只是糖
	if fast_mode:
		if on_done.is_valid():
			on_done.call()
		return
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(holder)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(center)

	var card := UiKit.panel(Color(0.035, 0.086, 0.137, 0.97), 14, GameDefs.C_ICE_DIM, 1, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)

	var m := UiKit.margin(30, 18, 30, 18)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(m)
	var col := UiKit.vbox(8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)

	var head := UiKit.label("本次结算", 17, GameDefs.C_ICE, HORIZONTAL_ALIGNMENT_CENTER)
	head.add_theme_font_override("font", UiKit.bold_font())
	col.add_child(head)
	col.add_child(UiKit.hsep(Color(0.20, 0.44, 0.60, 0.8), 1))
	for n: String in notes:
		var c := GameDefs.C_ICE
		if n.contains("获得证据"):
			c = GameDefs.C_GOLD
		elif n.contains("解锁科技"):
			c = GameDefs.C_COOP
		elif n.contains("+"):
			c = GameDefs.C_COOP
		elif n.contains("-"):
			c = GameDefs.C_WARN
		col.add_child(UiKit.label("· " + n, 18, c, HORIZONTAL_ALIGNMENT_CENTER))

	holder.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.16)
	tw.tween_interval(1.2)
	tw.tween_property(holder, "modulate:a", 0.0, 0.22)
	tw.tween_callback(func() -> void:
		holder.queue_free()
		if on_done.is_valid():
			on_done.call())


# ===========================================================================
# 结局
# ===========================================================================
func _finish_ending(eid: String) -> void:
	if eid == "":
		_toast_error("结局 id 为空。")
		return
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.finished_ending = eid
		for ch: Dictionary in GameDefs.CHAPTERS:
			gs.unlock_chapter(String(ch["id"]))
		gs.save_progress()
	_busy = true
	_bg.play_fx("flashice")
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void:
		var nav := get_node_or_null("/root/Navigator")
		if nav != null:
			nav.go_with(ENDING_SCENE, { "ending": eid }))


# ===========================================================================
# 输入
# ===========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if _busy or (_popup != null and _popup.is_open()) or (_qte != null and _qte.is_active()):
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_ESCAPE:
				var nav := get_node_or_null("/root/Navigator")
				if nav != null:
					nav.home()
				return
			if k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
				_advance()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_advance()


func _nav(path: String) -> void:
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.go(path)


func _toast_error(msg: String) -> void:
	push_error("[剧情] %s" % msg)
	if _text == null:
		return
	_set_box_visible(true)
	_text.visible = true
	_error_state = true
	_pending_choice = {}
	_pending_qte = {}
	_speaker.text = "系统"
	_speaker.visible = true
	_speaker.add_theme_color_override("font_color", GameDefs.C_DANGER)
	_text.text = msg
	_fit_box_after_frame()
	_text.visible_characters = -1
	_typing = false
	_advance_ready = true
	_caret.text = "▾ 点击返回主菜单"
