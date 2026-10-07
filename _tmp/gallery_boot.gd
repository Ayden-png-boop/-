extends Node
## 画廊式截图：把每个界面依次实例化为子节点，各停留若干帧，
## 配合 --write-movie 一次性渲染出全部界面的真实画面。
##
## 用法：godot --path . --write-movie <out.png> --fixed-fps 30 --quit-after 140 \
##           res://_tmp/gallery.tscn

const SHOTS := [
	["res://scenes/main_menu.tscn", {}, 20],
	["res://scenes/chapter_select.tscn", {}, 20],
	["res://scenes/story_screen.tscn", {"chapter": "ch3"}, 30],
	["res://scenes/codex_screen.tscn", {}, 20],
	["res://scenes/settings_screen.tscn", {}, 20],
	["res://scenes/ending_screen.tscn", {"ending": "ending_new_glacier"}, 26],
]

func _ready() -> void:
	# 等一帧，避开树的构建期
	await get_tree().process_frame
	var nav := get_node_or_null("/root/Navigator")
	for s: Variant in SHOTS:
		var arr: Array = s
		var path := String(arr[0])
		var params: Dictionary = arr[1]
		var hold := int(arr[2])
		if nav != null:
			nav.params = params.duplicate(true)
		var ps: PackedScene = load(path)
		if ps == null:
			print("GALLERY_SKIP ", path)
			continue
		var inst = ps.instantiate()
		# 剧情页跳过章节转场卡，直接露出对话界面
		if path.contains("story"):
			inst.fast_mode = true
		add_child(inst)
		for i: int in range(hold):
			await get_tree().process_frame
		print("GALLERY_SHOT ", path)
		inst.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("GALLERY_DONE")
