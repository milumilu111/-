extends RefCounted
class_name Texts

# 文案表：真正生效的是同目录的 texts.txt（纯文本，一行一条：键 = 文案）。
# 这里只是「默认值」——texts.txt 里没写的键，就用这里的。
# 想改屏幕上的字，改 texts.txt 就行，不用碰代码。

static var T := {
	# ── 探查结果 ──
	"res_empty": "这儿什么都没有。真乖 —— 继续猜。",
	"res_trail": "它踩过这里。印子还热着，它已经走了。",
	"res_hit": "找到了。可惜，它先看见了你。",
	"hit_wounded": "擦到了。它流了点东西，然后跑得更快了。",
	"probe_wait": "递上去了。等那边的回音。",
	"wall_crash": "墙塌了。它没停 —— 那一声你听见了吧。",

	# ── 布防 / 开局 ──
	"setup_ask": "先布防。它不知道你埋在哪，你也不知道它从哪条路来。",
	"setup_done_sp": "布防完了。它先走 4 步 —— 不计回合，你也看不见。",
	"setup_done_wait": "布防完了。等他走开局的 4 步 —— 不计回合，你看不见。",
	"setup_done_host": "布防完了。轮到他先走 4 步 —— 不计回合，你看不见。",
	"setup_done_monster": "他布完防了。开局这 4 步归你自己 —— 走完按空格。",
	"opening_hint": "它先走了 4 步 —— 不计回合，你也看不见。",

	# ── 地雷 ──
	"mine_hit": "踩响了。它没死，只是更恨你了。",
	"mine_miss": "响了。那儿没人 —— 你浪费了一颗。",

	# ── 投掷 ──
	"throw_empty": "这颗已经用掉了。别抠空盒子。",
	"throw_arm": "%s在手上。点一格，扔出去（Esc 放下）。",
	"throw_cant": "那儿扔不了。",
	"throw_done": "扔出去了。",
	"flash_hit": "晃到了。九格里有东西，它现在睁不开眼。",
	"flash_miss": "亮了。九格干净得像新的一样。",
	"nade_placed": "放下了。下一回合，它替你去看看。",
	"fire_placed": "烧起来了。这片地会一直烫着。",
	"put_down": "放下了。",

	# ── 回合流转 ──
	"auto_end": "步数走完了 —— 回合自己滑出去了。",
	"rest_confirm": "这一回合你动不了。按空格，认了它。",

	# ── 座位 / 联机 ──
	"seat_human_here": "你现在坐在它对面。他查哪一格，你都看得见。",
	"seat_wait_deploy": "他正在布防。布完你走开局的 4 步。",
	"seat_opening": "你在出生点。开局这 4 步归你自己 — 走完按空格，才轮到他。",
	"guest_wait": "等房主开局……",
	"turn_you": "轮到你了。手别抖。",
	"turn_you_monster": "轮到你了。走给我看。",
	"turn_other": "轮到它了。",
	"turn_multi": "轮到你了 —— 这回合能查 %d 格。",
	"actions_more": "还能再查 %d 次。",
	"peer_left": "对面断开了。",
	"peer_left_end": "他走了。",
	"press_r": "按 R 回标题",

	# ── 结算：人类赢 ──
	"win_probe_title": "查中了。",
	"win_probe_sub": "它一直在等你看错 —— 这一次它等错了。",
	"win_mine_title": "踩响了。",
	"win_mine_sub": "它以为那是你查格子的声音。",
	"win_fire_title": "烧掉了。",
	"win_fire_sub": "它一直没从火光里走出来。",
	"win_nade_title": "炸中了。",
	"win_nade_sub": "你只是把九格都试了一遍。",
	"win_timeout_title": "天亮了。",
	"win_timeout_sub": "二十回合，它没能进门。",

	# ── 结算：人类输 ──
	"lose_arrive_title": "它到了。",
	"lose_arrive_sub": "你一直看着的那个方向，其实不是它来的方向。",

	# ── 结算：异形席 ──
	"m_arrive_title": "你到了。",
	"m_arrive_sub": "他一直在查别的地方。",
	"m_timeout_title": "天亮了。",
	"m_timeout_sub": "二十回合，他没能找到你。",
	"m_probe_title": "他找到你了。",
	"m_probe_sub": "你会出现在他下一眼的余光里。",
	"m_mine_title": "踩雷了。",
	"m_mine_sub": "他根本没看见你 —— 只是把雷放在了你必经的那条路上。",
	"m_fire_title": "你被烧掉了。",
	"m_fire_sub": "火一直在那儿，你没绕开。",
	"m_nade_title": "你被炸中了。",
	"m_nade_sub": "那颗雷落地的时候，你没走开。",
	"m_other_title": "他找到了你。",
	"m_other_sub": "灯亮在他那边。",
}

const TEXT_PATH := "res://texts.txt"

static var _loaded := false
static var _overrides := {}


static func s(key: String) -> String:
	if not _loaded:
		_load()
	if _overrides.has(key):
		return String(_overrides[key])
	return String(T.get(key, key))


static func _load() -> void:
	_loaded = true
	_overrides = {}
	if not FileAccess.file_exists(TEXT_PATH):
		return
	var f := FileAccess.open(TEXT_PATH, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var idx := line.find("=")
		if idx <= 0:
			continue
		var k := line.substr(0, idx).strip_edges()
		var v := line.substr(idx + 1).strip_edges()
		if k != "":
			_overrides[k] = v
	f.close()


static func reload() -> void:
	_loaded = false
	_load()
