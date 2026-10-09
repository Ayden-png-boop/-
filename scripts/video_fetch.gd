extends Node
## VideoFetch —— CG 视频下载器（Web 专用，常驻 /root）。
##
## 背景：Web 导出时 CG 视频不打进 pck（65MB 会拖死首屏），改为运行时下载。
## 必须独立成常驻节点：BgArt 跟随场景生灭，挂它身上下载会在切屏时被中断。
##
## 职责：
##   1. 游戏启动 2.5s 后，按「剧情出现顺序」把 CG 一条条预取到 user://cg；
##   2. BgArt 需要某条 CG 时调 prioritize(key) —— 提到队首并打断当前下载；
##   3. 单条串行下载，避免多流抢占那点出网带宽。
## BgArt 通过轮询 user:// 文件是否落盘来感知完成（解耦，互不持有引用）。

const URL_DIR := "video/"
const USER_DIR := "user://media/v1/cg/"
const WAIT_TIMEOUT_S := 60.0

var _queue: Array = []          ## 待下载 key（头部最优先）
var _busy_key := ""
var _http: HTTPRequest = null
var _started := false


func _ready() -> void:
	_start()


func _start() -> void:
	if _started:
		return
	_started = true
	if not OS.has_feature("web"):
		return                          # 桌面/移动端视频在 pck 里，无需下载
	await get_tree().create_timer(2.5).timeout
	if not is_inside_tree():
		return
	if _queue.is_empty():
		_queue = _story_video_keys()
	# 带宽分配：语音是剧情阻塞资源（P0），等语音预取全部完成再铺视频（P1）。
	# 最多等 45s 兜底；prioritize() 可随时越过此等待直接开播（P0 抢占）。
	var vf := get_node_or_null("/root/VoiceFetch")
	if vf == null:
		var t := Engine.get_main_loop()
		if t is SceneTree:
			vf = (t as SceneTree).root.get_node_or_null("VoiceFetch")
	var waited := 0.0
	while vf != null and not vf.all_done() and waited < 45.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		if not is_inside_tree():
			return
	_pump()


## 把 key 提到队首；若正在下载别的，先掐掉让它插队。
func prioritize(key: String) -> void:
	if FileAccess.file_exists(_user_path(key)) or _busy_key == key:
		_queue.erase(key)
		return
	var interrupted := _busy_key
	if interrupted != "":
		# 先清状态再 cancel，防止 cancel 触发的回调把流程抢跑
		_busy_key = ""
		_drop_http()
		_queue.erase(interrupted)
	_queue.erase(key)
	if interrupted != "":
		_queue = [key, interrupted] + _queue
	else:
		_queue = [key] + _queue
	_pump()


func _pump() -> void:
	if _busy_key != "" or not is_inside_tree():
		return
	while not _queue.is_empty():
		var k: String = _queue.pop_front()
		if FileAccess.file_exists(_user_path(k)):
			continue
		_begin(k)
		return


func _begin(k: String) -> void:
	_busy_key = k
	_http = HTTPRequest.new()
	_http.timeout = 90.0
	add_child(_http)
	_http.request_completed.connect(_on_done.bind(k))
	var err := _http.request(_abs_url(k))
	if err != OK:
		push_warning("VideoFetch: CG 请求发起失败 %s (err=%d)" % [k, err])
		_drop_http()
		_busy_key = ""
		_pump()


func _on_done(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, k: String) -> void:
	if k != _busy_key:
		return                              # 已被 prioritize 掐掉的旧请求
	_drop_http()
	_busy_key = ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 4096:
		DirAccess.make_dir_recursive_absolute(USER_DIR)
		var f := FileAccess.open(_user_path(k), FileAccess.WRITE)
		if f != null:
			f.store_buffer(body)
			f.close()
		else:
			push_warning("VideoFetch: 无法写入 %s" % _user_path(k))
	else:
		push_warning("VideoFetch: CG %s 下载失败 (result=%d code=%d size=%d)" % [k, result, code, body.size()])
	_pump()


func _drop_http() -> void:
	if _http != null and is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
	_http = null


func _user_path(key: String) -> String:
	return USER_DIR + key + ".ogv"


## 把相对路径拼成绝对 URL（Godot 的 HTTPRequest 不接受相对路径）
func _abs_url(key: String) -> String:
	var rel := URL_DIR + key + ".ogv"
	if not OS.has_feature("web"):
		return rel
	var safe := rel.replace("\\", "").replace("\"", "").replace("'", "")
	var u: Variant = JavaScriptBridge.eval(
		"new URL(\"%s\", document.baseURI).href" % safe, true)
	if u == null:
		return rel
	return str(u)


## 从剧本里按出现顺序抽出所有 video key（story.json 在 pck 内，同步可读）
func _story_video_keys() -> Array:
	var keys: Array = []
	var path := "res://data/story.json"
	if not FileAccess.file_exists(path):
		return keys
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return keys
	var txt := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if data == null:
		return keys
	var seen := {}
	_collect_video_keys(data, keys, seen)
	return keys


func _collect_video_keys(node: Variant, out: Array, seen: Dictionary) -> void:
	if node is Dictionary:
		for k: Variant in (node as Dictionary).keys():
			var v: Variant = (node as Dictionary)[k]
			if str(k) == "video" and v is String and str(v) != "" and not seen.has(v):
				seen[v] = true
				out.append(str(v))
			else:
				_collect_video_keys(v, out, seen)
	elif node is Array:
		for v: Variant in (node as Array):
			_collect_video_keys(v, out, seen)
