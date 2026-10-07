extends Node
## StoryData —— 剧情数据的加载、索引与校验（autoload 单例）。
##
## 剧情全部写在 res://data/story.json 里，本脚本只做三件事：
##   1. 把 JSON 读进来并按 id 建立索引；
##   2. 提供「下一节点」查询等只读访问；
##   3. 自检剧情图（悬空跳转、缺字段、无法抵达的节点）。
## 这样改剧情只需要动 JSON，不用碰任何逻辑代码。

const STORY_PATH := "res://data/story.json"

var ok: bool = false
var meta: Dictionary = {}
var chapters: Array = []
var nodes: Dictionary = {}                  ## node_id -> node Dictionary（已注入 chapter 字段）
var chapter_order: Dictionary = {}          ## chapter_id -> Array[String] 该章节节点顺序
var codex: Dictionary = {}
var errors: Array[String] = []
var warnings: Array[String] = []


func _ready() -> void:
	# 延后一帧再自检，保证 GameState 等 autoload 已就位（autoload 顺序无关）
	reload.call_deferred(true)


func reload(verbose: bool = false) -> bool:
	ok = false
	errors.clear()
	warnings.clear()
	nodes.clear()
	chapter_order.clear()
	chapters.clear()
	meta.clear()
	codex.clear()

	if not FileAccess.file_exists(STORY_PATH):
		errors.append("找不到剧情文件：%s" % STORY_PATH)
		_report(verbose)
		return false

	var f := FileAccess.open(STORY_PATH, FileAccess.READ)
	if f == null:
		errors.append("无法读取剧情文件：%s" % STORY_PATH)
		_report(verbose)
		return false
	var raw := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		errors.append("剧情 JSON 解析失败（请检查逗号/引号是否配对）")
		_report(verbose)
		return false

	var root: Dictionary = parsed
	meta = root.get("meta", {}) if root.get("meta", {}) is Dictionary else {}
	chapters = root.get("chapters", []) if root.get("chapters", []) is Array else []
	codex = root.get("codex", {}) if root.get("codex", {}) is Dictionary else {}

	for ci: int in range(chapters.size()):
		var ch: Variant = chapters[ci]
		if not (ch is Dictionary):
			errors.append("chapters[%d] 不是对象" % ci)
			continue
		var cd: Dictionary = ch
		var cid := String(cd.get("id", ""))
		if cid == "":
			errors.append("chapters[%d] 缺少 id" % ci)
			continue
		var list: Array[String] = []
		var raw_nodes: Variant = cd.get("nodes", [])
		if not (raw_nodes is Array):
			errors.append("%s.nodes 不是数组" % cid)
			continue
		for ni: int in range(Array(raw_nodes).size()):
			var nv: Variant = Array(raw_nodes)[ni]
			if not (nv is Dictionary):
				errors.append("%s.nodes[%d] 不是对象" % [cid, ni])
				continue
			var nd: Dictionary = nv
			var nid := String(nd.get("id", ""))
			if nid == "":
				errors.append("%s.nodes[%d] 缺少 id" % [cid, ni])
				continue
			if nodes.has(nid):
				errors.append("节点 id 重复：%s" % nid)
				continue
			nd["chapter"] = cid
			nd["chapter_index"] = int(cd.get("index", ci + 1))
			nd["chapter_title"] = String(cd.get("title", ""))
			nodes[nid] = nd
			list.append(nid)
		chapter_order[cid] = list

	_validate()

	ok = errors.is_empty()
	_report(verbose)
	return ok


## 剧情图自检
func _validate() -> void:
	# 章节引用的合法性
	for ci: int in range(chapters.size()):
		var cd: Dictionary = chapters[ci]
		var cid := String(cd.get("id", ""))
		if GameDefs.chapter_by_id(cid).is_empty():
			warnings.append("章节 %s 未在 GameDefs.CHAPTERS 中登记（将没有章节卡片配色）" % cid)

	for nid: String in nodes.keys():
		var nd: Dictionary = nodes[nid]
		var ntype := String(nd.get("type", ""))
		if nd.has("next"):
			_check_link(nid, String(nd["next"]))
		match ntype:
			"choice":
				_validate_choice(nid, nd)
			"qte":
				_validate_qte(nid, nd)
			"ending":
				var eid := String(nd.get("ending", ""))
				if eid != "" and GameDefs.ending_by_id(eid).is_empty():
					errors.append("%s: 结局 id「%s」未在 GameDefs.ENDINGS 中登记" % [nid, eid])
			"chapter":
				var target := String(nd.get("chapter", ""))
				if not chapter_order.has(target):
					errors.append("%s: 跳转到不存在的章节「%s」" % [nid, target])
			_:
				var t := String(nd.get("type", ""))
				if t == "popup" or t == "resolve" or t == "chapter" or t == "ending":
					pass
				elif String(nd.get("text", "")) == "":
					warnings.append("%s: 文本为空" % nid)

	# 孤立节点（没有任何节点指过来，也不是各章首节点）
	var referenced := {}
	for cid: String in chapter_order.keys():
		var list: Array[String] = chapter_order[cid]
		if list.size() > 0:
			referenced[list[0]] = true   # 章节首节点允许不被引用
	for nid2: String in nodes.keys():
		var nd2: Dictionary = nodes[nid2]
		if nd2.has("next"):
			referenced[String(nd2["next"])] = true
		if nd2.has("branch") and nd2["branch"] is Array:
			for b: Variant in nd2["branch"]:
				if b is Dictionary and Dictionary(b).has("next"):
					referenced[String(Dictionary(b)["next"])] = true
		if nd2.has("options") and nd2["options"] is Array:
			for o: Variant in nd2["options"]:
				if o is Dictionary and Dictionary(o).has("next"):
					referenced[String(Dictionary(o)["next"])] = true
				if o is Dictionary and Dictionary(o).has("branch") and Dictionary(o)["branch"] is Array:
					for b2: Variant in Dictionary(o)["branch"]:
						if b2 is Dictionary and Dictionary(b2).has("next"):
							referenced[String(Dictionary(b2)["next"])] = true
		if nd2.has("branches") and nd2["branches"] is Array:
			for b3: Variant in nd2["branches"]:
				if b3 is Dictionary and Dictionary(b3).has("next"):
					referenced[String(Dictionary(b3)["next"])] = true
		if nd2.has("qte") and nd2["qte"] is Dictionary:
			var q: Dictionary = nd2["qte"]
			for k: String in ["success_next", "fail_next"]:
				if q.has(k):
					referenced[String(q[k])] = true
	for nid3: String in nodes.keys():
		if not referenced.has(nid3) and not _is_terminal(nid3):
			warnings.append("%s: 没有任何节点跳转到它（孤立节点）" % nid3)


