extends Node
## 驱动节点（挂在 /root 下，避免场景切换把驱动自己释放掉）

const SCREENS := [
	"res://scenes/loading_screen.tscn",
	"res://scenes/main_menu.tscn",
	"res://scenes/chapter_select.tscn",
	"res://scenes/story_screen.tscn",
	"res://scenes/codex_screen.tscn",
	"res://scenes/settings_screen.tscn",
	"res://scenes/ending_screen.tscn",
]

var _fail: int = 0
var _pass: int = 0
var _routes: Array = []
var _route_errors: Array = []
var _endings: Dictionary = {}
var _locked_seen: Dictionary = {}


func ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  ", label)


func _ready() -> void:
	var win := get_window()
	win.size = Vector2i(1152, 648)
	for i: int in range(3):
		await get_tree().process_frame
	print("VIEWPORT=%.0fx%.0f" % [
		get_viewport().get_visible_rect().size.x,
		get_viewport().get_visible_rect().size.y])

	print("=== 1. 剧情数据 ===")
	_test_story_data()
	print("=== 2. 全分支路线探索 ===")
	_explore([], 0)
	_report_routes()
	print("=== 3. 界面实例化 ===")
	await _test_screens()
	print("=== 4. 剧情页推进 ===")
	await _test_story_flow()
	print("=== 5. 布局审计 ===")
	await _test_layout()

	print("TOTAL_PASS=%d TOTAL_FAIL=%d" % [_pass, _fail])
	get_tree().quit(_fail)


# ===========================================================================
# 1. 剧情数据
# ===========================================================================
func _test_story_data() -> void:
	var sd := get_node_or_null("/root/StoryData")
	ok(sd != null, "StoryData 单例存在")
	if sd == null:
		return
	ok(bool(sd.ok), "剧情 JSON 载入无错误")
	ok(Array(sd.errors).is_empty(), "剧情校验 errors 为空，实际 %d" % Array(sd.errors).size())
	ok(sd.nodes.size() >= 70, "节点数量 %d >= 70" % sd.nodes.size())
	ok(sd.chapter_order.size() == 5, "章节数 %d == 5" % sd.chapter_order.size())

	# 每个章节都有起点
	for ch: Dictionary in GameDefs.CHAPTERS:
		var cid := String(ch["id"])
		ok(String(sd.chapter_start(cid)) != "", "章节 %s 有起点节点" % cid)

	# 五章元数据齐全
	for ch2: Dictionary in GameDefs.CHAPTERS:
		for key: String in ["title", "location", "weather", "summary", "bg"]:
			ok(String(ch2.get(key, "")) != "", "章节 %s 字段 %s 非空" % [String(ch2["id"]), key])

	# 结局元数据齐全
	for eid: String in GameDefs.ENDINGS.keys():
		var ed: Dictionary = GameDefs.ENDINGS[eid]
		for key2: String in ["title", "tag", "tone", "bg", "summary"]:
			ok(String(ed.get(key2, "")) != "", "结局 %s 字段 %s 非空" % [eid, key2])

	# 图鉴数据齐全
	for sec: String in ["characters", "evidence", "tech", "facts"]:
		ok(sd.codex_section(sec).size() > 0, "图鉴 %s 非空" % sec)


