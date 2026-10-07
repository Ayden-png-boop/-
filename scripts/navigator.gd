extends Node
## Navigator —— 全局场景导航（autoload 单例）。
##
## 用一个栈记录玩家走过的场景路径，所有「返回」按钮统一调用 back()，
## 不再写死返回目标；同时提供一个轻量参数袋，让上一页给下一页传数据
## （例如章节选择页把「从哪一章开始」传给剧情页）。

const HOME := "res://scenes/main_menu.tscn"
const BOOT := "res://scenes/loading_screen.tscn"

var _stack: Array[String] = []

## 页面之间传参用的临时袋子。进入目标页面后由目标页面自行读取。
var params: Dictionary = {}


## 主动跳转：把当前场景压栈，再切换。
func go(path: String) -> void:
	if path == "":
		push_error("Navigator.go: path 为空")
		return
	var cur := _current_scene_path()
	if cur != "" and cur != path:
		_stack.append(cur)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Navigator: 无法切换到 %s (code %d)" % [path, err])


## 带参数跳转
func go_with(path: String, p: Dictionary) -> void:
	params = p.duplicate(true)
	go(path)


## 返回上一页；栈空时回主菜单。
func back() -> void:
	var target := HOME
	if not _stack.is_empty():
		target = _stack.pop_back()
	var err := get_tree().change_scene_to_file(target)
	if err != OK:
		push_error("Navigator: 无法返回 %s (code %d)" % [target, err])


## 回主菜单并清空历史
func home() -> void:
	_stack.clear()
	go(HOME)


func reset() -> void:
	_stack.clear()


func depth() -> int:
	return _stack.size()


func _current_scene_path() -> String:
	var tree := get_tree()
	if tree == null:
		return ""
	var cur := tree.current_scene
	if cur == null:
		return ""
	return cur.scene_file_path
