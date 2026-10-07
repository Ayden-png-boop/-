class_name UiKit
extends RefCounted
## UiKit —— 统一的视觉语言（主题 + 控件工厂）。
##
## 全项目不使用编辑器拖拽的 .tscn 布局，所有界面都在代码里按同一套 UiKit
## 规则搭出来：配色、圆角、描边、字号、间距只有一处定义，改一个数就全局生效。

const FONT_SANS := "res://assets/fonts/NotoSansSC.ttf"

## 设计分辨率，与 project.godot / DisplayMgr 保持一致
const BASE_W := 1152.0
const BASE_H := 648.0

static var _theme: Theme = null
static var _font: Font = null
static var _font_bold: FontVariation = null


# ===========================================================================
# 字体
# ===========================================================================
static func font() -> Font:
	if _font != null:
		return _font
	# 优先走导入系统；若资源尚未导入（例如纯命令行首次运行），
	# 退回到运行时动态加载，保证中文永远有字形可用。
	if ResourceLoader.exists(FONT_SANS):
		var r: Resource = load(FONT_SANS)
		if r is Font:
			_font = r
	if _font == null:
		var ff := FontFile.new()
		if ff.load_dynamic_font(FONT_SANS) == OK:
			_font = ff
	if _font == null:
		push_warning("UiKit: 未能加载中文字体 %s，中文可能显示为方块" % FONT_SANS)
		_font = ThemeDB.fallback_font
	return _font


static func bold_font() -> FontVariation:
	if _font_bold != null:
		return _font_bold
	var fv := FontVariation.new()
	fv.base_font = font()
	fv.variation_embolden = 0.55
	_font_bold = fv
	return _font_bold


static func mono_font() -> Font:
	return font()


# ===========================================================================
# 主题
# ===========================================================================
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20

	# ---- Label ----
	t.set_color("font_color", "Label", GameDefs.C_TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("line_spacing", "Label", 8)

	# ---- Button ----
	t.set_stylebox("normal", "Button", box(GameDefs.C_PANEL, 10, GameDefs.C_LINE, 1))
	t.set_stylebox("hover", "Button", box(GameDefs.C_PANEL_HI, 10, GameDefs.C_ICE, 1))
	t.set_stylebox("pressed", "Button", box(GameDefs.C_DEEP, 10, GameDefs.C_ICE, 2))
	t.set_stylebox("disabled", "Button",
		box(Color(0.06, 0.10, 0.15, 0.7), 10, Color(0.16, 0.24, 0.32), 1))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", GameDefs.C_TEXT)
	t.set_color("font_hover_color", "Button", GameDefs.C_ICE)
	t.set_color("font_pressed_color", "Button", GameDefs.C_ICE)
	t.set_color("font_disabled_color", "Button", Color(0.42, 0.50, 0.58))
	t.set_font_size("font_size", "Button", 20)

	# ---- Panel ----
	t.set_stylebox("panel", "Panel", box(GameDefs.C_PANEL, 12, GameDefs.C_LINE, 1))
	t.set_stylebox("panel", "PanelContainer", box(GameDefs.C_PANEL, 12, GameDefs.C_LINE, 1))

	# ---- RichTextLabel ----
	t.set_color("default_color", "RichTextLabel", GameDefs.C_TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 20)
	t.set_font_size("bold_font_size", "RichTextLabel", 20)

	# ---- ProgressBar ----
	var pb_bg := box(Color(0.03, 0.07, 0.12, 0.9), 6, GameDefs.C_LINE, 1)
	pb_bg.content_margin_left = 0
	pb_bg.content_margin_right = 0
	pb_bg.content_margin_top = 0
	pb_bg.content_margin_bottom = 0
	var pb_fg := box(GameDefs.C_ICE, 6)
	pb_fg.content_margin_left = 0
	pb_fg.content_margin_right = 0
	pb_fg.content_margin_top = 0
	pb_fg.content_margin_bottom = 0
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fg)
	t.set_color("font_color", "ProgressBar", GameDefs.C_TEXT)

	# ---- HSlider ----
	t.set_stylebox("slider", "HSlider", box(Color(0.03, 0.07, 0.12, 0.9), 4, GameDefs.C_LINE, 1))
	t.set_stylebox("grabber_area", "HSlider", box(GameDefs.C_ICE_DIM, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GameDefs.C_ICE, 4))

	# ---- 分隔线 ----
	t.set_stylebox("separator", "HSeparator",
		box(Color(0.14, 0.30, 0.42, 0.8), 0))
	t.set_constant("separation", "HSeparator", 1)

	_theme = t
	return t


static func apply(root_node: Control) -> void:
	root_node.theme = theme()