# ===========================================================================
# 2. 全分支探索（数据层）
# ===========================================================================
func _walk(script: Array) -> Dictionary:
	var sd := get_node_or_null("/root/StoryData")
	var gs := get_node_or_null("/root/GameState")
	gs.new_run()
	gs.unlocked_chapters.assign(["ch1", "ch2", "ch3", "ch4", "ch5"])

	var node := String(sd.chapter_start("ch1"))
	var ci := 0
	var steps := 0
	while steps < 500:
		steps += 1
		var nd: Dictionary = sd.get_node_data(node)
		if nd.is_empty():
			return { "error": "节点缺失 %s" % node }
		var ntype := String(nd.get("type", ""))
		if ntype == "chapter":
			gs.current_chapter = String(nd.get("chapter", gs.current_chapter))
		if gs.first_visit(node) and nd.get("effects") is Dictionary:
			gs.apply_effects(Dictionary(nd["effects"]))
		if String(gs.death_ending()) != "" and ntype != "ending":
			return { "ending": "ending_doom", "auto": "population" }

		match ntype:
			"narration", "dialogue":
				var nxt := String(nd.get("next", ""))
				if nd.get("branch") is Array and not Array(nd["branch"]).is_empty():
					nxt = String(gs.resolve_branch(Array(nd["branch"]), nxt))
				node = nxt
			"popup", "chapter":
				node = String(nd.get("next", ""))
			"resolve":
				node = String(gs.resolve_branch(
					nd.get("branches", []) if nd.get("branches") is Array else [],
					String(nd.get("next", ""))))
			"ending":
				return { "ending": String(nd.get("ending", "")) }
			"choice":
				var opts: Array = nd.get("options", []) if nd.get("options") is Array else []
				var unlocked: Array = []
				for o: Variant in opts:
					var locked := false
					if o is Dictionary and Dictionary(o).has("require"):
						locked = not gs.check_all(Dictionary(o)["require"])
					unlocked.append(not locked)
				if ci >= script.size():
					return { "pending": { "kind": "choice", "node": node, "unlocked": unlocked } }
				var pick := int(script[ci])
				ci += 1
				if pick < 0 or pick >= opts.size():
					return { "error": "选项下标越界 %d @ %s" % [pick, node] }
				if not unlocked[pick]:
					return { "error": "脚本选了锁定项 %d @ %s" % [pick, node] }
				var opt: Dictionary = opts[pick]
				if opt.get("effects") is Dictionary:
					gs.apply_effects(Dictionary(opt["effects"]))
				if opt.get("flags") is Dictionary:
					for k: String in Dictionary(opt["flags"]).keys():
						gs.flags[k] = Dictionary(opt["flags"])[k]
				var n2 := String(opt.get("next", ""))
				if opt.get("branch") is Array and not Array(opt["branch"]).is_empty():
					n2 = String(gs.resolve_branch(Array(opt["branch"]), n2))
				node = n2
			"qte":
				var q: Dictionary = nd.get("qte", {}) if nd.get("qte") is Dictionary else {}
				if ci >= script.size():
					return { "pending": { "kind": "qte", "node": node } }
				var succ := int(script[ci]) == 0
				ci += 1
				var br: Dictionary = {}
				if q.get("success") is Dictionary and succ:
					br = Dictionary(q["success"])
				elif q.get("fail") is Dictionary and not succ:
					br = Dictionary(q["fail"])
				if br.get("effects") is Dictionary:
					gs.apply_effects(Dictionary(br["effects"]))
				node = String(q.get("success_next" if succ else "fail_next", ""))
			_:
				node = String(nd.get("next", ""))
		if node == "":
			return { "error": "在 %s 处断了（next 为空）" % nd.get("id", "?") }
	return { "error": "超过 500 步（疑似死循环），脚本 %s" % str(script) }


func _explore(script: Array, depth: int) -> void:
	if depth > 24:
		_route_errors.append("路线过深：%s" % str(script))
		return
	var res := _walk(script)
	if res.has("error"):
		_route_errors.append("%s  ← 脚本 %s" % [String(res["error"]), str(script)])
		return
	if res.has("ending"):
		var eid := String(res["ending"])
		_routes.append({ "script": script.duplicate(), "ending": eid })
		_endings[eid] = int(_endings.get(eid, 0)) + 1
		return
	var pend: Dictionary = res.get("pending", {})
	if String(pend.get("kind", "")) == "choice":
		var unlocked: Array = pend.get("unlocked", [])
		var any := false
		for i: int in range(unlocked.size()):
			if bool(unlocked[i]):
				any = true
				_explore(script + [i], depth + 1)
			else:
				var key := "%s#%d" % [String(pend["node"]), i]
				_locked_seen[key] = true
		if not any:
			_route_errors.append("节点 %s 所有选项都被锁死（玩家会卡住）← 脚本 %s"
				% [String(pend["node"]), str(script)])
		return
	if String(pend.get("kind", "")) == "qte":
		_explore(script + [0], depth + 1)
		_explore(script + [1], depth + 1)
		return
	_route_errors.append("未知的待决类型：%s ← 脚本 %s" % [str(pend), str(script)])


