extends RefCounted
class_name GameConfig

# 一局游戏的「赛前约定」：谁坐哪边、双方暗选了什么技能。
# 菜单写这里，main.gd 读这里。静态变量在场景切换后依然有效。

enum Side { HUMAN = 0, MONSTER = 1 }
enum HumanSkill { BUILDER = 1, SAPPER = 2, THROWER = 3, SURVIVOR = 4 }
enum MonsterSkill { TOUGH = 1, BURST = 2, LEAP = 3, PREDATOR = 4 }

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