func _is_terminal(nid: String) -> bool:
	var nd: Dictionary = nodes[nid]
	var t := String(nd.get("type", ""))
	return t == "ending"


func _check_link(from: String, to: String) -> void:
	if to == "":
		return
	if not nodes.has(to):
		errors.append("%s: 跳转到不存在的节点「%s」" % [from, to])


func _validate_choice(nid: String, nd: Dictionary) -> void:
	var opts: Variant = nd.get("options", null)
	if not (opts is Array) or Array(opts).is_empty():
		errors.append("%s: choice 节点缺少 options" % nid)
		return
	for oi: int in range(Array(opts).size()):
		var ov: Variant = Array(opts)[oi]
		if not (ov is Dictionary):
			errors.append("%s: options[%d] 不是对象" % [nid, oi])
			continue
		var o: Dictionary = ov
		if String(o.get("text", "")) == "":
			errors.append("%s: options[%d] 缺少 text" % [nid, oi])
		if o.has("next"):
			_check_link(nid, String(o["next"]))
		if o.has("branch") and o["branch"] is Array:
			for bi: int in range(Array(o["branch"]).size()):
				var bv: Variant = Array(o["branch"])[bi]
				if bv is Dictionary:
					if Dictionary(bv).has("next"):
						_check_link(nid, String(Dictionary(bv)["next"]))
				else:
					errors.append("%s: options[%d].branch[%d] 不是对象" % [nid, oi, bi])
		if not o.has("next") and not o.has("branch"):
			errors.append("%s: options[%d] 既没有 next 也没有 branch（死路）" % [nid, oi])


func _validate_qte(nid: String, nd: Dictionary) -> void:
	var qv: Variant = nd.get("qte", null)
	if not (qv is Dictionary):
		errors.append("%s: qte 节点缺少 qte 配置" % nid)
		return
	var q: Dictionary = qv
	for k: String in ["success_next", "fail_next"]:
		if not q.has(k):
			errors.append("%s: qte 缺少 %s" % [nid, k])
		else:
			_check_link(nid, String(q[k]))


func _report(verbose: bool) -> void:
	for e: String in errors:
		push_error("[剧情校验] %s" % e)
	for w: String in warnings:
		push_warning("[剧情校验] %s" % w)
	if verbose or not errors.is_empty():
		print("[StoryData] 节点 %d 个 / 章节 %d 个 / 错误 %d / 警告 %d"
			% [nodes.size(), chapter_order.size(), errors.size(), warnings.size()])


# ===========================================================================
# 只读访问
# ===========================================================================
func get_node_data(nid: String) -> Dictionary:
	if not nodes.has(nid):
		return {}
	return nodes[nid]


func has_node_data(nid: String) -> bool:
	return nodes.has(nid)


func chapter_start(cid: String) -> String:
	var list: Array = chapter_order.get(cid, [])
	if list.is_empty():
		return ""
	return String(list[0])


func next_chapter_id(cid: String) -> String:
	for i: int in range(chapters.size()):
		var cd: Dictionary = chapters[i]
		if String(cd.get("id", "")) == cid:
			if i + 1 < chapters.size():
				return String(Dictionary(chapters[i + 1]).get("id", ""))
			return ""
	return ""


## 章节在 JSON 里声明的元数据（标题、副标题、地点、天气、摘要）的合并视图：
## GameDefs.CHAPTERS 提供稳定的展示信息，JSON 里可以覆盖 summary 等字段。
func chapter_meta(cid: String) -> Dictionary:
	var base := GameDefs.chapter_by_id(cid)
	for cd_: Variant in chapters:
		if cd_ is Dictionary and String(Dictionary(cd_).get("id", "")) == cid:
			for k: String in Dictionary(cd_).keys():
				if k == "nodes":
					continue
				base[k] = Dictionary(cd_)[k]
			break
	return base


func codex_section(name: String) -> Array:
	var v: Variant = codex.get(name, [])
	return v if v is Array else []
