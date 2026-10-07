extends Node
## 截图引导：把游戏切到指定场景后停住，配合 --write-movie 渲染真实画面。
## 用法：godot --path . --write-movie <out.png> --fixed-fps 30 --quit-after N \
##           res://_tmp/shot.tscn -- <场景路径> [章节id]
##
## 注意：必须等一帧再导航，否则 change_scene_to_file 会在树的构建期报
## 「parent busy」而切换失败。

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var target := "res://scenes/main_menu.tscn"
	if args.size() > 0:
		target = String(args[0])
	var p := {}
	if args.size() > 1 and String(args[1]) != "":
		p = { "chapter": String(args[1]) }

	await get_tree().process_frame
	var nav := get_node_or_null("/root/Navigator")
	if nav != null:
		nav.go_with(target, p)
	else:
		print("SHOT_ERR 找不到 Navigator")
