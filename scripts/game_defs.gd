class_name GameDefs
extends RefCounted
## 全局静态定义：数值体系、章节/结局元数据、配色方案。
##
## 所有界面与逻辑都从这里取「唯一事实来源」，避免数值上限、颜色、
## 章节标题在多处各写一份而互相漂移。

# ---------------------------------------------------------------------------
# 配色：冰川夜蓝为主，冰青作强调，暖橙代表对抗，翠绿代表合作
# ---------------------------------------------------------------------------
const C_INK := Color("#050d17")
const C_DEEP := Color("#0a1b2b")
const C_PANEL := Color("#0e2438")
const C_PANEL_HI := Color("#15354f")
const C_LINE := Color("#24506e")
const C_ICE := Color("#7fe3ff")
const C_ICE_DIM := Color("#3f9dc4")
const C_TEXT := Color("#eaf7ff")
const C_MUTED := Color("#93b4cc")
const C_WARN := Color("#ff8a5c")
const C_RADICAL := Color("#ff7a59")
const C_COOP := Color("#6ee7b7")
const C_GOLD := Color("#ffd479")
const C_DANGER := Color("#ff5f6d")

## 状态条数值上限
const STAT_MAX := 100

## 六项核心数值。顺序即 HUD 中的显示顺序。
static var STATS := {
	"radical": {
		"label": "激进值",
		"color": C_RADICAL,
		"start": 20,
		"hint": "以直接对抗逼迫人类让步，越高越容易解锁强硬路线。",
	},
	"coop": {
		"label": "合作值",
		"color": C_COOP,
		"start": 20,
		"hint": "与人类科学界结盟的深度，决定最终谈判桌上的筹码。",
	},
	"population": {
		"label": "族群数量",
		"color": C_ICE,
		"start": 100,
		"hint": "雁群还剩下多少只，归零意味着迁徙彻底失败。",
	},
	"trust": {
		"label": "内部信任",
		"color": C_GOLD,
		"start": 70,
		"hint": "雁群与动物议会对你决策的信任，过低会众叛亲离。",
	},
	"glacier": {
		"label": "冰川健康度",
		"color": Color("#8ad7ff"),
		"start": 35,
		"hint": "全球冰川的整体存活状态，也是这场迁徙唯一真正要守护的东西。",
	},
	"stamina": {
		"label": "体力",
		"color": Color("#c9a6ff"),
		"start": 100,
		"hint": "长途飞行的余力，体力见底时很多选项将无法选择。",
	},
}

## 五章元数据。accent 用于章节卡片与标签配色。
static var CHAPTERS := [
	{
		"id": "ch1",
		"index": 1,
		"title": "珠峰警报",
		"subtitle": "开场",
		"location": "珠峰北坡冰川",
		"weather": "晴，零下 26℃",
		"summary": "冰裂声撕裂寂静。四十年的退缩，在一条新裂缝里露出了獠牙。",
		"accent": C_ICE,
		"bg": "ch1",
		"video": "scene1",
	},
	{
		"id": "ch2",
		"index": 2,
		"title": "冰原议会",
		"subtitle": "抉择",
		"location": "经幡废墟",
		"weather": "夜，月光",
		"summary": "雪豹、牦牛与金雕围坐在残垣之间。抗议，还是求援？",
		"accent": C_GOLD,
		"bg": "ch2",
		"video": "scene5a",
	},
	{
		"id": "ch3",
		"index": 3,
		"title": "人类世界的抉择",
		"subtitle": "迷宫",
		"location": "迪拜 · 摩天楼群",
		"weather": "晴，49℃热浪",
		"summary": "玻璃幕墙反射着致命的白光，广告牌上写着「清洁能源，守护冰川」。",
		"accent": C_WARN,
		"bg": "ch3",
		"video": "scene7",
	},
	{
		"id": "ch4",
		"index": 4,
		"title": "转折点",
		"subtitle": "崩塌",
		"location": "阿尔卑斯山脉",
		"weather": "阴，融水轰鸣",
		"summary": "记忆中的冰原不见了。半座冰崖在眼前轰然坠入黑色的融水湖。",
		"accent": Color("#b7e3ff"),
		"bg": "ch4",
		"video": "scene10",
	},
	{
		"id": "ch5",
		"index": 5,
		"title": "最终决战",
		"subtitle": "72 小时",
		"location": "格陵兰冰盖",
		"weather": "暴风，倒计时",
		"summary": "格陵兰冰盖崩塌预警，72 小时。人类文明第一次需要一只鸟的建议。",
		"accent": C_DANGER,
		"bg": "ch5",
		"video": "scene9",
	},
]

