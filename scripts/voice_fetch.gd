extends Node
## VoiceFetch —— 剧情配音下载器（Web 专用，懒创建常驻 /root）。
##
## 背景：Web 导出时 vo 语音不打进 pck（5MB，数百个碎片文件拖累首屏），
## 改为运行时按需下载 + 按剧情顺序预取。
##
## 职责：
##   1. 启动后按「剧情出现顺序」把 vo 一条条预取到 user://media/v1/vo；
##   2. AudioMgr 需要某条语音时调 prioritize(id) —— 提到队首；
##   3. 单条串行下载；语音碎片很小（平均 ~75KB），完成后才放行视频预取
##      （VideoFetch 会等待 all_done，实现 P0 语音 > P1 视频的带宽分配）。
## AudioMgr 通过轮询 user:// 文件落盘感知完成（与 VideoFetch/BgArt 同模式）。

const URL_DIR := "vo/"
const USER_DIR := "user://media/v1/vo/"
const WAIT_TIMEOUT_S := 20.0

var _queue: Array = []          ## 待下载 id（头部最优先）
var _manifest := {}             ## 剧本里出现过的 vo id -> true
var _busy_id := ""
var _http: HTTPRequest = null
var _started := false


func _ready() -> void:
	_start()


func _start() -> void:
	if _started:
		return
	_started = true
	if not OS.has_feature("web"):
		return                          # 桌面/移动端语音在 pck 里，无需下载
	_manifest = _story_voice_ids()
	if _manifest.is_empty():
		return                          # 没有语音可管（纯文本模式/数据缺失）
	# 语音是剧情推进的阻塞资源（P0），启动即预取，只等 1.2s 让引擎先喘口气
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():
		return
	_queue = _manifest.keys()
	_pump()


## 剧本里是否会出现这条语音（AudioMgr 用来决定「等下载」还是「直接放弃」）
func knows(id: String) -> bool:
	return _manifest.has(id)


## 全部预取完成（VideoFetch 以此判断可以开始铺视频）
func all_done() -> bool:
	return _busy_id == "" and _queue.is_empty()


## 把 id 提到队首；若正在下载别的语音，掐掉它（语音很小，代价可忽略）
func prioritize(id: String) -> void:
	if not _manifest.has(id):
		return
	if FileAccess.file_exists(_user_path(id)) or _busy_id == id:
		_queue.erase(id)
		return
	var interrupted := _busy_id
	if interrupted != "":
		_busy_id = ""
		_drop_http()
	_queue.erase(id)
	if interrupted != "":
		_queue = [id, interrupted] + _queue
	else:
		_queue = [id] + _queue
	_pump()


func _pump() -> void:
	if _busy_id != "" or not is_inside_tree():
		return
	while not _queue.is_empty():
		var k: String = _queue.pop_front()
		if FileAccess.file_exists(_user_path(k)):
			continue
		_begin(k)
		return


func _begin(k: String) -> void:
	_busy_id = k
	_http = HTTPRequest.new()
	_http.timeout = WAIT_TIMEOUT_S
	add_child(_http)
	_http.request_completed.connect(_on_done.bind(k))
	var err := _http.request(_abs_url(k))
	if err != OK:
		push_warning("VoiceFetch: 语音请求发起失败 %s (err=%d)" % [k, err])
		_drop_http()
		_busy_id = ""
		_pump()


func _on_done(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, k: String) -> void:
	if k != _busy_id:
		return                          # 已被 prioritize 掐掉的旧请求
	_drop_http()
	_busy_id = ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 512:
		DirAccess.make_dir_recursive_absolute(USER_DIR)
		var f := FileAccess.open(_user_path(k), FileAccess.WRITE)
		if f != null:
			f.store_buffer(body)
			f.close()
		else:
			push_warning("VoiceFetch: 无法写入 %s" % _user_path(k))
	else:
		push_warning("VoiceFetch: 语音 %s 下载失败 (result=%d code=%d size=%d)" % [k, result, code, body.size()])
	_pump()


func _drop_http() -> void:
	if _http != null and is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
	_http = null


func _user_path(id: String) -> String:
	return USER_DIR + id + ".mp3"


## 把相对路径拼成绝对 URL（Godot 的 HTTPRequest 不接受相对路径）
func _abs_url(id: String) -> String:
	var rel := URL_DIR + id + ".mp3"
	if not OS.has_feature("web"):
		return rel
	var safe := rel.replace("\\", "").replace("\"", "").replace("'", "")
	var u: Variant = JavaScriptBridge.eval(
		"new URL(\"%s\", document.baseURI).href" % safe, true)
	if u == null:
		return rel
	return str(u)


## 从剧本里按出现顺序抽出所有节点 id（vo 以节点 id 命名：c1_01.mp3）
func _story_voice_ids() -> Dictionary:
	var ids := {}
	var path := "res://data/story.json"
	if not FileAccess.file_exists(path):
		return ids
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ids
	var txt := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if data != null:
		_collect_ids(data, ids)
	return ids


func _collect_ids(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		var d := node as Dictionary
		var idv: Variant = d.get("id", "")
		if idv is String and str(idv) != "" and not out.has(str(idv)):
			out[str(idv)] = true
		for k: Variant in d.keys():
			_collect_ids(d[k], out)
	elif node is Array:
		for v: Variant in (node as Array):
			_collect_ids(v, out)