# ===========================================================================
# StyleBox 工厂
# ===========================================================================
static func box(bg: Color, radius: int = 10, border: Color = Color.TRANSPARENT,
		border_w: int = 1, pad: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	sb.set_content_margin_all(pad)
	return sb


static func box_grad(top: Color, bottom: Color, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(0)
	sb.set_content_margin_all(0)
	# 用背景色 + 顶部高光模拟渐变质感（StyleBoxFlat 自身不支持渐变）
	sb.bg_color = top.lerp(bottom, 0.5)
	sb.border_color = top
	return sb


# ===========================================================================
# 控件工厂
# ===========================================================================
static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func label(text: String, size: int = 20, color: Color = GameDefs.C_TEXT,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func title(text: String, size: int = 44, color: Color = GameDefs.C_TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", bold_font())
	l.add_theme_constant_override("line_spacing", 6)
	return l


static func wrapped(text: String, size: int = 20, color: Color = GameDefs.C_MUTED) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l


static func button(text: String, size: int = 20, min_h: int = 46) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, min_h)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_ALL
	return b


## 主行动按钮：冰青色实心
static func primary_button(text: String, size: int = 21, min_h: int = 50) -> Button:
	var b := button(text, size, min_h)
	b.add_theme_stylebox_override("normal", box(GameDefs.C_ICE_DIM, 10, GameDefs.C_ICE, 1))
	b.add_theme_stylebox_override("hover", box(GameDefs.C_ICE, 10, GameDefs.C_TEXT, 1))
	b.add_theme_stylebox_override("pressed", box(GameDefs.C_ICE_DIM.darkened(0.2), 10,
		GameDefs.C_TEXT, 2))
	b.add_theme_color_override("font_color", GameDefs.C_INK)
	b.add_theme_color_override("font_hover_color", GameDefs.C_INK)
	b.add_theme_color_override("font_pressed_color", GameDefs.C_INK)
	b.add_theme_font_override("font", bold_font())
	return b


static func ghost_button(text: String, size: int = 19, min_h: int = 42) -> Button:
	var b := button(text, size, min_h)
	var transparent := box(Color(0, 0, 0, 0), 10, GameDefs.C_LINE, 1)
	b.add_theme_stylebox_override("normal", transparent)
	b.add_theme_stylebox_override("hover", box(Color(0.09, 0.20, 0.30, 0.85), 10, GameDefs.C_ICE, 1))
	b.add_theme_stylebox_override("pressed", box(GameDefs.C_DEEP, 10, GameDefs.C_ICE, 2))
	return b


static func panel(color: Color = GameDefs.C_PANEL, radius: int = 12,
		border: Color = GameDefs.C_LINE, border_w: int = 1, pad: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius, border, border_w, pad))
	return p


static func panel_raw(color: Color, radius: int = 12) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(color, radius, Color.TRANSPARENT, 0, 0))
	return p


## 小标签片（chip），用于「选项3」「证据」「已解锁」等短标记
## 结构：单层 PanelContainer，内边距写在样式盒的 content_margin 上，
## 保证药丸背景始终包住文字（此前用外层 MarginContainer 会在容器布局中
## 把内层药丸压成文字大小，导致文字溢出背景）。
static func chip(text: String, color: Color = GameDefs.C_ICE, size: int = 15) -> PanelContainer:
	var sb := box(Color(color.r, color.g, color.b, 0.16), 999,
		Color(color.r, color.g, color.b, 0.55), 1, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, size, color)
	l.add_theme_font_override("font", bold_font())
	p.add_child(l)
	# 让 chip() 返回的节点既是容器又能取到内部 Label
	p.set_meta("chip_label", l)
	return p


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## 给自动换行文本一个「确定宽度」的容器。
## 裸 Control 包 VBox 的做法会让 VBox 拿到 0 宽度，自动换行标签于是每字一行、
## 高度炸开（实测 1480px）；HBox 里的裸 Label 又会被挤成 1px 竖条。
## 统一走这个 helper：VBox + 显式 custom_minimum_size.x。
static func block(children: Array, width: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(width, 0)
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Variant in children:
		if c is Node:
			v.add_child(c as Node)
	return v


## block() 的搭档：把内容推到左边、右侧留出空白
static func with_trailing_space(content: Control, trailing: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(content)
	if trailing > 0:
		h.add_child(hspacer(trailing))
	else:
		var pad := Control.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(pad)
	return h


static func margin(l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	return m


static func hsep(color: Color = GameDefs.C_LINE, h: int = 1) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hspacer(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 一个铺满屏幕、可作为页面根节点的 Control
static func screen_root(name_hint: String = "Screen") -> Control:
	var c := Control.new()
	c.name = name_hint
	full_rect(c)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	apply(c)
	return c


## 纯色遮罩
static func scrim(alpha: float = 0.72) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.01, 0.03, 0.05, alpha)
	full_rect(c)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


## 统一给按钮挂上音效
static func wire_sfx(b: Button, name: String = "click") -> Button:
	b.pressed.connect(func() -> void:
		var a := Engine.get_main_loop()
		if a is SceneTree:
			var am := (a as SceneTree).root.get_node_or_null("AudioMgr")
			if am != null:
				am.play_sfx(name))
	return b


# ===========================================================================
# 段落排版辅助
# ===========================================================================
## 中文正文的默认行距（Godot 的中文行高约为字号的 1.55~1.7 倍）
static func body_line_height(font_size: int) -> int:
	return int(ceil(float(font_size) * 1.72))


static func hex_to_color(hex: String, fallback: Color = GameDefs.C_ICE) -> Color:
	var s := hex.strip_edges()
	if s.begins_with("#"):
		s = s.substr(1)
	if s.length() != 6 and s.length() != 8:
		return fallback
	return Color(s)
