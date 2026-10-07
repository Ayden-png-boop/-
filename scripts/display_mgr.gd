extends Node
## DisplayMgr —— 窗口 / 全屏切换 + 分辨率适配（autoload 单例）。
##
## 与 project.godot 的 canvas_items + expand 拉伸策略配合：整套 UI 按
## 1152×648 设计，窗口变大或全屏时整体等比放大，而不是维持原始大小。

const MODE_WINDOWED := "windowed"
const MODE_FULLSCREEN := "fullscreen"
const BASE_SIZE := Vector2i(1152, 648)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_stretch()
	if _is_headless():
		return
	var want := false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		want = bool(gs.wants_fullscreen())
	_apply_fullscreen(want)


## 显式对齐根窗口拉伸参数：无论用编辑器、双击 exe 还是命令行启动，
## 画面都按 1152×648 随窗口与全屏等比放大。
func _apply_stretch() -> void:
	var w := get_window()
	if w == null:
		return
	w.content_scale_size = BASE_SIZE
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	w.content_scale_factor = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if _is_headless() or Engine.is_editor_hint():
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_F11 or k.physical_keycode == KEY_F11):
			toggle()
			get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	if _is_headless():
		return false
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func toggle() -> void:
	set_fullscreen(not is_fullscreen())


func set_fullscreen(on: bool) -> void:
	_apply_fullscreen(on)
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.set_fullscreen_flag(on)


func _apply_fullscreen(on: bool) -> void:
	if _is_headless():
		return
	var screen := DisplayServer.window_get_current_screen()
	var ssz := DisplayServer.screen_get_size(screen)
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		if ssz.x > 0 and ssz.y > 0:
			DisplayServer.window_set_size(ssz)
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var size := BASE_SIZE
		if ssz.x > 0 and ssz.y > 0:
			size.x = mini(size.x, int(ssz.x * 0.9))
			size.y = mini(size.y, int(ssz.y * 0.9))
		DisplayServer.window_set_size(size)
		if ssz.x > 0 and ssz.y > 0:
			DisplayServer.window_set_position(
				DisplayServer.screen_get_position(screen) + (ssz - size) / 2)


## 当前 UI 的实际缩放倍率（1.0 = 与设计分辨率 1:1）
func content_scale() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1.0
	var s := vp.get_final_transform().get_scale()
	return s.x if s.x > 0.0 else 1.0


func mode_label() -> String:
	if _is_headless():
		return "无头模式"
	return "全屏" if is_fullscreen() else "窗口"


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
