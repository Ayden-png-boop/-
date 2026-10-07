extends Node
## 只负责把驱动节点挂到 /root 下：这样驱动自己不是 current_scene，
## 即使被测页面触发 change_scene_to_file 也不会被释放。
##
## 驱动脚本若加载失败（语法错误等），必须立刻退出——否则会一直挂着等超时。

func _ready() -> void:
	var script := load("res://_tmp/route_test_driver.gd")
	if script == null or not (script is GDScript):
		print("BOOT_FAIL 驱动脚本加载失败，见上方 Parse Error")
		get_tree().quit(1)
		return
	var d: Node = (script as GDScript).new()
	if d == null:
		print("BOOT_FAIL 驱动脚本无法实例化")
		get_tree().quit(1)
		return
	d.name = "RouteTestDriver"
	get_tree().root.add_child.call_deferred(d)