func _report_routes() -> void:
	ok(_route_errors.is_empty(), "无路线错误")
	for e: String in _route_errors:
		print("  ROUTE_ERR ", e)
	ok(_routes.size() >= 20, "探索到 %d 条完整路线（>=20）" % _routes.size())
	print("  路线数=%d　结局分布=%s　锁定项出现=%d 处"
		% [_routes.size(), str(_endings), _locked_seen.size()])
	# 每个登记在案的结局都应至少可达一次
	for eid: String in GameDefs.ENDINGS.keys():
		var cnt := int(_endings.get(eid, 0))
		ok(cnt > 0, "结局 %s 至少可达一次（实际 %d 条路线）" % [eid, cnt])
	# 每一条路线都必须有结局
	for r: Variant in _routes:
		var d: Dictionary = r
		ok(String(d.get("ending", "")) != "", "路线 %s 走到结局" % str(d.get("script", [])))
		ok(not GameDefs.ending_by_id(String(d["ending"])).is_empty(),
			"结局 id %s 已登记" % String(d["ending"]))
	# 锁定项不应出现在「唯一选项」的位置
	ok(_locked_seen.size() > 0, "至少有一条锁定选项被正确识别（说明 require 生效）")


# ===========================================================================
# 3. 界面实例化
# ===========================================================================
func _test_screens() -> void:
	var sd := get_node_or_null("/root/StoryData")
	var gs := get_node_or_null("/root/GameState")
	gs.new_run()

	for path: String in SCREENS:
		ok(ResourceLoader.exists(path), "场景存在 %s" % path)
		var ps: PackedScene = load(path)
		ok(ps != null and ps.can_instantiate(), "可实例化 %s" % path)
		if ps == null:
			continue
		var inst: Node = ps.instantiate()
		ok(inst is Control, "%s 根节点是 Control" % path)
		# 剧情页需要参数
		var nav := get_node_or_null("/root/Navigator")
		if nav != null:
			nav.params = { "chapter": "ch1", "node": String(sd.chapter_start("ch1")) }
		get_tree().root.add_child(inst)
		for i: int in range(4):
			await get_tree().process_frame
		ok(inst.get_child_count() > 0, "%s 已构建子节点（%d 个）" % [path, inst.get_child_count()])
		inst.queue_free()
		for i: int in range(2):
			await get_tree().process_frame
	ok(true, "全部界面实例化完成")


# ===========================================================================
# 4. 剧情页真实推进
# ===========================================================================
func _test_story_flow() -> void:
	var sd := get_node_or_null("/root/StoryData")
	var gs := get_node_or_null("/root/GameState")
	var nav := get_node_or_null("/root/Navigator")
	gs.new_run()
	gs.text_speed = 5000.0          # 打字机瞬间完成，方便断言
	nav.params = { "chapter": "ch1", "node": String(sd.chapter_start("ch1")) }

	var ps: PackedScene = load("res://scenes/story_screen.tscn")
	# 不标注类型：下面要自由访问剧情页的内部成员（fast_mode / _advance / _popup）
	var screen = ps.instantiate()
	screen.fast_mode = true          # 跳过章节转场卡与结算动画
	get_tree().root.add_child(screen)
	for i: int in range(4):
		await get_tree().process_frame

	ok(String(gs.current_node) != "", "剧情页已定位到节点：%s" % String(gs.current_node))

	var layer = _choice_layer(screen)
	ok(layer != null, "选项层可定位（ChoiceLayer）")
	var popup = screen.get_node_or_null("PopupLayer")
	ok(popup != null, "弹窗层可定位（PopupLayer）")

	# 一路推进，直到出现选项；途中遇到弹窗就模拟玩家点「继续」
	var seen_nodes: Array[String] = []
	var guard := 0
	while guard < 80 and not _choice_visible(screen):
		guard += 1
		seen_nodes.append(String(gs.current_node))
		if popup != null and popup.is_open():
			popup._close()
		else:
			screen._advance()
		for i: int in range(2):
			await get_tree().process_frame

	ok(_choice_visible(screen), "推进到第一章选项层可见（走了 %d 步，经过 %s）"
		% [guard, str(seen_nodes.slice(0, 8))])
	var cards := _choice_cards(screen)
	ok(cards.size() == 2, "选项卡片数量 %d == 2" % cards.size())

	# 点击第一个选项 → 应结算并进入新节点
	var before := String(gs.current_node)
	var stats_before: Dictionary = gs.stats.duplicate()
	var ev_before: int = int(gs.evidence.size())
	var tech_before: int = int(gs.techs.size())
	if cards.size() > 0:
		var c0: Node = cards[0]
		ok(c0.get_signal_connection_list("pressed").size() >= 1, "选项卡片已连接 pressed")
		c0.pressed.emit()
		for i: int in range(40):
			await get_tree().process_frame
			if String(gs.current_node) != before:
				break
	ok(String(gs.current_node) != before, "点击选项后推进到新节点（%s → %s）"
		% [before, String(gs.current_node)])
	ok(gs.choice_log.size() >= 1, "选择已记入 choice_log")
	ok(_stats_changed(stats_before, gs.stats) or int(gs.evidence.size()) > ev_before
			or int(gs.techs.size()) > tech_before or not gs.flags.is_empty(),
		"选项效果已结算（数值/证据/科技/旗标至少一项变化）")

	screen.queue_free()
	for i: int in range(2):
		await get_tree().process_frame


