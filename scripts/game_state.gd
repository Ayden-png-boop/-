extends Node
## GameState —— 一局「迁徙」的全部状态 + 玩家设置 + 存档读写（autoload 单例）。
##
## 剧情脚本只描述「发生了什么」，所有数值落地、条件判断、存读档都由这里负责，
## 这样剧情数据可以随时增删改而不必碰逻辑代码。

signal stats_changed()
signal inventory_changed()
signal settings_changed()
signal run_reset()

const SAVE_PATH := "user://glacier_save.json"
const SETTINGS_PATH := "user://glacier_settings.cfg"
const SAVE_VERSION := 1

# ---------------------------------------------------------------------------
# 一局迁徙的状态
# ---------------------------------------------------------------------------
var stats: Dictionary = {}
var flags: Dictionary = {}
var evidence: Array[String] = []
var techs: Array[String] = []
var visited: Array[String] = []
var choice_log: Array = []          ## [{node, index, text, chapter}]
var current_chapter: String = "ch1"
var current_node: String = ""
var run_started: bool = false
var finished_ending: String = ""

# ---------------------------------------------------------------------------
# 玩家设置
# ---------------------------------------------------------------------------
var text_speed: float = 55.0         ## 打字机速度：字/秒
var font_scale: float = 1.0
var bgm_volume: float = 0.55
var sfx_volume: float = 0.7
var voice_on: bool = true            ## 剧情配音开关
var voice_volume: float = 0.9
var typing_on: bool = true           ## 逐字显示时的键盘敲击音
var auto_advance: bool = false
var auto_delay: float = 2.2
var seen_prologue: bool = false
var unlocked_chapters: Array[String] = ["ch1"]


func _ready() -> void:
	_load_settings()
	_reset_run_internal()


# ===========================================================================
# 一局迁徙
# ===========================================================================
## 开新一局：六项数值回到起始值，清空旗标/证据/科技。
func new_run() -> void:
	_reset_run_internal()
	_save_progress()
	run_reset.emit()


func _reset_run_internal() -> void:
	stats.clear()
	for key: String in GameDefs.STATS.keys():
		var d: Dictionary = GameDefs.STATS[key]
		stats[key] = float(d.get("start", 0))
	flags.clear()
	evidence.clear()
	techs.clear()
	visited.clear()
	choice_log.clear()
	current_chapter = "ch1"
	current_node = ""
	finished_ending = ""
	run_started = true
	stats_changed.emit()
	inventory_changed.emit()


## 让角色从某一章直接开始（章节选择用）。会把该章视为「刚进入」，
## 同时保留合理的起始数值。
func begin_from_chapter(cid: String, start_node: String) -> void:
	_reset_run_internal()
	current_chapter = cid
	current_node = start_node


