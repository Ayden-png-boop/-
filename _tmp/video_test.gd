extends SceneTree
## CG 视频资源验证：能否作为 VideoStreamTheora 加载 + 能否真的播放出帧。
## 在项目根目录用 --headless --path . --script 运行。

var _frame := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_run_checks()
		return false
	if _frame >= 30:
		_report()
		return true
	return false


var _keys: Array[String] = []
var _bad: Array[String] = []
var _bg: BgArt = null
var _playing := false
var _pos := 0.0


func _run_checks() -> void:
	var dir := DirAccess.open("res://assets/video")
	if dir == null:
		print("VIDEO_FAIL cannot open res://assets/video")
		return
	for f: String in dir.get_files():
		if f.ends_with(".ogv"):
			_keys.append(f.get_basename())
	_keys.sort()

	for k: String in _keys:
		var p := "res://assets/video/%s.ogv" % k
		if not ResourceLoader.exists(p):
			_bad.append(k + ":exists=false")
			continue
		var r: Resource = load(p)
		if r == null:
			_bad.append(k + ":load=null")
		elif not (r is VideoStream):
			_bad.append(k + ":type=" + r.get_class())
		print("VIDEO_LOAD %s -> %s" % [k, "OK" if r is VideoStream else "FAIL"])

	# 实际播放测试：拿第一个片段挂到 BgArt 上播 0.5 秒
	if not _keys.is_empty():
		_bg = BgArt.new()
		_bg.size = Vector2(1152, 648)
		root.add_child(_bg)
		_bg.set_video(_keys[0])


func _report() -> void:
	if _bg != null and _bg.video_key != "":
		var p: VideoStreamPlayer = _bg.get_node_or_null("VideoLayer") as VideoStreamPlayer
		if p != null:
			_playing = p.is_playing()
			_pos = p.get_stream_position()
			var tex := p.get_video_texture()
			var tex_ok := tex != null and tex.get_width() > 0
			print("VIDEO_PLAY playing=%s pos=%.2f tex=%s(%dx%d)" % [
				_playing, _pos, tex_ok, tex.get_width() if tex != null else 0,
				tex.get_height() if tex != null else 0])
		else:
			print("VIDEO_PLAY player=null")
	_bg = null
	var n_loaded := 0
	for k: String in _keys:
		if not _bad.any(func(b: String) -> bool: return b.begins_with(k + ":")):
			n_loaded += 1
	print("VIDEO_TOTAL keys=%d loaded=%d bad=%d playing=%s" % [
		_keys.size(), n_loaded, _bad.size(), _playing])
	for b: String in _bad:
		print("VIDEO_BAD ", b)
	print("VIDEO_DONE")
