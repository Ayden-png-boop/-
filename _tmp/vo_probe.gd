extends SceneTree
func _initialize() -> void:
	var am := root.get_node_or_null("/root/AudioMgr")
	print("AudioMgr=", am != null)
	for id: String in ["c1_03", "c2_04", "ending_new_glacier", "not_exist"]:
		var path := "res://assets/audio/vo/%s.mp3" % id
		var ex := ResourceLoader.exists(path)
		var st: Resource = load(path) if ex else null
		print(id, " exists=", ex, " stream=", st != null, " class=", st.get_class() if st != null else "-",
			" len=", ("%.1f" % (st.get_length() if st != null else 0.0)))
	quit()