## 应用一段剧情效果。返回可直接显示给玩家的结算文案数组。
func apply_effects(eff: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	if eff.is_empty():
		return notes

	var changed := false
	var s: Dictionary = eff.get("stats", {})
	for key: String in s.keys():
		if not stats.has(key):
			continue
		var before := float(stats[key])
		var after := clampf(before + float(s[key]), 0.0, float(GameDefs.STAT_MAX))
		stats[key] = after
		if not is_equal_approx(before, after):
			changed = true
			notes.append("%s %s%d" % [
				GameDefs.stat_label(key),
				"+" if after > before else "",
				int(round(after - before)),
			])
	if changed:
		stats_changed.emit()

	var ev: Array = eff.get("evidence", [])
	for e: Variant in ev:
		if add_evidence(String(e)):
			notes.append("获得证据：%s" % String(e))

	var tk: Array = eff.get("tech", [])
	for t: Variant in tk:
		if unlock_tech(String(t)):
			notes.append("解锁科技：%s" % String(t))

	var fl: Dictionary = eff.get("flags", {})
	for key: String in fl.keys():
		flags[key] = fl[key]

	var custom := String(eff.get("note", ""))
	if custom != "":
		notes.append(custom)

	return notes


func add_evidence(id: String) -> bool:
	if id == "" or evidence.has(id):
		return false
	evidence.append(id)
	inventory_changed.emit()
	return true


func unlock_tech(id: String) -> bool:
	if id == "" or techs.has(id):
		return false
	techs.append(id)
	inventory_changed.emit()
	return true


func has_evidence(id: String) -> bool:
	return evidence.has(id)


func has_tech(id: String) -> bool:
	return techs.has(id)


func flag(name: String) -> bool:
	return bool(flags.get(name, false))


func stat(key: String) -> float:
	return float(stats.get(key, 0.0))


func mark_visited(node_id: String) -> void:
	if node_id != "" and not visited.has(node_id):
		visited.append(node_id)


## 首次抵达某节点时返回 true，并把该节点记为已访问。
## 剧情节点自带的 effects 只在首次抵达时结算，这样「中途去档案页再回来」
## 不会把同一段数值变化重复加一遍。
func first_visit(node_id: String) -> bool:
	if node_id == "":
		return false
	if visited.has(node_id):
		return false
	visited.append(node_id)
	return true


# ===========================================================================
# 条件判断
# ===========================================================================
## 判断一组条件是否全部满足。空条件视为满足。
func check_all(conds: Variant) -> bool:
	if conds == null:
		return true
	if conds is Array:
		for c: Variant in conds:
			if not check_one(c):
				return false
		return true
	if conds is Dictionary:
		return check_one(conds)
	return true


func check_one(cond: Variant) -> bool:
	if not (cond is Dictionary):
		return true
	var c: Dictionary = cond

	# 任意满足
	if c.has("any"):
		var arr: Array = c["any"]
		for sub: Variant in arr:
			if check_one(sub):
				return true
		return false
	# 全部不满足
	if c.has("none"):
		var arr2: Array = c["none"]
		for sub: Variant in arr2:
			if check_one(sub):
				return false
		return true
	# 全部满足
	if c.has("all"):
		var arr3: Array = c["all"]
		for sub: Variant in arr3:
			if not check_one(sub):
				return false
		return true

	# 单条原子条件
	if c.has("stat"):
		var key := String(c["stat"])
		var op := String(c.get("op", ">="))
		var target := float(c.get("value", 0))
		var v := stat(key)
		match op:
			">=": return v >= target
			">": return v > target
			"<=": return v <= target
			"<": return v < target
			"==": return is_equal_approx(v, target)
			"!=": return not is_equal_approx(v, target)
		return false
	if c.has("flag"):
		return flag(String(c["flag"]))
	if c.has("not_flag"):
		return not flag(String(c["not_flag"]))
	if c.has("evidence"):
		return has_evidence(String(c["evidence"]))
	if c.has("not_evidence"):
		return not has_evidence(String(c["not_evidence"]))
	if c.has("all_evidence"):
		for e: Variant in c["all_evidence"]:
			if not has_evidence(String(e)):
				return false
		return true
	if c.has("any_evidence"):
		for e: Variant in c["any_evidence"]:
			if has_evidence(String(e)):
				return true
		return false
	if c.has("tech"):
		return has_tech(String(c["tech"]))
	if c.has("not_tech"):
		return not has_tech(String(c["tech"]))
	return true


## 某个分支表里挑出第一个满足 when 的 next；都不满足则用 fallback。
func resolve_branch(branches: Array, fallback: String) -> String:
	for b: Variant in branches:
		if not (b is Dictionary):
			continue
		var d: Dictionary = b
		if check_all(d.get("when", null)):
			return String(d.get("next", fallback))
	return fallback


## 灭族检查：族群归零直接失败。
func death_ending() -> String:
	if stat("population") <= 0.0:
		return "ending_doom"
	return ""


# ===========================================================================
# 存档
# ===========================================================================
func save_progress() -> bool:
	_save_progress()
	return true


func _save_progress() -> void:
	var data := {
		"version": SAVE_VERSION,
		"chapter": current_chapter,
		"node": current_node,
		"stats": stats,
		"flags": flags,
		"evidence": evidence,
		"techs": techs,
		"visited": visited,
		"choice_log": choice_log,
		"unlocked_chapters": unlocked_chapters,
		"finished_ending": finished_ending,
		"run_started": run_started,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("GameState: 无法写入存档 %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 读取存档。返回是否成功。
func load_progress() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed
	if int(d.get("version", 0)) != SAVE_VERSION:
		return false

	# 数值键补齐，避免旧档缺键
	stats.clear()
	for key: String in GameDefs.STATS.keys():
		var start: float = float(Dictionary(GameDefs.STATS[key]).get("start", 0))
		stats[key] = float(Dictionary(d.get("stats", {})).get(key, start))

	flags = _as_dict(d.get("flags", {}))
	evidence = _as_str_array(d.get("evidence", []))
	techs = _as_str_array(d.get("techs", []))
	visited = _as_str_array(d.get("visited", []))
	choice_log = _as_array(d.get("choice_log", []))
	unlocked_chapters = _as_str_array(d.get("unlocked_chapters", ["ch1"]))
	if unlocked_chapters.is_empty():
		unlocked_chapters = ["ch1"]
	current_chapter = String(d.get("chapter", "ch1"))
	current_node = String(d.get("node", ""))
	finished_ending = String(d.get("finished_ending", ""))
	run_started = bool(d.get("run_started", true))
	stats_changed.emit()
	inventory_changed.emit()
	return true


func clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	unlocked_chapters = ["ch1"]


## 章节解锁（通关一章后调用）
func unlock_chapter(cid: String) -> void:
	if not unlocked_chapters.has(cid):
		unlocked_chapters.append(cid)
		_save_progress()


func is_chapter_unlocked(cid: String) -> bool:
	return unlocked_chapters.has(cid)


func _as_dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


func _as_array(v: Variant) -> Array:
	return v if v is Array else []


func _as_str_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for item: Variant in v:
			out.append(String(item))
	return out


# ===========================================================================
# 设置
# ===========================================================================
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	text_speed = float(cfg.get_value("text", "speed", text_speed))
	font_scale = float(cfg.get_value("text", "font_scale", font_scale))
	bgm_volume = float(cfg.get_value("audio", "bgm", bgm_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	voice_on = bool(cfg.get_value("audio", "voice_on", voice_on))
	voice_volume = float(cfg.get_value("audio", "voice", voice_volume))
	typing_on = bool(cfg.get_value("audio", "typing_on", typing_on))
	auto_advance = bool(cfg.get_value("text", "auto_advance", auto_advance))
	auto_delay = float(cfg.get_value("text", "auto_delay", auto_delay))
	seen_prologue = bool(cfg.get_value("progress", "seen_prologue", seen_prologue))
	var fullscreen := bool(cfg.get_value("display", "fullscreen", false))
	# 全屏由 DisplayMgr 在启动时读取，这里只保留值
	set_meta("fullscreen", fullscreen)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("text", "speed", text_speed)
	cfg.set_value("text", "font_scale", font_scale)
	cfg.set_value("text", "auto_advance", auto_advance)
	cfg.set_value("text", "auto_delay", auto_delay)
	cfg.set_value("audio", "bgm", bgm_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "voice", voice_volume)
	cfg.set_value("audio", "voice_on", voice_on)
	cfg.set_value("audio", "typing_on", typing_on)
	cfg.set_value("progress", "seen_prologue", seen_prologue)
	cfg.set_value("display", "fullscreen", bool(get_meta("fullscreen", false)))
	cfg.save(SETTINGS_PATH)
	settings_changed.emit()


func set_fullscreen_flag(on: bool) -> void:
	set_meta("fullscreen", on)
	save_settings()


func wants_fullscreen() -> bool:
	return bool(get_meta("fullscreen", false))