func _stats_changed(before: Dictionary, after: Dictionary) -> bool:
	for k: String in after.keys():
		if absf(float(after[k]) - float(before.get(k, 0.0))) > 0.001:
			return true
	return false


## 剧情页的选项层（StoryScreen 里命名为 ChoiceLayer 的 Control）
func _choice_layer(screen: Node) -> Node:
	return screen.get_node_or_null("ChoiceLayer")


func _choice_visible(screen: Node) -> bool:
	var l := _choice_layer(screen)
	return l != null and (l as Control).visible


func _choice_cards(screen: Node) -> Array:
	var out: Array = []
	var l := _choice_layer(screen)
	if l == null:
		return out
	for n: Node in _all_descendants(l):
		if n is Button and not (n as Button).disabled:
			out.append(n)
	return out


func _all_descendants(n: Node) -> Array:
	var out: Array = []
	for c: Node in n.get_children():
		out.append(c)
		out.append_array(_all_descendants(c))
	return out


# ===========================================================================
# 5. 布局审计
# ===========================================================================
func _visual_rect(c: Control) -> Rect2:
	var xf := c.get_global_transform_with_canvas()
	var pts: Array = [
		xf * Vector2.ZERO,
		xf * Vector2(c.size.x, 0),
		xf * Vector2(0, c.size.y),
		xf * c.size,
	]
	var r := Rect2(pts[0], Vector2.ZERO)
	for p: Vector2 in pts:
		r = r.expand(p)
	return r


func _in_scroll(node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _test_layout() -> void:
	var sd := get_node_or_null("/root/StoryData")
	var gs := get_node_or_null("/root/GameState")
	var nav := get_node_or_null("/root/Navigator")
	gs.new_run()
	nav.params = { "chapter": "ch3", "node": String(sd.chapter_start("ch3")) }

	var screen_rect := get_viewport().get_visible_rect()
	var checked := 0
	var bad := 0
	for path: String in SCREENS:
		var ps: PackedScene = load(path)
		var inst: Control = ps.instantiate()
		get_tree().root.add_child(inst)
		for i: int in range(5):
			await get_tree().process_frame
		for n: Node in _all_descendants(inst):
			if not (n is Control):
				continue
			var c := n as Control
			if not c.visible or c.size.x < 1.0 or c.size.y < 1.0:
				continue
			if _in_scroll(c):
				continue
			# 纯定位容器（size 为 0 的父容器）跳过
			if c is Container and c.custom_minimum_size == Vector2.ZERO and c.size == Vector2.ZERO:
				continue
			checked += 1
			var r := _visual_rect(c)
			if not screen_rect.grow(6.0).encloses(r):
				bad += 1
				if bad <= 12:
					print("  OVERFLOW %s :: %s rect=%s" % [path, str(c.get_path()), str(r)])
		inst.queue_free()
		for i: int in range(2):
			await get_tree().process_frame
	print("  布局检查控件 %d 个，越界 %d 个" % [checked, bad])
	ok(bad == 0, "所有可见控件都在屏幕内（越界 %d）" % bad)
