extends SceneTree
func _initialize() -> void:
	var c := UiKit.chip("第 3 章", GameDefs.C_ICE, 14)
	root.add_child(c)
	await process_frame
	await process_frame
	var l: Label = c.get_meta("chip_label")
	var m: MarginContainer = c.get_child(0)
	var p: PanelContainer = m.get_child(0)
	print("label min=", l.get_minimum_size(), " size=", l.size)
	print("pill  min=", p.get_minimum_size(), " size=", p.size)
	print("margin min=", m.get_minimum_size(), " size=", m.size)
	print("holder min=", c.get_minimum_size(), " size=", c.size)
	print("bold_font=", UiKit.bold_font())
	quit()
