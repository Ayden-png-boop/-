extends SceneTree
## 临时诊断：验证 5 首背景音乐能否通过导入系统加载（跑完可删）。
func _initialize() -> void:
	var ok := true
	for kind: String in ["menu", "calm", "tense", "finale", "collapse"]:
		var p := "res://assets/audio/bgm/%s.mp3" % kind
		if ResourceLoader.exists(p):
			var st: Resource = load(p)
			if st is AudioStreamMP3:
				st.loop = true
				print("OK      %s  %.1fs  loop=%s" % [kind, st.get_length(), st.loop])
			else:
				ok = false
				print("BADTYPE %s  -> %s" % [kind, st.get_class() if st != null else "null"])
		else:
			ok = false
			print("MISSING %s" % kind)
	quit(0 if ok else 1)
