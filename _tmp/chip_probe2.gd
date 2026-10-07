extends Node
func _ready() -> void:
	var gs := get_node("/root/GameState")
	gs.new_run()
	var nav := get_node("/root/Navigator")
	nav.params = { "chapter": "ch3", "node": "" }
	var ps: PackedScene = load("res://scenes/story_screen.tscn")
	var screen: Node = ps.instantiate()
	screen.fast_mode = true
	get_tree().root.add_child.call_deferred(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var chip: Control = _find(screen)
	if chip == null:
		print("CHIP NOT FOUND")
	else:
		var l: Label = chip.get_meta("chip_label")
		print("CHIPTEXT=", l.text)
		print("CHIP size=", chip.size, " min=", chip.get_minimum_size())
		print("LB size=", l.size, " min=", l.get_minimum_size())
		var p: Control = l.get_parent()
		print("PILL size=", p.size, " min=", p.get_minimum_size())
		var m: Control = p.get_parent()
		print("MARG size=", m.size, " min=", m.get_minimum_size())
	get_tree().quit()
func _find(n: Node) -> Control:
	if n is PanelContainer and n.has_meta("chip_label"):
		return n
	for c: Node in n.get_children():
		var r := _find(c)
		if r != null:
			return r
	return null