## 结局元数据。tone 决定结局页的配色与音乐情绪。
static var ENDINGS := {
	"ending_new_glacier": {
		"title": "结局 · 新冰川",
		"tag": "最佳结局",
		"tone": "good",
		"accent": C_COOP,
		"bg": "ending_good",
		"video": "scene12b",
		"summary": "七十二小时后，格陵兰的裂缝停止了扩张。第二年春天，雪翼在一条新生的冰舌上，看着小雁第一次踩碎薄冰、扑棱着学会起飞。她想起赤瞳的那句「再这样下去，我们的后代连雪都看不到了」——现在，雪回来了。",
	},
	"ending_dawn": {
		"title": "结局 · 脆弱的黎明",
		"tag": "部分成功",
		"tone": "neutral",
		"accent": C_GOLD,
		"bg": "ending_good",
		"video": "scene12c",
		"summary": "紧急计划通过了，但代价比谁都预想的更重。冰川没有消失，也未曾恢复——它停在了一个脆弱的平衡上。雪翼明白，这不是胜利，只是把终局往后推了一代人。",
	},
	"ending_diaspora": {
		"title": "结局 · 离散",
		"tag": "迁徙继续",
		"tone": "neutral",
		"accent": C_ICE_DIM,
		"bg": "ending_good",
		"video": "scene11c",
		"summary": "雁群飞向了南方那座陌生的大陆。水是热的，藻类是毒的，袋鼠和野兔在枯河边争夺最后一洼水。雪翼活着，族群活着，只是它们再也回不去那个会下雪的故乡了。",
	},
	"ending_doom": {
		"title": "结局 · 长夜降临",
		"tag": "末日结局",
		"tone": "bad",
		"accent": C_DANGER,
		"bg": "ending_bad",
		"video": "scene14a",
		"summary": "格陵兰冰盖在第七十一小时四十分崩塌。镜头拉远：海水漫过自由女神像的肩，漫过迪拜的玻璃幕墙，漫过珠峰的北坡。雪翼在空中盘旋了很久，然后发现，已经没有可以落下的陆地了。",
	},
	"ending_greenhouse": {
		"title": "结局 · 钢铁温室",
		"tag": "失控结局",
		"tone": "bad",
		"accent": C_WARN,
		"bg": "ending_bad",
		"video": "scene14b",
		"summary": "大气冷凝器启动了。冰回来了——以一种谁也无法预料的方式。暴雪在三亚落下，赤道的海洋结起薄壳，地球被拽进了另一场失控的降温。人类和候鸟一起，学会了在钢铁温室里等待下一个春天。",
	},
}

## 每条数值变化的显示名，用于「本次结算」浮层
static func stat_label(key: String) -> String:
	var d: Dictionary = STATS.get(key, {})
	return String(d.get("label", key))


static func stat_color(key: String) -> Color:
	var d: Dictionary = STATS.get(key, {})
	var c: Color = d.get("color", C_ICE)
	return c


static func chapter_by_id(cid: String) -> Dictionary:
	for c: Dictionary in CHAPTERS:
		if String(c["id"]) == cid:
			return c
	return {}


static func chapter_index(cid: String) -> int:
	var c := chapter_by_id(cid)
	return int(c.get("index", 0)) if not c.is_empty() else 0


## 存档里只存 key，这里统一转成完整元数据
static func ending_by_id(eid: String) -> Dictionary:
	var d: Dictionary = ENDINGS.get(eid, {})
	return d
