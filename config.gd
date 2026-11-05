extends RefCounted
class_name GameConfig

# 一局游戏的「赛前约定」：谁坐哪边、双方暗选了什么技能。
# 菜单写这里，main.gd 读这里。静态变量在场景切换后依然有效。

enum Side { HUMAN = 0, MONSTER = 1 }
enum HumanSkill { BUILDER = 1, SAPPER = 2, THROWER = 3, SURVIVOR = 4 }
enum MonsterSkill { TOUGH = 1, BURST = 2, LEAP = 3, PREDATOR = 4 }

# 玩法模式
enum Mode { CLASSIC = 0, BO3 = 1, ESCAPE = 2, HUNT = 3 }

static var mode: int = Mode.CLASSIC

# —— 三局两胜（BO3）用的对局记录（只在联机时启用）——
static var match_round: int = 1        # 现在是第几局
static var wins_human: int = 0
static var wins_monster: int = 0
static var used_human: Array = []      # 人类这几局用过哪些职业
static var used_monster: Array = []    # 异形用过哪些职业
static var last_winner: int = -1        # -1 还没打 / 0 人类赢 / 1 异形赢

# —— 死里逃生用的状态 ——
static var lives_left: int = 3          # 异形还剩几条命
static var human_skills: Array = []     # 人类叠加的技能（含重复，重复＝强化）
static var monster_skills: Array = []

# —— 亡命追猎：两名人类各自的基地 ——
static var base_a: Vector2i = Vector2i(0, 0)
static var base_b: Vector2i = Vector2i(0, 0)
static var my_seat: int = 0             # 亡命追猎里我是 A 还是 B

static var player_side: int = Side.HUMAN
static var human_skill: int = HumanSkill.SAPPER
static var monster_skill: int = MonsterSkill.BURST

# 联机：0 单机练习 / 1 房主（权威端）/ 2 客机（只渲染快照）
static var net_mode: int = 0

# 这一局的地形种子：0 = 还没定（main.gd 会随机一个）。联机时房主定，随开局消息发给客机。
static var map_seed: int = 0

# 再来一局：结算页按 R 时置 true，菜单看到它就不重置联机状态、直接回「选阵营」
static var rematch: bool = false


static func reset() -> void:
	player_side = Side.HUMAN
	human_skill = HumanSkill.SAPPER
	monster_skill = MonsterSkill.BURST
	net_mode = 0
	map_seed = 0
	rematch = false
	mode = Mode.CLASSIC
	match_round = 1
	wins_human = 0
	wins_monster = 0
	used_human = []
	used_monster = []
	last_winner = -1
	lives_left = 3
	human_skills = []
	monster_skills = []
	base_a = Vector2i(0, 0)
	base_b = Vector2i(0, 0)
	my_seat = 0


static func is_bo3() -> bool:
	return mode == Mode.BO3


static func is_escape() -> bool:
	return mode == Mode.ESCAPE


static func is_hunt() -> bool:
	return mode == Mode.HUNT


static func mode_name() -> String:
	match mode:
		Mode.BO3:
			return "三局两胜"
		Mode.ESCAPE:
			return "死里逃生"
		Mode.HUNT:
			return "亡命追猎"
		_:
			return "经典对局"


static func is_online() -> bool:
	return net_mode != 0


static func is_host() -> bool:
	return net_mode == 1


static func is_guest() -> bool:
	return net_mode == 2


static func human_skill_name() -> String:
	match human_skill:
		HumanSkill.BUILDER:
			return "布障者"
		HumanSkill.SAPPER:
			return "地雷师"
		HumanSkill.THROWER:
			return "投掷者"
		_:
			return "求生者"


static func monster_skill_name() -> String:
	match monster_skill:
		MonsterSkill.TOUGH:
			return "强健体魄"
		MonsterSkill.BURST:
			return "爆发力"
		MonsterSkill.LEAP:
			return "弹跳力"
		_:
			return "捕食本能"


static func human_skill_desc() -> String:
	match human_skill:
		HumanSkill.BUILDER:
			return "两组墙，盲放。它穿得过去，但会撞碎墙 —— 那一声你听得见，方位也听得出来。"
		HumanSkill.SAPPER:
			return "三颗雷，盲放。你按下按钮，它只要在雷旁边就吃一发；落下就废。"
		HumanSkill.THROWER:
			return "闪光弹、手雷、燃烧弹各一颗。扔出去那回合就不能再查。"
		_:
			return "第七回合起每回合能连查两格，第十五回合起三格。"


static func monster_skill_desc() -> String:
	match monster_skill:
		MonsterSkill.TOUGH:
			return "两条命。被查中一次不会死，但那之后它会跑起来 —— 下一回合三步。"
		MonsterSkill.BURST:
			return "一回合三步，下一回合动不了。快，但会僵住。"
		MonsterSkill.LEAP:
			return "整局两次：跃过相邻一格，被跳过的那格不留脚印。"
		_:
			return "第七回合起每回合走两步，第十五回合起走三步。"
