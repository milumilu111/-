extends Node3D

const Texts := preload("res://texts.gd")

# 《异形入侵》3D 第一屏（人类视角）
# 范围：值班室 + 桌面沙盘 + 探查（0.5s 延迟）/ 三种结果 / 足迹留存与消退 / 脚本对手 / 回合推进
# 不做：技能、联机、AI 推理、正式胜负结算（这里只有占位的三种终止态）

const SIZE := 10
const CELL := 0.28
const BOARD_TOP := 0.030          # 射线求交用的棋盘平面高度
const TRACE_LIFE := 9             # 足迹存活 9 个「年龄」，第 10 回合消失
const MAX_ROUNDS := 20
const SCAN_TIME := 0.5            # 探查延迟：恐惧发生在半秒里

# 地形（与交接包 board.gd 一致，23 格）
var MOUNTAINS := [
	Vector2i(0, 9), Vector2i(1, 9), Vector2i(2, 9),
	Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6),
	Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6),
	Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8),
	Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5),
]

const HUMAN_HOME := Vector2i(0, 0)
const MONSTER_SPAWN := Vector2i(9, 9)
const HEAD_START_STEPS := 4        # 开局异形白走 4 步（不计回合）

# 屏幕底部那句话：粉色、会上下浮 —— 像有人在暗处贴着桌沿说话
const PINK_SOFT := Color(0.98, 0.62, 0.78)
const PINK := Color(1.00, 0.45, 0.66)
const PINK_HOT := Color(1.00, 0.28, 0.48)
const RESULT_Y := 844.0
const SAY_MIN_MS := 1000
const RESULT_Y_END := 766.0
const RESULT_FLOAT_AMP := 4.5
const RESULT_FLOAT_SPEED := 1.9
const LAMP_BASE_ENERGY := 6.0

var mountain_set := {}
var visited := {}                  # 异形走过的所有格子（过去时信息源）
var traces: Array = []             # {cell, round, node, mat}
var monster_pos := MONSTER_SPAWN

var round_no := 1
var probes_used := 0
var player_turn := true
var scanning := false
var ended := false

var camera: Camera3D
var cam_pos := Vector3(0.0, 2.40, 2.60)
var cam_yaw := 0.0
var cam_pitch := -38.0
var look_target_yaw := 0.0
var look_target_pitch := -38.0
var looking := false
var top_down := false

# 镜头手感：呼吸（几乎看不见的慢晃）+ 震动（撞墙、爆炸时）
var dust: GPUParticles3D
var breath_t := 0.0
var shake := 0.0
var shake_rng := RandomNumberGenerator.new()
var clock_minute: Node3D
var clock_hour: Node3D

var hud_round: Label
var hud_round_big: Label
var hud_round_pre: Label
var hud_round_post: Label
var hud_round_ticks: Array = []
var hud_probes: Label
var hud_hint: Label
var hud_result: Label
var hud_layer: CanvasLayer
var result_tween: Tween
var hud_end: Label
var overlay_mat: ShaderMaterial
var result_float_t := 0.0          # 底部那句话的浮动相位

var world_env: Environment         # 捏在手里：输的时候要把它一起压暗
var pendant_root: Node3D
var bulb_mat: StandardMaterial3D   # 灯泡的自发光材质（灭灯时归零）
var next_lamp_flicker_at := 0.0    # 吊灯下一次自己闪的时间

var audio_probe: AudioStreamPlayer
var audio_step: AudioStreamPlayer
var audio_hit: AudioStreamPlayer
var audio_heart: AudioStreamPlayer
var bgm: AudioStreamPlayer
const BGM_DB := -9.0

var monster_phase := 0             # 0 = 这一回合走 3 步，1 = 这一回合不动
var actions_left := 1              # 人类这一回合还能行动几次（求生者会 >1）
var survivor_t7 := false           # 求生者：第 7 回合的提示只播一次
var survivor_t15 := false          # 求生者：第 15 回合的提示只播一次
var step_taken := 0                # 开局白走的 4 步（与 round_no 分开计数，不能混用）
var burst_index := 0               # 第几次爆发，用来安排「幌子」
var ai_decoy := Vector2i(-1, -1)   # 幌子目标
var ai_decoy_bursts := 0           # 还要往幌子走几次爆发
var opening := false               # 开局段：人类不能行动
var open_hint_hold := 0            # 开局提示多留一会儿（毫秒时间戳）
var side := 0                      # 0 = 人类席，1 = 异形席（坐在对面）
var monster_steps := 0             # 异形席：本回合还能走几步
var self_marker: MeshInstance3D = null   # 异形席上代表「你」的那颗暗红点
var human_marks := []              # 异形席：他查过的格子（永久留痕）
var perm_fp_root: Node3D = null    # 异形席：自己的永久脚印都挂在这里
var perm_fp_cells := {}            # 已画过脚印的格子，防重复

var eyes: Array = []               # {node, mat, pos}
var eye_active: Dictionary = {}
var next_eye_at := 0.0
var next_ambient_at := 0.0

var cell_mats: Array = []
var mountain_mat: StandardMaterial3D
var board_root: Node3D
var lamp: SpotLight3D

# —— 技能与工事（GDD S4） ——
var human_skill := 2               # 1 布障者 / 2 地雷师 / 3 投掷者
var monster_skill := 2             # 1 强健体魄 / 2 爆发力 / 3 弹跳力
var monster_hp := 1.0              # 强健体魄 = 2；燃烧弹会扣 0.5，所以用小数
var wounded := false               # 强健体魄：受伤后下一回合 3 步
var obstacles: Array = []          # 每组障碍 = Array[Vector2i]
var obstacle_set := {}
var mine_list: Array = []          # 每颗雷 = Vector2i（3×3 中心）
var gear_root: Node3D = null
var setup_phase := false           # 部署阶段：人类盲放工事
var remote_deploy := false         # 我是异形，正等对面人类布防（不是我自己要放）
var setup_placed := 0
var setup_vertical := false
var path: Array = []               # 异形走过的有序路径（结算揭晓）
var path_nodes: Array = []
var trail_nodes: Array = []        # 输了之后点亮的那条路（发光脚印）
var human_win := false             # 结束时是否是人类赢（赢就要把它的路画出来）

# —— 步数走完自动结束回合 ——
var _last_steps_seen := 0
var _auto_end_pending := false
var _scan_since := 0
var _say_hold_until := 0
var _say_pending := ""
var _say_pending_col := PINK_SOFT
var end_reason := ""
var end_title := ""
var end_sub := ""
var flash_rect: ColorRect

var ghost_root: Node3D = null      # 部署时跟着鼠标的虚影
var ghost_wall: Node3D = null
var ghost_mine: Node3D = null
var ghost_mat: StandardMaterial3D = null
const MINE_COUNT := 3
var monster_opening := false       # 异形席：开局 4 步还没走完（由玩家自己走）
var leap_left := 0                 # 弹跳力：整局还能跃几次
var stun_turns := 0                # 被闪光弹晃住的回合数（那回合它不能动）
var throw_left := {"flash": 1, "nade": 1, "fire": 1}   # 投掷者：每种一颗
var armed_throw := ""             # 已经拿起、等着点格子的那一个
var nade_cell := Vector2i(-1, -1)  # 手雷落点
var nade_fuse := 0                 # 还有几个异形回合就炸
var fires: Array = []              # 燃烧区：{cell, turns}
var _applying_snapshot := false    # 客机：正在套用快照（别回环广播）
var turn_side := 0                 # 联机：现在轮到哪一边行动（0 人类 / 1 异形）


func _ready() -> void:
	randomize()
	# 每局地形随机：种子存在 GameConfig 里，联机时双方用同一个种子生成同一张图
	var rng := RandomNumberGenerator.new()
	if GameConfig.map_seed == 0:
		GameConfig.map_seed = int(randi() % 1000000000) + 1
	rng.seed = GameConfig.map_seed
	MOUNTAINS = _gen_mountains(rng)
	mountain_set = {}
	for m in MOUNTAINS:
		mountain_set[m] = true
	visited[MONSTER_SPAWN] = true

	_build_environment()
	_build_pendant()
	_build_room()
	_build_board()
	_build_camera()
	_build_dust()
	_build_hud()
	_build_audio()
	_build_eyes()
	_build_gear_root()
	_build_ghost()

	# 读菜单里暗选的结果
	human_skill = GameConfig.human_skill
	monster_skill = GameConfig.monster_skill
	side = GameConfig.player_side
	# 安全阀：配置说是联机，但其实没有活着的连接（比如上一局联机按 R 重开过）
	# 那就当单机打，免得「等对面」等到天荒地老
	# 注意只认 STATE_IDLE：房主刚接进连接时状态会短暂是 CONNECTING（正在握手），那不是「没人」
	var nn := _net()
	if GameConfig.is_online() and (nn == null or nn.status == 0):
		GameConfig.net_mode = 0
	monster_hp = 2.0 if monster_skill == GameConfig.MonsterSkill.TOUGH else 1.0
	leap_left = 2 if monster_skill == GameConfig.MonsterSkill.LEAP else 0
	path = [MONSTER_SPAWN]

	next_eye_at = _now() + 7.0
	next_ambient_at = _now() + 4.0
	next_lamp_flicker_at = _now() + randf_range(8.0, 16.0)

	_refresh_hud()
	_refresh_traces()

	var n := _net()
	if n != null:
		n.message.connect(_on_net_msg)
		if GameConfig.is_online() and not n.peer_left.is_connected(_on_peer_left):
			n.peer_left.connect(_on_peer_left)

	if GameConfig.is_guest():
		# 客机：不跑规则，等房主的快照
		_apply_seat_visuals() if side == GameConfig.Side.MONSTER else null
		if human_skill == GameConfig.HumanSkill.THROWER and side == GameConfig.Side.HUMAN:
			# 投掷者没有布防 —— 直接告诉房主「我不用布，开局吧」
			await get_tree().create_timer(0.4).timeout
			_net_send({"t": "cmd", "a": "deploy_done"})
		_say(Texts.s("guest_wait"))
		hud_result.modulate.a = 1.0
		return

	if side == GameConfig.Side.MONSTER:
		_apply_seat_visuals()
		if GameConfig.is_online():
			# 联机：对面是人类，他会自己布防；我等他布完
			setup_phase = true
			remote_deploy = true
			setup_placed = 0
			player_turn = false
			turn_side = 0
			_notify(Texts.s("seat_wait_deploy"))
			_refresh_hud()
			# 对面的「布防完了」可能比这个场景早到（那时我还在菜单里，消息被丢了）
			# 所以隔几秒问一次，直到他真的布完
			_resync_deploy()
			return
		_ai_deploy()
		# 开局那 4 步由你自己走 —— 不是脚本替你走完再交给你
		monster_opening = true
		monster_steps = HEAD_START_STEPS
		player_turn = true
		_rebuild_perm_footprints()
		_say(Texts.s("seat_opening"))
		hud_result.modulate.a = 1.0
		_refresh_hud()
	elif human_skill == GameConfig.HumanSkill.BUILDER or human_skill == GameConfig.HumanSkill.SAPPER:
		_enter_setup()
	else:
		# 投掷者没有部署阶段 —— 直接进对局；但联机时开局的 4 步仍归对面走
		if GameConfig.is_online() and _net() != null and _net().is_online():
			monster_opening = true
			monster_steps = HEAD_START_STEPS
			turn_side = 1
			player_turn = false
			_notify("没有布防。他正在走开局的 4 步 —— 不计回合，你看不见。")
			_net_send({"t": "turn", "who": 1})
			_refresh_hud()
		else:
			_opening_move()


# ---------------------------------------------------------------- 场景搭建

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.010, 0.011, 0.016)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.20, 0.29)
	env.ambient_light_energy = 0.46
	env.fog_enabled = true
	env.fog_light_color = Color(0.025, 0.028, 0.042)
	env.fog_density = 0.026
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	world_env = env
	add_child(we)

	# 吊灯：唯一的主光源，从桌子正上方吊下来，只照亮桌面中间那一块
	lamp = SpotLight3D.new()
	lamp.position = Vector3(0.0, 1.10, 0.0)
	lamp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	lamp.light_color = Color(1.0, 0.84, 0.62)
	lamp.light_energy = LAMP_BASE_ENERGY
	lamp.spot_range = 6.5
	lamp.spot_angle = 56.0
	lamp.spot_attenuation = 1.10
	lamp.shadow_enabled = true
	lamp.shadow_bias = 0.04
	add_child(lamp)

	var cold := OmniLight3D.new()
	cold.position = Vector3(-2.6, 1.4, -2.2)
	cold.light_color = Color(0.26, 0.40, 0.72)
	cold.light_energy = 0.40
	cold.omni_range = 5.0
	add_child(cold)

	# 顶部软补光：把桌面上远离吊灯的地方垫起来，避免角落吃掉棋盘
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-58.0, 24.0, 0.0)
	fill.light_color = Color(1.0, 0.90, 0.78)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	add_child(fill)


func _build_pendant() -> void:
	# 看得见的那盏灯：吊线 + 灯罩 + 灯泡。光本身还是上面那盏 SpotLight3D。
	pendant_root = Node3D.new()
	pendant_root.name = "Pendant"
	add_child(pendant_root)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.10, 0.095, 0.09)
	metal.metallic = 0.55
	metal.roughness = 0.42

	var cord_mesh := CylinderMesh.new()
	cord_mesh.top_radius = 0.006
	cord_mesh.bottom_radius = 0.006
	cord_mesh.height = 1.70
	cord_mesh.radial_segments = 8
	var cord := MeshInstance3D.new()
	cord.mesh = cord_mesh
	cord.material_override = metal
	cord.position = Vector3(0.0, 2.05, 0.0)
	pendant_root.add_child(cord)

	var shade_mesh := CylinderMesh.new()
	shade_mesh.top_radius = 0.036
	shade_mesh.bottom_radius = 0.155
	shade_mesh.height = 0.16
	shade_mesh.radial_segments = 24
	var shade := MeshInstance3D.new()
	shade.mesh = shade_mesh
	shade.material_override = metal
	shade.position = Vector3(0.0, 1.19, 0.0)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pendant_root.add_child(shade)

	# 灯泡：唯一自发光的东西，灭了整间屋子就真的黑了
	bulb_mat = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.90, 0.72)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.80, 0.52)
	bulb_mat.emission_energy_multiplier = 3.2
	bulb_mat.roughness = 0.30

	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.032
	bulb_mesh.height = 0.064
	bulb_mesh.radial_segments = 16
	bulb_mesh.rings = 8
	var bulb := MeshInstance3D.new()
	bulb.mesh = bulb_mesh
	bulb.material_override = bulb_mat
	bulb.position = Vector3(0.0, 1.112, 0.0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pendant_root.add_child(bulb)


func _build_room() -> void:
	var root := Node3D.new()
	root.name = "Room"
	add_child(root)

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(9.0, 0.1, 9.0)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.035, 0.035, 0.04)
	floor_mat.roughness = 1.0
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	floor_inst.material_override = floor_mat
	floor_inst.position = Vector3(0.0, -0.95, 0.0)
	root.add_child(floor_inst)

	var table_mesh := BoxMesh.new()
	table_mesh.size = Vector3(3.9, 0.10, 3.2)
	var table_mat := StandardMaterial3D.new()
	table_mat.albedo_color = Color(0.095, 0.075, 0.058)
	table_mat.roughness = 0.82
	table_mat.metallic = 0.05
	var table := MeshInstance3D.new()
	table.mesh = table_mesh
	table.material_override = table_mat
	table.position = Vector3(0.0, -0.05, 0.0)
	root.add_child(table)

	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.12, 0.09, 0.07)
	edge_mat.roughness = 0.9
	for i in range(4):
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.12, 0.9, 0.12)
		leg.mesh = lm
		leg.material_override = edge_mat
		var sx := -1.75 if i % 2 == 0 else 1.75
		var sz := -1.35 if i < 2 else 1.35
		leg.position = Vector3(sx, -0.5, sz)
		root.add_child(leg)

	_build_walls(root)
	_build_window(root, -2.74, 1.95)
	_build_window(root, 2.74, -1.95)
	_build_door(root)
	_build_clock(root, -2.72, -2.35)
	_build_clock(root, 2.72, 2.35)


func _room_mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


func _build_walls(root: Node3D) -> void:
	# 四面墙只是"这间屋子存在"的证据：几乎全黑，只在边缘露出一点形。
	# 墙要够高 —— 高到从画面里看不见墙顶，才有"在屋里"的压迫感。
	var wall_mat := _room_mat(Color(0.055, 0.056, 0.062), 1.0)
	var wh := 3.2
	var yc := 1.0
	var specs := [
		[Vector3(9.0, wh, 0.10), Vector3(0.0, yc, -2.80)],   # 人类席正对
		[Vector3(9.0, wh, 0.10), Vector3(0.0, yc, 2.80)],    # 异形席正对
		[Vector3(0.10, wh, 9.0), Vector3(-4.20, yc, 0.0)],   # 左
		[Vector3(0.10, wh, 9.0), Vector3(4.20, yc, 0.0)],    # 右
	]
	for sp in specs:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sp[0]
		mi.mesh = bm
		mi.material_override = wall_mat
		mi.position = sp[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


func _build_window(root: Node3D, wz: float, cx: float) -> void:
	# 墙上那扇窗：外面永远是夜。窗洞很高 —— 高到上沿被画面切掉，
	# 这样"墙很高"不是靠说的，是靠它出画。
	var frame_mat := _room_mat(Color(0.075, 0.072, 0.068), 0.95)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass_mat.albedo_color = Color(0.05, 0.075, 0.125)
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(0.10, 0.16, 0.28)
	glass_mat.emission_energy_multiplier = 0.42

	var cy := 0.62
	var w := 1.90
	var h := 1.35
	var inward := 0.05 if wz < 0.0 else -0.05

	var glass := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(w, h, 0.02)
	glass.mesh = gm
	glass.material_override = glass_mat
	glass.position = Vector3(cx, cy, wz)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)

	# 四边窗框
	var fr := [
		[Vector3(w + 0.10, 0.06, 0.05), Vector3(cx, cy + h * 0.5 + 0.03, wz + inward)],
		[Vector3(w + 0.10, 0.06, 0.05), Vector3(cx, cy - h * 0.5 - 0.03, wz + inward)],
		[Vector3(0.06, h + 0.10, 0.05), Vector3(cx - w * 0.5 - 0.03, cy, wz + inward)],
		[Vector3(0.06, h + 0.10, 0.05), Vector3(cx + w * 0.5 + 0.03, cy, wz + inward)],
	]
	for f in fr:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = f[0]
		mi.mesh = bm
		mi.material_override = frame_mat
		mi.position = f[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# 三根竖栏杆
	for i in range(3):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, h, 0.03)
		mi.mesh = bm
		mi.material_override = frame_mat
		mi.position = Vector3(cx - w * 0.5 + w * (i + 1) / 4.0, cy, wz + inward)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

	# 雨：贴玻璃、只落在窗洞里那一条竖带子上（窗框外不落）。
	var rain := GPUParticles3D.new()
	rain.amount = 150
	rain.lifetime = 0.50
	rain.preprocess = 1.0
	rain.position = Vector3(cx, cy + h * 0.5 - 0.03, wz + inward)
	rain.visibility_aabb = AABB(Vector3(-w, -h, -0.5), Vector3(w * 2.0, h * 2.0, 1.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(w * 0.5 - 0.05, 0.03, 0.02)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 1.5
	pm.initial_velocity_min = 0.9
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.0, -4.4, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.color = Color(0.62, 0.72, 0.92, 0.30)
	rain.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.006, 0.15)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.66, 0.76, 0.96, 0.32)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	streak.material = smat
	rain.draw_pass_1 = streak
	root.add_child(rain)


func _build_door(root: Node3D) -> void:
	# 左边的门：关着。门缝下有一条很细的光 —— 走廊还亮着。
	var door_mat := _room_mat(Color(0.085, 0.072, 0.060), 0.92)
	var dm := BoxMesh.new()
	dm.size = Vector3(0.06, 2.30, 1.00)
	var door := MeshInstance3D.new()
	door.mesh = dm
	door.material_override = door_mat
	door.position = Vector3(-4.12, 0.20, -2.10)
	door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(door)

	var gap_mat := StandardMaterial3D.new()
	gap_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gap_mat.albedo_color = Color(0.92, 0.74, 0.42)
	gap_mat.emission_enabled = true
	gap_mat.emission = Color(0.95, 0.70, 0.36)
	gap_mat.emission_energy_multiplier = 1.1
	var gap := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.03, 0.022, 0.92)
	gap.mesh = gm
	gap.material_override = gap_mat
	gap.position = Vector3(-4.09, -0.94, -2.10)
	gap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gap)

	# 门把手
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.035
	km.height = 0.07
	knob.mesh = km
	knob.material_override = _room_mat(Color(0.32, 0.26, 0.16), 0.45)
	knob.position = Vector3(-4.06, -0.10, -1.75)
	knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(knob)


func _build_clock(root: Node3D, z: float, x: float) -> void:
	# 墙上的挂钟：表面几乎看不见，只有指针的暗影。二十回合走完，它就是"天亮"的另一种说法。
	var dir := 1.0 if z < 0.0 else -1.0
	var clock_root := Node3D.new()
	clock_root.name = "Clock"
	clock_root.position = Vector3(x, 0.30, z)
	root.add_child(clock_root)

	var face := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.22
	fm.bottom_radius = 0.22
	fm.height = 0.02
	fm.radial_segments = 24
	face.mesh = fm
	face.material_override = _room_mat(Color(0.13, 0.125, 0.12), 0.9)
	face.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clock_root.add_child(face)

	var minute := _clock_hand(clock_root, 0.125, 0.006, dir)
	var hour := _clock_hand(clock_root, 0.082, 0.008, dir)
	if z < 0.0:
		clock_minute = minute
		clock_hour = hour


func _clock_hand(root: Node3D, length: float, thick: float, dir: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, 0.0, 0.014 * dir)
	root.add_child(pivot)
	var hand := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, length, 0.006)
	hand.mesh = bm
	hand.material_override = _room_mat(Color(0.42, 0.40, 0.37), 0.55)
	hand.position = Vector3(0.0, length * 0.5, 0.0)
	hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(hand)
	return pivot


func _tick_clock() -> void:
	# 20 回合 = 一夜。分针走满一圈，时针走一格。
	if clock_minute == null or clock_hour == null:
		return
	var t := float(mini(round_no, MAX_ROUNDS))
	clock_minute.rotation_degrees.z = -t * (360.0 / float(MAX_ROUNDS))
	clock_hour.rotation_degrees.z = -t * (30.0 / float(MAX_ROUNDS))


func _build_board() -> void:
	board_root = Node3D.new()
	board_root.name = "Board"
	add_child(board_root)

	# 棋盘底座
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(SIZE * CELL + 0.10, 0.03, SIZE * CELL + 0.10)
	plate.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.085, 0.075, 0.062)
	pmat.roughness = 0.95
	plate.material_override = pmat
	plate.position = Vector3(0.0, 0.005, 0.0)
	board_root.add_child(plate)

	# 三种底色，做一点随机温差
	for i in range(3):
		var c := StandardMaterial3D.new()
		c.albedo_color = Color(0.155, 0.135, 0.112).lerp(Color(0.185, 0.160, 0.128), i * 0.5)
		c.roughness = 0.95
		cell_mats.append(c)

	mountain_mat = StandardMaterial3D.new()
	mountain_mat.albedo_color = Color(0.085, 0.090, 0.105)
	mountain_mat.roughness = 0.95
	mountain_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	for y in range(SIZE):
		for x in range(SIZE):
			var cell := Vector2i(x, y)
			if mountain_set.has(cell):
				_add_box(_cell_pos(cell) + Vector3(0.0, 0.115, 0.0), Vector3(0.255, 0.22, 0.255), mountain_mat)
			else:
				var mat = cell_mats[(x + y * 3) % 3]
				_add_box(_cell_pos(cell) + Vector3(0.0, 0.010, 0.0), Vector3(0.262, 0.020, 0.262), mat)

	# 人类基地：暖橙，唯一亮着的东西
	var home_mat := StandardMaterial3D.new()
	home_mat.albedo_color = Color(1.0, 0.55, 0.18)
	home_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add_box(_cell_pos(HUMAN_HOME) + Vector3(0.0, 0.022, 0.0), Vector3(0.22, 0.02, 0.22), home_mat)

	var home_light := OmniLight3D.new()
	home_light.position = _cell_pos(HUMAN_HOME) + Vector3(0.0, 0.16, 0.0)
	home_light.light_color = Color(1.0, 0.55, 0.22)
	home_light.light_energy = 0.75
	home_light.omni_range = 1.1
	board_root.add_child(home_light)


func _add_box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	board_root.add_child(mi)
	return mi


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.position = cam_pos
	camera.rotation_degrees = Vector3(cam_pitch, cam_yaw, 0.0)
	camera.current = true
	add_child(camera)


func _build_dust() -> void:
	# 光束里的灰：只在灯照到的那块上空飘，慢慢上升、慢慢横移。
	# 这是「坐在这儿」唯一的证据 —— 除了你，这里还有东西在动。
	dust = GPUParticles3D.new()
	dust.amount = 70
	dust.lifetime = 14.0
	dust.preprocess = 3.0
	dust.position = Vector3(0.0, 0.30, 0.0)
	dust.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 1.4, 3.0))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.95, 0.20, 0.95)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.006
	pm.initial_velocity_max = 0.030
	pm.gravity = Vector3(0.0006, 0.004, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.16
	pm.turbulence_noise_scale = 1.1
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color = Color(1.0, 0.94, 0.82, 0.32)
	dust.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.008, 0.008)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.95, 0.85, 0.16)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_receive_shadows = true
	quad.material = mat
	dust.draw_pass_1 = quad
	add_child(dust)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_layer = layer

	var cjk := SystemFont.new()
	cjk.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "Segoe UI"])

	# 暗角 + 颗粒：先加，保证文字在它之上，不被压暗
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := load("res://fx_overlay.gdshader")
	if sh != null:
		overlay_mat = ShaderMaterial.new()
		overlay_mat.shader = sh
		rect.material = overlay_mat
	layer.add_child(rect)

	hud_round = _make_label(cjk, 18, Color(0.72, 0.70, 0.64), Vector2(28, 22))
	hud_round.visible = false        # 回合数搬到正上方了，左上角不再重复
	hud_probes = _make_label(cjk, 15, Color(0.52, 0.51, 0.47), Vector2(28, 24))
	hud_hint = _make_label(cjk, 14, Color(0.40, 0.40, 0.38), Vector2(28, 52))
	_build_round_hud(cjk)
	hud_result = _make_label(cjk, 23, Color(0.95, 0.93, 0.88), Vector2(500, 844))
	hud_result.size = Vector2(600, 44)
	hud_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_end = _make_label(cjk, 44, Color(0.95, 0.45, 0.40), Vector2(500, 300))
	hud_end.size = Vector2(600, 80)
	hud_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_end.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_end.visible = false

	# 全屏闪白（闪光弹炸在它脸上时用）
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	layer.add_child(flash_rect)


func _build_round_hud(font: SystemFont) -> void:
	# 正上方那一条：第 XX / 20 回合，底下一排二十个小刻度，走过的会亮
	var bg := ColorRect.new()
	bg.position = Vector2(628, 8)
	bg.size = Vector2(344, 74)
	bg.color = Color(0.06, 0.05, 0.05, 0.52)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(bg)

	var line := ColorRect.new()
	line.position = Vector2(700, 36)
	line.size = Vector2(200, 1)
	line.color = Color(0.62, 0.42, 0.48, 0.35)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(line)

	hud_round_pre = _make_label(font, 15, Color(0.62, 0.56, 0.54), Vector2(668, 12))
	hud_round_pre.text = "第"
	hud_round_pre.size = Vector2(30, 24)
	hud_round_pre.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	hud_round_big = _make_label(font, 38, Color(0.98, 0.92, 0.86), Vector2(702, 0))
	hud_round_big.text = "1"
	hud_round_big.size = Vector2(66, 48)
	hud_round_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_round_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	hud_round_post = _make_label(font, 15, Color(0.62, 0.56, 0.54), Vector2(770, 12))
	hud_round_post.text = "/ %d 回合" % MAX_ROUNDS
	hud_round_post.size = Vector2(120, 24)

	hud_round_ticks.clear()
	var tw := 12.0
	var gap := 4.0
	var total := MAX_ROUNDS * tw + (MAX_ROUNDS - 1) * gap
	var x0 := 800.0 - total * 0.5
	for i in MAX_ROUNDS:
		var t := ColorRect.new()
		t.position = Vector2(x0 + i * (tw + gap), 54)
		t.size = Vector2(tw, 4)
		t.color = Color(0.26, 0.24, 0.24, 0.55)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(t)
		hud_round_ticks.append(t)


func _update_round_hud() -> void:
	var n := clampi(round_no, 1, MAX_ROUNDS)
	hud_round_big.text = str(n)
	for i in hud_round_ticks.size():
		var t: ColorRect = hud_round_ticks[i]
		if i < n - 1:
			t.color = Color(0.92, 0.36, 0.52, 0.80)
		elif i == n - 1:
			t.color = Color(1.00, 0.28, 0.48, 1.00)
		else:
			t.color = Color(0.26, 0.24, 0.24, 0.55)


func _make_label(font: SystemFont, size: int, color: Color, pos: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(l)
	return l


func _build_audio() -> void:
	audio_probe = _make_audio("res://sfx/sfx_probe.wav", 0.0)
	audio_step = _make_audio("res://sfx/sfx_footstep.wav", 2.0)
	audio_hit = _make_audio("res://sfx/sfx_hit.wav", 1.0)
	audio_heart = _make_audio("res://sfx/sfx_heartbeat.wav", -6.0)
	if audio_heart != null and audio_heart.stream != null:
		audio_heart.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		audio_heart.play()
	_build_bgm()


func _build_bgm() -> void:
	# 房间底噪：没有拍点、没有旋律，只是一间屋子该有的声音。
	# 循环点靠素材上的首尾交叉淡化藏起来，听不出「又从头开始」。
	var stream := load("res://audio/bgm_room_dark.wav") as AudioStreamWAV
	if stream == null:
		return
	# 让它自己循环（样本级无缝）。只有 PCM 才能这样算帧数；被导入成 QOA 时
	# 帧数算不出来，就靠下面的 finished 回调接上去。
	var bytes_per_sample := 0
	match stream.format:
		AudioStreamWAV.FORMAT_8_BITS:
			bytes_per_sample = 1
		AudioStreamWAV.FORMAT_16_BITS:
			bytes_per_sample = 2
	if bytes_per_sample > 0:
		var frames: int = stream.data.size() / (bytes_per_sample * (2 if stream.stereo else 1))
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frames
	bgm = AudioStreamPlayer.new()
	bgm.stream = stream
	bgm.volume_db = BGM_DB
	add_child(bgm)
	bgm.finished.connect(_on_bgm_finished)
	bgm.play()


func _on_bgm_finished() -> void:
	# 万一导入设置里的循环没生效（比如被重新导入成 QOA），就手动接上：
	# 素材本身首尾已经交叉淡化过，从 0 重放也听不出接缝。
	if bgm != null:
		bgm.play()


func _make_audio(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = db
	add_child(p)
	return p


func _fx_sound(pitch: float, db: float) -> void:
	# 一次性的"手感音"：放东西、按按钮、扔出去。用同一个撞击样本变调，
	# 每次开一个新的 player，这样连点时声音能叠起来而不是互相打断。
	if audio_hit == null or audio_hit.stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = audio_hit.stream
	p.pitch_scale = pitch
	p.volume_db = db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------- 坐标

func _cell_pos(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - 4.5) * CELL, 0.0, (cell.y - 4.5) * CELL)


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < SIZE and c.y >= 0 and c.y < SIZE


func _is_mountain(c: Vector2i) -> bool:
	return mountain_set.has(c)


# ---------------------------------------------------------------- 随机地形

func _gen_mountains(rng: RandomNumberGenerator) -> Array:
	# 每局长一张新地图：几条断续的山脊，不封死路，基地和出生点永远空着
	var blocked := {}
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var target := rng.randi_range(19, 26)
	var guard := 0
	while blocked.size() < target and guard < 600:
		guard += 1
		var cur := Vector2i(rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1))
		var dir: Vector2i = dirs[rng.randi_range(0, 3)]
		var run := rng.randi_range(2, 5)
		for i in run:
			if _grow_ok(cur, blocked):
				blocked[cur] = true
			if rng.randf() < 0.30:
				# 拐弯：横竖互换
				dir = Vector2i(dir.y, dir.x)
			cur += dir
			if not _in_bounds(cur):
				break
	# 保证从出生点能走到基地：不通就一点点拆，先拆离基地远的
	var tries := 0
	while not _map_connected(blocked) and tries < 80:
		tries += 1
		var far := []
		for c in blocked.keys():
			if _cheb(c, HUMAN_HOME) > 2:
				far.append(c)
		if far.is_empty():
			break
		blocked.erase(far[rng.randi_range(0, far.size() - 1)])
	# 出生点周围留两格空地，别让它一开局就被关在笼子里
	for c in blocked.keys():
		if _cheb(c, MONSTER_SPAWN) <= 0:
			blocked.erase(c)
	var out := []
	for c in blocked.keys():
		out.append(c)
	out.sort_custom(func(a, b): return a.y * 100 + a.x < b.y * 100 + b.x)
	return out


func _grow_ok(c: Vector2i, blocked: Dictionary) -> bool:
	if not _in_bounds(c) or blocked.has(c):
		return false
	if c == HUMAN_HOME or c == MONSTER_SPAWN:
		return false
	# 基地紧邻的两格不封（留个门）
	if _cheb(c, HUMAN_HOME) <= 1:
		return false
	return true


func _map_connected(blocked: Dictionary) -> bool:
	# 从异形出生点四邻 BFS，看能不能摸到人类基地
	var q := [MONSTER_SPAWN]
	var seen := {MONSTER_SPAWN: true}
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		if c == HUMAN_HOME:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not _in_bounds(n) or blocked.has(n) or seen.has(n):
				continue
			seen[n] = true
			q.append(n)
	return false


func _cell_at_mouse() -> Vector2i:
	return _cell_at(get_viewport().get_mouse_position())


func _cell_at(mp: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(mp)
	var normal := camera.project_ray_normal(mp)
	if absf(normal.y) < 0.00001:
		return Vector2i(-1, -1)
	var t := (BOARD_TOP - origin.y) / normal.y
	if t <= 0.0:
		return Vector2i(-1, -1)
	var hit := origin + normal * t
	var fx := hit.x / CELL + 4.5
	var fy := hit.z / CELL + 4.5
	var cell := Vector2i(int(round(fx)), int(round(fy)))
	if not _in_bounds(cell):
		return Vector2i(-1, -1)
	if absf(fx - cell.x) > 0.5 or absf(fy - cell.y) > 0.5:
		return Vector2i(-1, -1)
	return cell


# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _dismiss_eye_under_cursor(mb.position):
				return
			if setup_phase and side == 0:
				_setup_click(mb.position)
			elif side == 1:
				_monster_move_at(mb.position)
			elif armed_throw != "":
				_throw_at(mb.position)
			elif not _try_detonate_at(mb.position):
				_try_probe(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			looking = mb.pressed
	elif event is InputEventMouseMotion and looking:
		var mm := event as InputEventMouseMotion
		look_target_yaw = clampf(look_target_yaw - mm.relative.x * 0.10, -20.0, 20.0)
		look_target_pitch = clampf(look_target_pitch - mm.relative.y * 0.08, -52.0, -18.0)
	elif event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo:
			match ek.keycode:
				KEY_E:
					_toggle_top_down()
				KEY_F1:
					_switch_side()
				KEY_1:
					_arm_throw("flash")
				KEY_2:
					_arm_throw("nade")
				KEY_3:
					_arm_throw("fire")
				KEY_ESCAPE:
					if armed_throw != "":
						armed_throw = ""
						_say(Texts.s("put_down"))
						hud_result.modulate.a = 1.0
						_refresh_hud()
				KEY_SPACE:
					if setup_phase and side == 0:
						_finish_setup()
					elif side == 1:
						_end_monster_turn()
				KEY_W:
					if side == 1:
						_step_screen(0, ek.shift_pressed)
				KEY_A:
					if side == 1:
						_step_screen(1, ek.shift_pressed)
				KEY_S:
					if side == 1:
						_step_screen(2, ek.shift_pressed)
				KEY_D:
					if side == 1:
						_step_screen(3, ek.shift_pressed)
				KEY_R:
					if setup_phase and side == 0:
						setup_vertical = not setup_vertical
					elif ended:
						_back_to_menu()
				KEY_M:
					# M 静音/恢复底噪（不想听的时候随手关掉）
					if bgm != null:
						bgm.volume_db = -80.0 if bgm.volume_db > -40.0 else BGM_DB


func _toggle_top_down() -> void:
	top_down = not top_down
	if top_down:
		look_target_yaw = 0.0
		look_target_pitch = -89.0
	else:
		look_target_pitch = -38.0


func _back_to_menu() -> void:
	# 回标题：联机的先挂断，免得对面以为你还坐着
	var n := _net()
	if n != null and n.is_online():
		n.close()
	GameConfig.net_mode = 0
	get_tree().change_scene_to_file("res://menu.tscn")


func _process(delta: float) -> void:
	var speed := 7.0 * delta
	cam_yaw = lerpf(cam_yaw, look_target_yaw, speed)
	cam_pitch = lerpf(cam_pitch, look_target_pitch, speed)
	var base_yaw := 180.0 if side == 1 else 0.0
	var seat_z := -2.60 if side == 1 else 2.60
	if top_down:
		cam_pos = cam_pos.lerp(Vector3(0.0, 4.30, 0.02), speed)
	else:
		cam_pos = cam_pos.lerp(Vector3(0.0, 2.40, seat_z), speed)
	camera.position = cam_pos + _camera_jitter(delta)
	camera.rotation_degrees = Vector3(cam_pitch + _breath(0.22, 0.37), base_yaw + cam_yaw + _breath(0.30, 0.23), _breath(0.34, 0.19))

	_tick_ambient(delta)
	_tick_eyes(delta)
	_tick_lamp()
	_tick_clock()
	_tick_result_float(delta)
	_tick_auto_end()
	_tick_scan_watchdog()
	_flush_say()
	_update_heartbeat()
	_update_ghost()


func _breath(amp_deg: float, speed: float) -> float:
	# 呼吸：两个不成整数比的正弦叠在一起，看不出周期，只觉得"在动"
	return (sin(breath_t * speed) * 0.62 + sin(breath_t * speed * 1.73 + 1.1) * 0.38) * amp_deg


func _camera_jitter(delta: float) -> Vector3:
	breath_t += delta
	if shake <= 0.0:
		return Vector3(0.0, sin(breath_t * 0.51) * 0.004, 0.0)
	shake = maxf(0.0, shake - delta * 2.6)
	var a := shake * shake * 0.055
	return Vector3(
		shake_rng.randf_range(-a, a),
		sin(breath_t * 0.51) * 0.004 + shake_rng.randf_range(-a, a),
		shake_rng.randf_range(-a, a)
	)


func _add_shake(amount: float) -> void:
	shake = minf(1.4, shake + amount)


func _tick_scan_watchdog() -> void:	# 保险：scanning 一旦漏成 true，输入会被永久锁死。超过 4 秒没解开就强制放开。
	if not scanning:
		_scan_since = 0
		return
	if _scan_since == 0:
		_scan_since = Time.get_ticks_msec()
	elif Time.get_ticks_msec() - _scan_since > 4000:
		scanning = false
		_scan_since = 0


func _tick_auto_end() -> void:
	# 异形席：步数走完自动交出回合。
	# 例外是「休息回合」—— 那一回合本来就没有步数，要自己按空格确认。
	if side != 1:
		_last_steps_seen = monster_steps
		return
	if ended or not player_turn:
		_last_steps_seen = monster_steps
		return
	if scanning:
		# 正在走这一步：别在这里更新基准，否则「1 → 0」的跃迁会被吃掉
		return
	if _last_steps_seen > 0 and monster_steps <= 0:
		_maybe_auto_end()
	_last_steps_seen = monster_steps


func _maybe_auto_end() -> void:
	if _auto_end_pending:
		return
	_auto_end_pending = true
	await get_tree().create_timer(0.55).timeout
	_auto_end_pending = false
	if ended or side != 1 or not player_turn or scanning or monster_steps > 0:
		return
	_notify(Texts.s("auto_end"))
	_end_monster_turn()


func _tick_lamp() -> void:
	# 吊灯自己也会晃神：不定时闪一下，不为任何事，只是老
	if ended or lamp == null:
		return
	var t := _now()
	if t < next_lamp_flicker_at:
		return
	next_lamp_flicker_at = t + randf_range(9.0, 24.0)
	_flicker_lamp()


func _tick_result_float(delta: float) -> void:
	# 底部那句话一直慢慢上下浮，像有人在桌子对面呼吸
	if hud_result == null:
		return
	result_float_t += delta
	var base_y := RESULT_Y_END if ended else RESULT_Y
	hud_result.position.y = base_y + sin(result_float_t * RESULT_FLOAT_SPEED) * RESULT_FLOAT_AMP


func _update_heartbeat() -> void:
	if audio_heart == null or audio_heart.stream == null:
		return
	var d := absf(float(monster_pos.x)) + absf(float(monster_pos.y))
	var t := clampf(d / 18.0, 0.0, 1.0)
	audio_heart.pitch_scale = lerpf(1.30, 0.88, t)
	audio_heart.volume_db = lerpf(-4.0, -14.0, t)


# ---------------------------------------------------------------- 探查

func _try_probe(at: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if ended or scanning or not player_turn:
		return
	var mp := at
	if mp.x < 0.0:
		mp = get_viewport().get_mouse_position()
	var cell := _cell_at(mp)
	if cell.x < 0:
		return
	if cell == HUMAN_HOME or _is_blocked(cell):
		return
	if GameConfig.is_guest():
		# 客机的探查由房主判定，但手感要一样：本地也放音效、也画那圈扫描环、也等半秒
		scanning = true
		player_turn = false
		_play(audio_probe)
		_spawn_scan_ring(cell)
		_net_send({"t": "cmd", "a": "probe", "c": [cell.x, cell.y]})
		_say(Texts.s("probe_wait"))
		hud_result.add_theme_color_override("font_color", PINK_SOFT)
		hud_result.modulate.a = 1.0
		await get_tree().create_timer(SCAN_TIME).timeout
		scanning = false
		return
	_do_probe(cell)


func _do_probe(cell: Vector2i) -> void:
	scanning = true
	player_turn = false
	_play(audio_probe)
	_spawn_scan_ring(cell)
	await get_tree().create_timer(SCAN_TIME).timeout

	# 判定顺序：先当前位置，再历史痕迹（不能反）
	var result := 0
	if cell == monster_pos:
		result = 2
	elif visited.has(cell):
		result = 1

	probes_used += 1
	_show_result(result)
	_spawn_result_mark(cell, result)
	if result >= 1:
		_add_trace(cell)
	if GameConfig.is_online():
		human_marks.append({"cell": cell, "result": result})

	if result == 2:
		await get_tree().create_timer(0.65).timeout
		_play(audio_hit)
		if _damage_monster():
			human_win = true
			_finish(Texts.s("win_probe_title"), Texts.s("win_probe_sub"), PINK_HOT, "PROBE")
			return
		_say(Texts.s("hit_wounded"))
		hud_result.add_theme_color_override("font_color", PINK_HOT)
		await get_tree().create_timer(1.1).timeout
		await _after_human_action()
		return

	await get_tree().create_timer(0.85).timeout
	await _after_human_action()


func _say(txt: String, col: Color = PINK_SOFT, force: bool = false) -> void:
	# 底部那行提示的统一出口：
	#  · 默认粉色（不再出现「白字」）
	#  · 最短停留 1 秒 —— 1 秒内的新提示先排着，到点再顶上去
	if txt == "":
		return
	var now := Time.get_ticks_msec()
	if not force and now < _say_hold_until and hud_result.text != "" and txt != hud_result.text:
		_say_pending = txt
		_say_pending_col = col
		return
	_apply_say(txt, col)
	_say_hold_until = now + SAY_MIN_MS


func _apply_say(txt: String, col: Color) -> void:
	if result_tween != null and result_tween.is_valid():
		result_tween.kill()
	hud_result.text = txt
	hud_result.add_theme_color_override("font_color", col)
	hud_result.modulate.a = 1.0


func _flush_say() -> void:
	# 排队里的那条，等够最短停留就放出来
	if _say_pending == "":
		return
	if ended:
		# 终局了：排队里那条（多半是「轮到你了」）不许再弹出来盖掉结算文案
		_say_pending = ""
		return
	if Time.get_ticks_msec() < _say_hold_until:
		return
	var t := _say_pending
	var c := _say_pending_col
	_say_pending = ""
	_apply_say(t, c)
	_say_hold_until = Time.get_ticks_msec() + SAY_MIN_MS


func _show_result(result: int) -> void:
	match result:
		0:
			_say(Texts.s("res_empty"), PINK_SOFT)
		1:
			_say(Texts.s("res_trail"), PINK)
		2:
			_say(Texts.s("res_hit"), PINK_HOT)
	hud_result.modulate.a = 1.0
	if result_tween != null and result_tween.is_valid():
		result_tween.kill()
	result_tween = create_tween()
	result_tween.tween_interval(2.2)
	result_tween.tween_property(hud_result, "modulate:a", 0.30, 1.4)


# ---------------------------------------------------------------- 异形回合

func _opening_move() -> void:
	# 开局段：异形白走 4 步，不计入回合数，人类此时不能行动。
	# 这 4 步是「你一开局就已经落后 4 步信息」，不是随便送的。
	if opening:
		return
	opening = true
	player_turn = false
	ai_decoy = _pick_far_cell()
	_refresh_hud()
	for i in range(4):
		var nxt := _bfs_next(monster_pos, ai_decoy)
		if nxt == monster_pos:
			nxt = _random_free_neighbor(monster_pos)
		if nxt == monster_pos:
			break
		monster_pos = nxt
		visited[monster_pos] = true
		step_taken += 1
		path.append(monster_pos)
		# 开局这 4 步也算它走过的路：房主要记下来转发给客机异形
		_add_perm_footprint(monster_pos)
		await get_tree().create_timer(0.22).timeout
	opening = false
	player_turn = true
	open_hint_hold = Time.get_ticks_msec() + 2600
	if side == 1:
		# 你坐异形席：开盘 4 步走完之后，直接轮到你的第一个回合
		monster_steps = _next_monster_budget()
		_rebuild_perm_footprints()
	_refresh_hud()


func _pick_far_cell() -> Vector2i:
	# 开局用：从出生点做一次 BFS，挑一个「真能走到、而且离基地够远」的格子，
	# 免得它绕了 4 步又回到原点（那样开局看起来像没动）。
	var dist := {monster_pos: 0}
	var queue: Array[Vector2i] = [monster_pos]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		for d in dirs:
			var nb: Vector2i = cur + d
			if not _in_bounds(nb) or _is_blocked(nb) or dist.has(nb):
				continue
			dist[nb] = int(dist[cur]) + 1
			queue.append(nb)
	var best := monster_pos
	var best_score := -1
	for c in dist.keys():
		if int(dist[c]) < 4:
			continue
		var score := absi(c.x - HUMAN_HOME.x) + absi(c.y - HUMAN_HOME.y)
		if score > best_score:
			best_score = score
			best = c
	return best


func _pick_decoy_cell() -> Vector2i:
	# 幌子：在「和基地差不多远」的一圈里挑个横向错开的点 ——
	# 足迹会拐弯、走岔、甚至回头，但整体还是在逼近，不会原地打转。
	var ring := absi(monster_pos.x - HUMAN_HOME.x) + absi(monster_pos.y - HUMAN_HOME.y)
	for i in range(80):
		var c := Vector2i(randi_range(0, SIZE - 1), randi_range(0, SIZE - 1))
		if _is_mountain(c) or c == HUMAN_HOME or c == monster_pos:
			continue
		var cring := absi(c.x - HUMAN_HOME.x) + absi(c.y - HUMAN_HOME.y)
		if cring < ring - 1 or cring > ring + 1:
			continue
		if absi(c.x - monster_pos.x) + absi(c.y - monster_pos.y) < 2:
			continue
		return c
	return HUMAN_HOME


func _random_free_neighbor(cell: Vector2i) -> Vector2i:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	dirs.shuffle()
	for d in dirs:
		var nb: Vector2i = cell + d
		if _in_bounds(nb) and not _is_mountain(nb) and nb != HUMAN_HOME:
			return nb
	return cell


func _monster_turn() -> void:
	# 脚本对手：基础每回合 1 步；爆发力 = 3 步 / 停一回合；强健体魄受伤后下一回合 3 步。
	# 会放幌子：每三次爆发有一次整轮朝着远处走，让足迹拐弯、掉头，不能顺着往回推。
	# 没有任何「一步一声」的反馈 —— 步数只能靠事后探查到的足迹反推。
	var steps := 1
	if stun_turns > 0:
		# 被闪光弹晃住：这一回合它不动，而且不算「爆发力之后的那次休息」
		stun_turns -= 1
		steps = 0
	elif monster_skill == GameConfig.MonsterSkill.BURST:
		steps = 3 if monster_phase == 0 else 0
		monster_phase = 1 - monster_phase
	elif monster_skill == GameConfig.MonsterSkill.PREDATOR:
		steps = _predator_steps()
	elif wounded:
		wounded = false
		steps = 3

	var dist := absi(monster_pos.x - HUMAN_HOME.x) + absi(monster_pos.y - HUMAN_HOME.y)
	var use_decoy := false
	if steps > 0:
		burst_index += 1
		if ai_decoy_bursts > 0:
			use_decoy = true
			ai_decoy_bursts -= 1
		elif dist > 5 and burst_index % 3 == 0 and randf() < 0.75:
			# 还远的时候才放幌子；进到最后 5 格就一心扑门
			ai_decoy = _pick_decoy_cell()
			ai_decoy_bursts = 1
			use_decoy = true
		elif dist > 7 and randf() < 0.18:
			ai_decoy = _pick_decoy_cell()
			use_decoy = true

	var target: Vector2i = HUMAN_HOME
	if use_decoy:
		target = ai_decoy

	for i in range(steps):
		# 弹跳力：偶尔跃一格抄近路（跳过的那格不留痕迹）
		if leap_left > 0 and randf() < 0.45:
			var dc := _leap_dir_toward(monster_pos, target)
			if dc != Vector2i.ZERO:
				var landing := monster_pos + dc * 2
				monster_pos = landing
				leap_left -= 1
				visited[landing] = true
				step_taken += 1
				path.append(landing)
				await get_tree().create_timer(0.13).timeout
				if monster_pos == HUMAN_HOME:
					break
				continue
		var nxt := _bfs_next(monster_pos, target)
		if nxt == monster_pos:
			nxt = _random_free_neighbor(monster_pos)
		if nxt == monster_pos:
			break
		if obstacle_set.has(nxt):
			# 它不绕墙，直接把墙撞开 —— 声音会传到你这边
			_smash_obstacle(nxt)
			_wall_crash(nxt)
			await get_tree().create_timer(0.20).timeout
		monster_pos = nxt
		visited[monster_pos] = true
		step_taken += 1
		path.append(monster_pos)
		await get_tree().create_timer(0.13).timeout
		if monster_pos == HUMAN_HOME:
			break

	await _tick_hazards()
	if ended:
		return

	round_no += 1
	_refresh_traces()
	_refresh_hud()

	if monster_pos == HUMAN_HOME:
		_finish(Texts.s("lose_arrive_title"), Texts.s("lose_arrive_sub"), Color(0.80, 0.22, 0.22), "ARRIVE")
		return
	if round_no > MAX_ROUNDS:
		_finish(Texts.s("win_timeout_title"), Texts.s("win_timeout_sub"), Color(0.75, 0.72, 0.60), "TIMEOUT")
		return

	player_turn = true
	scanning = false
	actions_left = _survivor_cap()
	_refresh_hud()
	if actions_left > 1:
		_say(Texts.s("turn_multi") % actions_left)
	else:
		_say(Texts.s("turn_you"))
	_survivor_notice()


func _bfs_next(from: Vector2i, target: Vector2i) -> Vector2i:
	if from == target:
		return from
	var queue: Array[Vector2i] = [from]
	var prev := {from: from}
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		for d in dirs:
			var nb: Vector2i = cur + d
			if not _in_bounds(nb) or _is_blocked(nb) or prev.has(nb):
				continue
			prev[nb] = cur
			if nb == target:
				var node: Vector2i = nb
				while prev[node] != from:
					if prev[node] == node:
						return from
					node = prev[node]
				return node
			queue.append(nb)
	return from


func _flicker_lamp() -> void:
	if lamp == null:
		return
	var base := LAMP_BASE_ENERGY
	# 抖两下：压暗 → 反弹 → 更暗 → 回到正常。老灯泡那种接不稳的闪
	var tw := create_tween()
	tw.tween_property(lamp, "light_energy", base * 0.30, 0.055)
	tw.tween_property(lamp, "light_energy", base * 0.95, 0.070)
	tw.tween_property(lamp, "light_energy", base * 0.16, 0.050)
	tw.tween_property(lamp, "light_energy", base, 0.240)
	if bulb_mat != null:
		var tw2 := create_tween()
		tw2.tween_property(bulb_mat, "emission_energy_multiplier", 0.7, 0.06)
		tw2.tween_property(bulb_mat, "emission_energy_multiplier", 3.2, 0.22)


func _kill_lamp() -> void:
	# 输了：灯抽搐两下，然后灭。灭掉之后整个屋子只剩屏幕前的你。
	if lamp == null:
		return
	next_lamp_flicker_at = 1.0e9
	var tw := create_tween()
	tw.tween_property(lamp, "light_energy", LAMP_BASE_ENERGY * 0.55, 0.08)
	tw.tween_property(lamp, "light_energy", LAMP_BASE_ENERGY * 0.08, 0.10)
	tw.tween_property(lamp, "light_energy", LAMP_BASE_ENERGY * 0.45, 0.09)
	tw.tween_property(lamp, "light_energy", 0.0, 0.60)
	if bulb_mat != null:
		var tw2 := create_tween()
		tw2.tween_property(bulb_mat, "emission_energy_multiplier", 1.4, 0.10)
		tw2.tween_property(bulb_mat, "emission_energy_multiplier", 0.0, 0.70)
	if world_env != null:
		var tw3 := create_tween()
		tw3.tween_property(world_env, "ambient_light_energy", 0.05, 0.95)


# ---------------------------------------------------------------- 足迹

func _add_trace(cell: Vector2i) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.155, 0.155)
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.09, 0.08, 0.65)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mi.material_override = mat
	mi.position = _cell_pos(cell) + Vector3(0.0, 0.020, 0.0)
	mi.rotation_degrees = Vector3(-90.0, randf_range(-25.0, 25.0), 0.0)
	board_root.add_child(mi)

	var mi2 := MeshInstance3D.new()
	var quad2 := QuadMesh.new()
	quad2.size = Vector2(0.10, 0.10)
	mi2.mesh = quad2
	mi2.material_override = mat
	mi2.position = _cell_pos(cell) + Vector3(randf_range(-0.05, 0.05), 0.021, randf_range(-0.05, 0.05))
	mi2.rotation_degrees = Vector3(-90.0, randf_range(-40.0, 40.0), 0.0)
	board_root.add_child(mi2)

	traces.append({"cell": cell, "round": round_no, "nodes": [mi, mi2], "mat": mat})
	_refresh_traces()


func _refresh_traces() -> void:
	for t in traces:
		var age: int = round_no - int(t["round"])
		var alpha := 1.0 - float(age) / float(TRACE_LIFE)
		alpha = clampf(alpha, 0.0, 1.0)
		alpha = pow(alpha, 1.35)
		var mat: StandardMaterial3D = t["mat"]
		var col := Color(0.34, 0.09, 0.08)
		mat.albedo_color = Color(col.r, col.g, col.b, alpha * 0.72)
		var nodes: Array = t["nodes"]
		for n in nodes:
			(n as MeshInstance3D).visible = alpha > 0.02


func _spawn_scan_ring(cell: Vector2i) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.10
	torus.outer_radius = 0.135
	torus.rings = 24
	torus.ring_segments = 8
	mi.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.80, 0.86, 0.92)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = _cell_pos(cell) + Vector3(0.0, 0.030, 0.0)
	mi.scale = Vector3(0.2, 1.0, 0.2)
	board_root.add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(1.0, 1.0, 1.0), SCAN_TIME).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, SCAN_TIME)
	tw.tween_callback(func(): mi.queue_free())


func _spawn_result_mark(cell: Vector2i, result: int) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.26)
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	match result:
		0:
			mat.albedo_color = Color(0.35, 0.36, 0.34, 0.5)
		1:
			mat.albedo_color = Color(0.95, 0.62, 0.20, 0.7)
		2:
			mat.albedo_color = Color(0.95, 0.15, 0.12, 0.9)
	mi.material_override = mat
	mi.position = _cell_pos(cell) + Vector3(0.0, 0.019, 0.0)
	mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	board_root.add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(1.25, 1.25, 1.25), 0.25)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.9)
	tw.tween_callback(func(): mi.queue_free())


# ---------------------------------------------------------------- 黑暗里的眼睛

func _build_eyes() -> void:
	# 都是桌子外的黑暗处，y 有高有低，看起来像有东西站在那儿看你
	var spots := [
		Vector3(-2.05, 0.36, -2.30),
		Vector3(2.15, 0.31, -2.25),
		Vector3(0.05, 0.29, -2.72),
		Vector3(-1.25, 0.40, -2.45),
		Vector3(1.30, 0.33, -2.40),
		Vector3(-2.60, 0.44, -2.40),
	]
	for p in spots:
		var root := Node3D.new()
		root.position = p
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.26, 0.18, 0.0)
		for sx in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.021
			sp.height = 0.042
			sp.radial_segments = 8
			sp.rings = 4
			mi.mesh = sp
			mi.material_override = mat
			mi.position = Vector3(sx * 0.048, 0.0, 0.0)
			root.add_child(mi)
		root.visible = false
		add_child(root)
		eyes.append({"node": root, "mat": mat, "pos": p})


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _tick_ambient(_dt: float) -> void:
	# 「一些小动静」：和它走没走、走了几步完全无关，才不泄露暗选技能
	var now := _now()
	if now < next_ambient_at:
		return
	next_ambient_at = now + randf_range(5.0, 11.0)
	if audio_step != null and audio_step.stream != null:
		audio_step.pitch_scale = randf_range(0.50, 0.80)
		audio_step.volume_db = -17.0
		audio_step.play()
	if randf() < 0.45:
		_flicker_lamp()


func _tick_eyes(dt: float) -> void:
	var now := _now()
	if eye_active.is_empty():
		if now < next_eye_at:
			return
		next_eye_at = now + randf_range(10.0, 20.0)
		var pick: Dictionary = eyes[randi() % eyes.size()]
		pick["alpha"] = 0.0
		pick["state"] = 1
		pick["hold_until"] = 0.0
		pick["next_blink"] = now + randf_range(1.6, 3.6)
		pick["blink_until"] = 0.0
		pick["node"].visible = true
		eye_active = pick
		return

	var a: float = eye_active["alpha"]
	var st: int = eye_active["state"]
	if st == 1:
		a += dt / 0.7
		var node: Node3D = eye_active["node"]
		node.look_at(camera.global_position, Vector3.UP)
		if a >= 1.0:
			a = 1.0
			st = 2
			eye_active["hold_until"] = now + randf_range(2.4, 5.0)
	elif st == 2:
		var node2: Node3D = eye_active["node"]
		node2.look_at(camera.global_position, Vector3.UP)
		if now > eye_active["hold_until"]:
			st = 3
		if now > eye_active["next_blink"]:
			eye_active["next_blink"] = now + randf_range(1.4, 4.2)
			eye_active["blink_until"] = now + 0.11
		var sy := 1.0
		if now < float(eye_active["blink_until"]):
			sy = 0.06
		node2.scale = Vector3(1.0, sy, 1.0)
	elif st == 3:
		a -= dt / 0.55
		var node3: Node3D = eye_active["node"]
		node3.look_at(camera.global_position, Vector3.UP)
		if a <= 0.0:
			a = 0.0
			node3.visible = false
			var mat0: StandardMaterial3D = eye_active["mat"]
			mat0.albedo_color = Color(1.0, 0.26, 0.18, 0.0)
			eye_active = {}
			return

	eye_active["alpha"] = a
	eye_active["state"] = st
	var mat: StandardMaterial3D = eye_active["mat"]
	mat.albedo_color = Color(1.0, 0.26, 0.18, a)


func _dismiss_eye_under_cursor(at: Vector2) -> bool:
	if eye_active.is_empty() or int(eye_active["state"]) != 2:
		return false
	var mp := at
	var o := camera.project_ray_origin(mp)
	var n := camera.project_ray_normal(mp)
	var target: Vector3 = eye_active["pos"]
	var to := target - o
	var t := to.dot(n)
	if t <= 0.0:
		return false
	var closest := o + n * t
	if closest.distance_to(target) > 0.18:
		return false
	# 被看见了 —— 立刻消失
	var node: Node3D = eye_active["node"]
	node.visible = false
	var mat: StandardMaterial3D = eye_active["mat"]
	mat.albedo_color = Color(1.0, 0.26, 0.18, 0.0)
	eye_active = {}
	_flicker_lamp()
	return true

# ---------------------------------------------------------------- 收尾

func _end_texts(reason: String) -> Array:
	# 按「我坐在哪一边」返回 [标题, 副标题]
	var as_monster := side == 1
	match reason:
		"ARRIVE":
			return [Texts.s("m_arrive_title"), Texts.s("m_arrive_sub")] if as_monster else [Texts.s("lose_arrive_title"), Texts.s("lose_arrive_sub")]
		"PROBE":
			return [Texts.s("m_probe_title"), Texts.s("m_probe_sub")] if as_monster else [Texts.s("win_probe_title"), Texts.s("win_probe_sub")]
		"MINE":
			return [Texts.s("m_mine_title"), Texts.s("m_mine_sub")] if as_monster else [Texts.s("win_mine_title"), Texts.s("win_mine_sub")]
		"FIRE":
			return [Texts.s("m_fire_title"), Texts.s("m_fire_sub")] if as_monster else [Texts.s("win_fire_title"), Texts.s("win_fire_sub")]
		"NADE":
			return [Texts.s("m_nade_title"), Texts.s("m_nade_sub")] if as_monster else [Texts.s("win_nade_title"), Texts.s("win_nade_sub")]
		"TIMEOUT":
			return [Texts.s("m_timeout_title"), Texts.s("m_timeout_sub")] if as_monster else [Texts.s("win_timeout_title"), Texts.s("win_timeout_sub")]
	return ["", ""]


func _finish(title: String, sub: String, color: Color, reason: String = "") -> void:
	ended = true
	scanning = false
	player_turn = false
	setup_phase = false
	_say_pending = ""
	end_reason = reason
	end_title = title
	end_sub = sub
	hud_end.visible = true
	hud_end.text = title
	hud_end.add_theme_color_override("font_color", color)
	hud_result.position = Vector2(500, RESULT_Y_END)
	hud_result.size = Vector2(600, 92)
	hud_result.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_say(sub + "\n" + Texts.s("press_r"), PINK_SOFT, true)
	hud_result.modulate.a = 1.0
	if GameConfig.is_host():
		_broadcast()
	if not human_win:
		_kill_lamp()
	elif overlay_mat != null:
		var tw := create_tween()
		tw.tween_method(func(v): overlay_mat.set_shader_parameter("tint", v), 0.0, 0.55, 0.6)
	_refresh_hud()
	if human_win:
		_play(audio_hit)
		_reveal_path()
	elif side == 0:
		# 输了：灯灭了，但它这一路踩过的格子会一点点亮起来 —— 让你看清它怎么进来的
		_reveal_trails()


func _reveal_trails() -> void:
	# 输了之后把它的全局足迹点亮：每个走过的格子一片发光脚印，逐个亮起
	if trail_nodes.size() > 0:
		return
	var cells: Array = visited.keys()
	if cells.is_empty():
		return
	var seen := {}
	var order: Array = []
	for c in path:
		if not seen.has(c):
			seen[c] = true
			order.append(c)
	for c in cells:
		if not seen.has(c):
			seen[c] = true
			order.append(c)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.105, 0.078)
	for i in order.size():
		var c: Vector2i = order[i]
		# 一格两片（左右脚），比一个大方块更像「踩过」
		for lobe in [-1.0, 1.0]:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(1.0, 0.30, 0.42, 0.0)
			mat.no_depth_test = true
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			var off := Vector3(lobe * 0.048, 0.036 + (0.002 if lobe > 0.0 else 0.0), 0.030 * lobe)
			mi.position = _cell_pos(c) + off
			mi.rotation_degrees = Vector3(0.0, randf_range(-22.0, 22.0), 0.0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			trail_nodes.append(mi)
			_reveal_trail_glow(mat, 0.35 + i * 0.10)


func _refresh_hud() -> void:
	if GameConfig.is_host() and not _applying_snapshot:
		_broadcast()
	_update_round_hud()
	hud_probes.text = "已探查 %d 次  ·  剩 %d 次机会" % [probes_used, MAX_ROUNDS - probes_used]
	if setup_phase:
		if remote_deploy:
			# 我是异形，正在等对面人类布防 —— 这不是我的活
			hud_probes.text = "他正在布防 — 你看不见他放了什么"
			hud_hint.text = "等他布完，你走开局的 4 步  ·  E 俯视  ·  F1 换席"
			return
		if human_skill == GameConfig.HumanSkill.BUILDER:
			hud_probes.text = "部署：还剩 %d 组墙（左键放置 · R 旋转 · 空格开始）" % (_setup_total() - setup_placed)
			hud_hint.text = "墙挡不住它 —— 它穿得过去，但墙会塌，声音你听得见。别放基地附近两格内。"
		else:
			hud_probes.text = "部署：还剩 %d 颗雷（左键放置 · 空格开始）" % (MINE_COUNT - setup_placed)
			hud_hint.text = "每颗雷盖九格，引爆要花掉人类一回合的行动。"
		return
	if side == 1:
		var hp_txt := _hp_text()
		var leap_txt := ""
		if monster_skill == GameConfig.MonsterSkill.LEAP:
			leap_txt = "  ·  弹跳力 %d 次（Shift+WASD）" % leap_left
		if monster_opening:
			if monster_steps > 0:
				hud_probes.text = "开局 — 你还有 %d 步（不计回合）  ·  他还没动%s" % [monster_steps, leap_txt]
				hud_hint.text = "WASD 走一格  ·  走完按空格 —— 第一次轮到他  ·  E 俯视  ·  F1 换席"
			else:
				hud_probes.text = "开局这 4 步走完了 — 他还没动%s" % leap_txt
				hud_hint.text = "按空格，第一次轮到他  ·  E 俯视  ·  F1 换席"
		elif stun_turns > 0:
			hud_probes.text = "眼前还在白 —— 这一回合你动不了  ·  你 %s 血" % hp_txt
			hud_hint.text = "空格交给他  ·  E 俯视  ·  F1 换席"
		elif monster_steps > 0:
			hud_probes.text = "本回合还能走 %d 步  ·  他查了 %d 次（还剩 %d 次）  ·  你 %s 血%s" % [monster_steps, probes_used, MAX_ROUNDS - probes_used, hp_txt, leap_txt]
			hud_hint.text = "WASD 走一格  ·  空格结束回合  ·  E 俯视  ·  F1 换席"
		else:
			hud_probes.text = "这一回合你动不了 —— %s  ·  他查了 %d 次  ·  你 %s 血" % [_no_steps_reason(), probes_used, hp_txt]
			hud_hint.text = "空格交给他  ·  E 俯视  ·  F1 换席"
		return
	if armed_throw != "":
		var names := {"flash": "闪光弹", "nade": "手雷", "fire": "燃烧弹"}
		hud_hint.text = "%s握在手上 —— 点一格扔出去  ·  Esc 放下" % names[armed_throw]
	elif human_skill == GameConfig.HumanSkill.THROWER:
		hud_hint.text = "左键探查一格（0.5 秒）  ·  1 闪光弹 %d  2 手雷 %d  3 燃烧弹 %d  ·  E 俯视" % [int(throw_left["flash"]), int(throw_left["nade"]), int(throw_left["fire"])]
	elif opening or Time.get_ticks_msec() < open_hint_hold:
		hud_hint.text = "它先走了 4 步 —— 不计回合，你也看不见。"
	elif top_down:
		hud_hint.text = "左键探查一格（0.5 秒出结果）  ·  E 回正视角  ·  按住右键转头"
	else:
		hud_hint.text = "左键探查一格（0.5 秒出结果）  ·  E 俯视  ·  按住右键转头"
	if human_skill == GameConfig.HumanSkill.SURVIVOR:
		if actions_left > 1:
			hud_hint.text = "本回合还能查 %d 次  ·  %s" % [actions_left, hud_hint.text]
		else:
			var need := 7 if round_no < 7 else 15
			var cap := 2 if need == 7 else 3
			hud_hint.text = "求生者：第 %d 回合起能连查 %d 格  ·  %s" % [need, cap, hud_hint.text]
	elif actions_left > 1:
		hud_hint.text = "本回合还能查 %d 次  ·  %s" % [actions_left, hud_hint.text]
	if GameConfig.is_host():
		_broadcast()


func _play(p: AudioStreamPlayer) -> void:
	if p != null and p.stream != null:
		p.play()

# ---------------------------------------------------------------- 异形席（坐在对面）

func _switch_side() -> void:
	# F1：换座位。不重开局面，只换你坐在哪一边。
	if ended:
		return
	side = 1 - side
	scanning = false
	player_turn = true
	look_target_yaw = 0.0
	if side == 1:
		monster_steps = _next_monster_budget()
		_rebuild_perm_footprints()
		_update_self_marker()
		_apply_seat_visuals()
		if monster_steps > 0:
			_notify(Texts.s("seat_human_here"))
		else:
			_notify("你现在坐在它对面。这一回合你动不了 —— %s。" % _no_steps_reason())
	else:
		monster_steps = 0
		_update_self_marker()
		_notify("回到这一边。现在轮到你了。")
	_apply_view_filter()
	_refresh_hud()


func _apply_view_filter() -> void:
	# 异形席：整屏压成绿磷光夜视，一眼就知道「你不在人类那边了」
	if overlay_mat == null:
		return
	if side == 1:
		overlay_mat.set_shader_parameter("night_vision", 1.0)
		overlay_mat.set_shader_parameter("blood", 0.0)
		overlay_mat.set_shader_parameter("vignette_strength", 0.55)
		overlay_mat.set_shader_parameter("grain_strength", 0.02)
	else:
		overlay_mat.set_shader_parameter("night_vision", 0.0)
		overlay_mat.set_shader_parameter("blood", 0.0)
		overlay_mat.set_shader_parameter("vignette_strength", 0.86)
		overlay_mat.set_shader_parameter("grain_strength", 0.05)


func _notify(txt: String) -> void:
	if side == 1:
		# 异形席上，他查过哪里要一直摆在眼前（夜视里也用暗粉，别太刺）
		_say(txt, Color(0.72, 0.50, 0.58))
		hud_result.modulate.a = 0.90
		return
	_say(txt, PINK_SOFT)
	if result_tween != null and result_tween.is_valid():
		result_tween.kill()
	result_tween = create_tween()
	result_tween.tween_interval(3.4)
	result_tween.tween_property(hud_result, "modulate:a", 0.0, 1.2)


func _monster_move_at(mp: Vector2) -> void:
	if side == 0 or ended or scanning or not player_turn:
		return
	var cell := _cell_at(mp)
	if cell.x < 0 or _is_mountain(cell):
		return
	if monster_steps <= 0:
		_notify("这一回合你动不了 —— %s。" % _no_steps_reason())
		return
	# 弹跳力：点在正前方两格上 = 跃过去（中间那格不留脚印）
	if leap_left > 0:
		var d := cell - monster_pos
		if absi(d.x) + absi(d.y) == 2 and (d.x == 0 or d.y == 0):
			_leap_to(cell)
			return
	_walk_to(cell)


func _step_screen(idx: int, leaping: bool = false) -> void:
	# 异形席：WASD 按「屏幕方向」走一格（换到对面后 W 依然是往上）
	# 按住 Shift = 用弹跳力跃过一格（整局两次）
	if side == 0 or ended or scanning or not player_turn:
		return
	if monster_steps <= 0:
		_notify("这一回合你动不了 —— %s。" % _no_steps_reason())
		return
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var dir := Vector3.ZERO
	match idx:
		0:
			dir = fwd
		1:
			dir = -right
		2:
			dir = -fwd
		3:
			dir = right
	var dc := Vector2i(int(round(dir.x)), int(round(dir.z)))
	if dc == Vector2i.ZERO:
		return
	if leaping:
		_try_leap(dc)
		return
	var nxt := monster_pos + dc
	if not _in_bounds(nxt) or _is_mountain(nxt):
		return
	scanning = true
	await _take_step(nxt)
	scanning = false
	_update_self_marker()
	_refresh_traces()
	if ended:
		return
	if monster_steps <= 0:
		_notify("这几步走完了 —— 空格结束回合。")


func _try_leap(dc: Vector2i) -> void:
	# 弹跳力：跃过相邻一格，落到再下一格；被跳过的那格不留脚印
	if leap_left <= 0:
		_notify("弹跳力用完了。")
		return
	var landing := monster_pos + dc * 2
	if not _in_bounds(landing) or _is_mountain(landing):
		_notify("那边落不下去。")
		return
	if GameConfig.is_guest():
		_net_send({"t": "cmd", "a": "leap", "c": [landing.x, landing.y]})
		return
	await _leap_to(landing)


func _leap_to(landing: Vector2i) -> void:
	# 跃过去：中间那格既不进 visited，也不画脚印 —— 它的路上会缺一格
	if GameConfig.is_guest():
		_net_send({"t": "cmd", "a": "leap", "c": [landing.x, landing.y]})
		return
	leap_left -= 1
	monster_steps -= 1
	step_taken += 1
	var mid := (monster_pos + landing) / 2
	if obstacle_set.has(landing):
		# 落点上有墙：照塌，声音照样传出去
		_smash_obstacle(landing)
		_wall_crash(landing)
		await get_tree().create_timer(0.20).timeout
	monster_pos = landing
	visited[landing] = true
	path.append(landing)
	# 脚印：房主那边要记（要转发给客机异形），画不画看座位
	_add_perm_footprint(landing)
	_update_self_marker()
	_play(audio_step)
	if side == 1:
		# 只有坐异形席的人才知道自己跃过了哪一格 —— 人类那边看到这句就等于拿到了它的坐标
		_notify("你跃过了 (%d, %d)。" % [mid.x, mid.y])
	_refresh_hud()
	await get_tree().create_timer(0.18).timeout
	if landing == HUMAN_HOME:
		await get_tree().create_timer(0.30).timeout
		_play(audio_hit)
		var pair := _end_texts("ARRIVE")
		_finish(pair[0], pair[1], Color(0.85, 0.35, 0.30), "ARRIVE")


func _take_step(cell: Vector2i) -> void:
	if GameConfig.is_guest():
		_net_send({"t": "cmd", "a": "move", "c": [cell.x, cell.y]})
		return
	if obstacle_set.has(cell):
		# 穿墙：挡不住它，但墙会塌、动静很大 —— 你听得见，只是不知道在哪。
		_smash_obstacle(cell)
		_wall_crash(cell)
		await get_tree().create_timer(0.26).timeout
	monster_pos = cell
	visited[cell] = true
	step_taken += 1
	monster_steps -= 1
	path.append(cell)
	# 脚印：房主那边要记（要转发给客机异形），画不画看座位
	_add_perm_footprint(cell)
	_update_self_marker()
	_refresh_hud()
	await get_tree().create_timer(0.12).timeout
	if cell == HUMAN_HOME:
		await get_tree().create_timer(0.30).timeout
		_play(audio_hit)
		var pair := _end_texts("ARRIVE")
		_finish(pair[0], pair[1], Color(0.85, 0.35, 0.30), "ARRIVE")


func _walk_to(target: Vector2i) -> void:
	# 客机异形：本地没有权威位置，自己走会死循环 —— 整条路交给房主演
	if GameConfig.is_guest():
		_net_send({"t": "cmd", "a": "walk", "c": [target.x, target.y]})
		return
	scanning = true
	var guard := 0
	while monster_steps > 0 and monster_pos != target and not ended and guard < 24:
		guard += 1
		var before := monster_pos
		if obstacle_set.has(target) and _cheb(monster_pos, target) == 1:
			await _take_step(target)
			break
		var nxt := _bfs_next(monster_pos, target)
		if nxt == monster_pos or _is_mountain(nxt):
			break
		await _take_step(nxt)
		await get_tree().create_timer(0.10).timeout
		if monster_pos == before:
			break
	scanning = false
	_update_self_marker()
	_refresh_traces()
	if ended:
		return
	if monster_steps <= 0:
		_notify("这几步走完了 —— 空格结束回合。")


func _end_monster_turn() -> void:
	if side == 0 or ended or not player_turn or scanning:
		return
	if GameConfig.is_guest():
		_net_send({"t": "cmd", "a": "end"})
		player_turn = false
		return
	player_turn = false
	monster_steps = 0
	if GameConfig.is_online():
		if monster_opening:
			# 联机：开局那 4 步走完 —— 不计回合计，直接把台子交给人类
			monster_opening = false
			turn_side = 0
			player_turn = false
			_notify("走完了。轮到他。")
			_refresh_hud()
			_net_send({"t": "turn", "who": 0})
			_broadcast()
			return
		# 联机：对面是人类玩家，把台子交回去，不跑脚本
		# 交台之前先把这回合的火/雷结算掉 —— 房主是权威，这一步不做，联机的燃烧弹永远烧不到人
		await _tick_hazards()
		if ended:
			return
		round_no += 1
		turn_side = 0
		monster_steps = 0
		actions_left = _survivor_cap()
		_refresh_hud()
		_survivor_notice()
		if round_no > MAX_ROUNDS:
			_finish(Texts.s("m_timeout_title"), Texts.s("m_timeout_sub"), Color(0.75, 0.72, 0.60), "TIMEOUT")
		_net_send({"t": "turn", "who": 0})
		_broadcast()
		return
	await _scripted_human_probe()
	if ended:
		return
	round_no += 1
	if monster_opening:
		# 开局这 4 步走完：第 1 回合正式开始，之后按技能给步数
		monster_opening = false
		monster_steps = _next_monster_budget()
		player_turn = true
		_refresh_hud()
		_notify("开局走完了。轮到你 —— 这回合 %d 步。" % monster_steps)
		return
	await _tick_hazards()
	if ended:
		return
	# 闪光弹的后劲：这一回合它不动，而且不算「爆发力之后的那次休息」
	if stun_turns > 0:
		stun_turns -= 1
		monster_steps = 0
		_notify("眼前还在白 —— 这一回合你动不了。")
		player_turn = true
		_refresh_hud()
		return
	# 回合结算：统一走 _next_monster_budget()，别在这里另写一套
	# （以前这里漏了「捕食本能」，手操异形每回合都被压回 1 步）
	monster_steps = _next_monster_budget()
	player_turn = true
	_refresh_hud()
	if side == 0:
		_say(Texts.s("turn_you"))
	else:
		_notify("他查完了。轮到你走 %d 步。" % monster_steps)
	if round_no > MAX_ROUNDS:
		_finish(Texts.s("m_timeout_title"), Texts.s("m_timeout_sub"), Color(0.75, 0.72, 0.60), "TIMEOUT")


func _scripted_human_probe() -> void:
	# 脚本人类：会顺着脚印往你家推一格 —— 不是纯碰运气
	# 先看雷：只要你在某颗雷的格心旁边，他会直接引爆（那是一发必中）
	for m in mine_list:
		if _cheb(m, monster_pos) <= 1:
			await _detonate_ai(m)
			return
	var pick := Vector2i(-1, -1)
	# 一、见过脚印，就沿着「它正朝我这边走」的方向推一格
	for i in range(human_marks.size() - 1, -1, -1):
		var m: Dictionary = human_marks[i]
		if int(m["result"]) == 1:
			var g := _guess_next(m["cell"])
			if _probe_ok(g) and not _already_probed(g):
				pick = g
				break
	# 二、没线索：翻最新的一片脚印（六成），或者到处摸（四成）
	if pick.x < 0 and randf() < 0.62:
		var keys := visited.keys()
		for i in range(keys.size() - 1, -1, -1):
			var c: Vector2i = keys[i]
			if c != monster_pos and not _already_probed(c):
				pick = c
				break
	if pick.x < 0:
		for i in range(60):
			var c := Vector2i(randi_range(0, SIZE - 1), randi_range(0, SIZE - 1))
			if not _probe_ok(c) or _already_probed(c):
				continue
			pick = c
			break
	if pick.x < 0:
		return

	_play(audio_probe)
	_spawn_scan_ring(pick)
	await get_tree().create_timer(SCAN_TIME).timeout

	var res := 0
	if pick == monster_pos:
		res = 2
	elif visited.has(pick):
		res = 1
	probes_used += 1
	_spawn_result_mark(pick, res)
	_mark_human_probe(pick, res)
	human_marks.append({"cell": pick, "result": res, "round": round_no})

	match res:
		0:
			_notify("第 %d 回合 · 他查了 (%d, %d) —— 什么也没有。" % [round_no, pick.x, pick.y])
		1:
			_notify("第 %d 回合 · 他查了 (%d, %d) —— 有脚印。他知道你走过这里。" % [round_no, pick.x, pick.y])
		2:
			_notify("第 %d 回合 · 他查了 (%d, %d) —— 查中你了。" % [round_no, pick.x, pick.y])
	_refresh_hud()

	if res == 2:
		await get_tree().create_timer(0.6).timeout
		_play(audio_hit)
		_finish(Texts.s("m_probe_title"), Texts.s("m_probe_sub"), Color(0.85, 0.35, 0.30), "PROBE")


func _detonate_ai(c: Vector2i) -> void:
	# 脚本人类引爆：命中就吃一发，不中这颗雷就废了
	mine_list.erase(c)
	for ch in gear_root.get_children():
		if ch is MeshInstance3D and ch.position.distance_to(_cell_pos(c) + Vector3(0.0, 0.018, 0.0)) < 0.05:
			ch.queue_free()
	_play(audio_hit)
	await get_tree().create_timer(0.5).timeout
	_notify("第 %d 回合 · 他引爆了 (%d, %d) 的雷。" % [round_no, c.x, c.y])
	_walk_damage_ai()


func _walk_damage_ai() -> void:
	if _damage_monster():
		_finish(Texts.s("m_mine_title"), Texts.s("m_mine_sub"), Color(0.85, 0.35, 0.30), "MINE")



func _mark_human_probe(cell: Vector2i, res: int) -> void:
	# 异形席上，他查过的每一格都永久留下来 —— 这是情报上的不对称
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.20, 0.20)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var col := Color(0.42, 0.43, 0.41, 0.45)
	if res == 1:
		col = Color(0.78, 0.52, 0.22, 0.55)
	elif res == 2:
		col = Color(0.88, 0.18, 0.16, 0.75)
	mat.albedo_color = col
	mi.material_override = mat
	mi.position = _cell_pos(cell) + Vector3(0.0, 0.026, 0.0)
	mi.rotation_degrees = Vector3(-90.0, 45.0, 0.0)
	board_root.add_child(mi)

func _add_perm_footprint(cell: Vector2i) -> void:
	# 异形席：自己走过的脚印永久留着，不随回合消退
	# 联机时房主是人类也要记（记下来才能转发给客机异形），只是自己不画
	if perm_fp_cells.has(cell):
		return
	perm_fp_cells[cell] = true
	if side != 1:
		return
	if perm_fp_root == null:
		perm_fp_root = Node3D.new()
		board_root.add_child(perm_fp_root)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.13, 0.13)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.16, 0.13, 0.55)
	mi.material_override = mat
	mi.position = _cell_pos(cell) + Vector3(randf_range(-0.03, 0.03), 0.023, randf_range(-0.03, 0.03))
	mi.rotation_degrees = Vector3(-90.0, randf_range(-30.0, 30.0), 0.0)
	perm_fp_root.add_child(mi)


func _rebuild_perm_footprints() -> void:
	# 切到异形席时补脚印：出生点、开局那 4 步、AI 替你走过的路，全都要留下
	if perm_fp_root == null:
		perm_fp_root = Node3D.new()
		board_root.add_child(perm_fp_root)
	for child in perm_fp_root.get_children():
		perm_fp_root.remove_child(child)
		child.queue_free()
	perm_fp_cells.clear()
	for c in visited.keys():
		_add_perm_footprint(c)
	_add_perm_footprint(MONSTER_SPAWN)
	_add_perm_footprint(monster_pos)


func _probe_ok(c: Vector2i) -> bool:
	return _in_bounds(c) and not _is_mountain(c) and c != HUMAN_HOME


func _already_probed(c: Vector2i) -> bool:
	for m in human_marks:
		if m["cell"] == c:
			return true
	return false


func _guess_next(c: Vector2i) -> Vector2i:
	# 它要去 (0,0)，所以从脚印往前推一格：先走差得多的那根轴
	var dx := HUMAN_HOME.x - c.x
	var dy := HUMAN_HOME.y - c.y
	if dx != 0 and absi(dx) >= absi(dy):
		return c + Vector2i(signi(dx), 0)
	if dy != 0:
		return c + Vector2i(0, signi(dy))
	return c

func _update_self_marker() -> void:
	if self_marker == null:
		self_marker = MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.042
		sp.height = 0.084
		sp.radial_segments = 12
		sp.rings = 6
		self_marker.mesh = sp
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.62, 0.10, 0.10, 0.85)
		self_marker.material_override = mat
		board_root.add_child(self_marker)
	self_marker.visible = side == 1 and not ended
	self_marker.position = _cell_pos(monster_pos) + Vector3(0.0, 0.045, 0.0)


# ---------------------------------------------------------------- 工事：障碍与地雷

func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _is_blocked(c: Vector2i) -> bool:
	# 墙不再是「墙」：它穿得过去，只是会把墙撞塌、弄出很大动静。
	return _is_mountain(c)


func _build_gear_root() -> void:
	gear_root = Node3D.new()
	gear_root.name = "Gear"
	board_root.add_child(gear_root)


# ---------------------------------------------------------------- 部署虚影

func _build_ghost() -> void:
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = Color(0.80, 0.84, 0.52, 0.26)
	ghost_mat.roughness = 0.75
	ghost_mat.emission_enabled = true
	ghost_mat.emission = Color(0.42, 0.46, 0.22)
	ghost_mat.emission_energy_multiplier = 0.55

	ghost_root = Node3D.new()
	ghost_root.name = "Ghost"
	ghost_root.visible = false
	board_root.add_child(ghost_root)

	ghost_wall = Node3D.new()
	ghost_root.add_child(ghost_wall)
	for i in range(2):
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.235, 0.13, 0.235)
		mi.mesh = box
		mi.material_override = ghost_mat
		mi.position = Vector3(0.0, 0.065, 0.0)
		ghost_wall.add_child(mi)

	ghost_mine = Node3D.new()
	ghost_root.add_child(ghost_mine)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var mi := MeshInstance3D.new()
			var q := PlaneMesh.new()
			q.size = Vector2(0.24, 0.24)
			mi.mesh = q
			mi.material_override = ghost_mat
			mi.position = Vector3(float(dx) * CELL, 0.034, float(dy) * CELL)
			ghost_mine.add_child(mi)


func _update_ghost() -> void:
	if ghost_root == null:
		return
	# 部署虚影只画给人类自己；异形席等他布防时什么都不该出现
	var deploy_ui := setup_phase and side == 0
	if not deploy_ui and armed_throw == "":
		ghost_root.visible = false
		return
	var cell := _cell_at(get_viewport().get_mouse_position())
	if cell.x < 0:
		ghost_root.visible = false
		return
	# 拿着弹：九格虚影，颜色按弹种区分，扔不进去的地方标红
	if not deploy_ui and armed_throw != "":
		ghost_wall.visible = false
		ghost_mine.visible = true
		ghost_root.visible = true
		ghost_root.position = _cell_pos(cell)
		var ok_t := _throw_cell_ok(cell)
		var idx := 0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var c2 := cell + Vector2i(dx, dy)
				var inside := _in_bounds(c2)
				ghost_mine.get_child(idx).visible = inside and not _is_mountain(c2)
				idx += 1
		var tint := Color(0.88, 0.90, 0.96, 0.26)
		match armed_throw:
			"nade":
				tint = Color(0.96, 0.66, 0.28, 0.28)
			"fire":
				tint = Color(0.96, 0.44, 0.18, 0.28)
		ghost_mat.albedo_color = tint if ok_t else Color(0.86, 0.28, 0.22, 0.32)
		return
	var builder := human_skill == GameConfig.HumanSkill.BUILDER
	ghost_wall.visible = builder
	ghost_mine.visible = not builder
	ghost_root.visible = true
	ghost_root.position = _cell_pos(cell)
	for mi in ghost_mine.get_children():
		mi.visible = true

	var ok := true
	if builder:
		# 第二格从光标往下/往右延伸；按 R 换方向
		var second := cell + (Vector2i(0, 1) if setup_vertical else Vector2i(1, 0))
		ok = _setup_cell_ok(cell) and _setup_cell_ok(second)
		var a: Node3D = ghost_wall.get_child(0)
		var b: Node3D = ghost_wall.get_child(1)
		a.position = Vector3(0.0, 0.065, 0.0)
		b.position = Vector3(0.0, 0.065, CELL) if setup_vertical else Vector3(CELL, 0.065, 0.0)
	else:
		ok = _setup_cell_ok(cell) and not _mine_covers_home(cell) and not mine_list.has(cell)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var c2 := cell + Vector2i(dx, dy)
				if not _in_bounds(c2) or _is_mountain(c2):
					ok = false
	ghost_mat.albedo_color = Color(0.80, 0.84, 0.52, 0.26) if ok else Color(0.86, 0.28, 0.22, 0.30)


func _enter_setup() -> void:
	setup_phase = true
	setup_placed = 0
	player_turn = false
	open_hint_hold = Time.get_ticks_msec() + 999999
	_say(Texts.s("setup_ask"))
	hud_result.add_theme_color_override("font_color", PINK_SOFT)
	hud_result.modulate.a = 1.0
	_refresh_hud()


func _setup_click(mp: Vector2) -> void:
	var cell := _cell_at(mp)
	if cell.x < 0 or ended:
		return
	if GameConfig.is_guest():
		_net_send({"t": "cmd", "a": "place", "c": [cell.x, cell.y], "v": setup_vertical})
		# 本地也数着：不然客机的部署界面永远走不完
		if human_skill == GameConfig.HumanSkill.BUILDER:
			setup_vertical = not setup_vertical
		setup_placed += 1
		if setup_placed >= _setup_total():
			setup_phase = false
			_say(Texts.s("setup_done_wait"))
			hud_result.modulate.a = 1.0
		_refresh_hud()
		return
	_setup_place_cell(cell)


func _setup_place_cell(cell: Vector2i) -> void:
	if cell.x < 0 or ended:
		return
	if human_skill == GameConfig.HumanSkill.BUILDER:
		var second := cell + Vector2i(0, 1) if setup_vertical else cell + Vector2i(1, 0)
		if not _setup_cell_ok(cell) or not _setup_cell_ok(second):
			_notify("这里放不下 —— 不能压山、不能贴基地两格内、不能落在一起。")
			return
		var group := [cell, second]
		obstacles.append(group)
		for c in group:
			obstacle_set[c] = true
			_spawn_wall(c)
		setup_vertical = not setup_vertical
	else:
		if not _setup_cell_ok(cell) or _mine_covers_home(cell) or mine_list.has(cell):
			_notify("这里放不下 —— 九格里不能有基地，也不能和别的雷重叠。")
			return
		mine_list.append(cell)
		_spawn_mine(cell)
	setup_placed += 1
	_fx_sound(1.52, -13.0)
	_refresh_hud()
	if setup_placed >= _setup_total():
		_finish_setup()


func _setup_total() -> int:
	if human_skill == GameConfig.HumanSkill.BUILDER:
		return 2
	return MINE_COUNT


func _setup_cell_ok(c: Vector2i) -> bool:
	if not _in_bounds(c) or _is_mountain(c) or c == MONSTER_SPAWN:
		return false
	if _cheb(c, HUMAN_HOME) <= 2:
		return false
	if obstacle_set.has(c):
		return false
	return true


func _mine_covers_home(c: Vector2i) -> bool:
	return _cheb(c, HUMAN_HOME) <= 1


func _finish_setup() -> void:
	if not setup_phase:
		return
	setup_phase = false
	remote_deploy = false
	open_hint_hold = 0
	if GameConfig.is_online() and _net() != null and _net().is_online():
		# 联机：开局 4 步归异形玩家自己走
		_say(Texts.s("setup_done_host") if side == 0 else Texts.s("setup_done_monster"))
		hud_result.add_theme_color_override("font_color", PINK_SOFT)
		monster_opening = true
		monster_steps = HEAD_START_STEPS
		turn_side = 1
		player_turn = (side == 1)
		# 两边都要知道「布防结束了」：人类那边要收起部署界面，异形那边要开始走 4 步
		_net_send({"t": "turn", "who": 1})
		_refresh_hud()
		_broadcast()
		return
	_say(Texts.s("setup_done_sp"))
	hud_result.add_theme_color_override("font_color", PINK_SOFT)
	_opening_move()


func _spawn_wall(c: Vector2i) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.235, 0.13, 0.235)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.31, 0.30, 0.28)
	mat.roughness = 0.90
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = mat
	mi.position = _cell_pos(c) + Vector3(0.0, 0.065, 0.0)
	gear_root.add_child(mi)
	# 顶上一条暗红，好认
	var cap := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.205, 0.010, 0.205)
	cap.mesh = cb
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(0.58, 0.24, 0.18, 0.60)
	cap.material_override = cm
	cap.position = Vector3(0.0, 0.071, 0.0)
	mi.add_child(cap)


func _smash_obstacle(c: Vector2i) -> void:
	# 塌的是「这一格」，不是整组 —— 同组另一格还立着，也还能被撞
	obstacle_set.erase(c)
	for i in range(obstacles.size()):
		var g: Array = obstacles[i]
		if g.has(c):
			g.erase(c)
			if g.is_empty():
				obstacles.remove_at(i)
			break
	_free_wall_at(c)
	_refresh_hud()


func _free_wall_at(c: Vector2i) -> void:
	# 只把「这一格的模型」拆掉，别动别的
	for ch in gear_root.get_children():
		if ch is MeshInstance3D and ch.position.distance_to(_cell_pos(c) + Vector3(0.0, 0.065, 0.0)) < 0.05:
			ch.queue_free()


func _wall_crash(cell: Vector2i) -> void:
	# 声音从墙塌的那一格传过来（3D 定位：人类坐左上角，左右能分辨）
	_play_wall_sound(cell)
	_add_shake(0.55)
	if side == 0:
		_say(Texts.s("wall_crash"))
		hud_result.add_theme_color_override("font_color", PINK)
		if result_tween != null and result_tween.is_valid():
			result_tween.kill()
		hud_result.modulate.a = 1.0
		result_tween = create_tween()
		result_tween.tween_interval(1.8)
		result_tween.tween_property(hud_result, "modulate:a", 0.25, 1.0)
	else:
		_notify("墙塌了。他听见了。")


func _play_wall_sound(cell: Vector2i) -> void:
	if audio_hit == null or audio_hit.stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = audio_hit.stream
	p.unit_size = 1.6
	p.max_distance = 12.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.pitch_scale = 0.90
	p.volume_db = 2.0
	p.position = _cell_pos(cell) + Vector3(0.0, 0.05, 0.0)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _spawn_mine(c: Vector2i) -> void:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.055
	cy.bottom_radius = 0.065
	cy.height = 0.035
	mi.mesh = cy
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.24, 0.14)
	mat.metallic = 0.4
	mat.roughness = 0.6
	mi.material_override = mat
	mi.position = _cell_pos(c) + Vector3(0.0, 0.018, 0.0)
	mi.name = "mine_%d_%d" % [c.x, c.y]
	mi.set_meta("mine_owner", c)
	gear_root.add_child(mi)
	# 九格覆盖范围：极淡的暗红地毯
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cc := c + Vector2i(dx, dy)
			if not _in_bounds(cc):
				continue
			var q := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(0.24, 0.24)
			q.mesh = pm
			var qm := StandardMaterial3D.new()
			qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			qm.albedo_color = Color(0.55, 0.14, 0.10, 0.10)
			q.material_override = qm
			q.position = _cell_pos(cc) + Vector3(0.0, 0.034, 0.0)
			q.set_meta("mine_owner", c)
			gear_root.add_child(q)


func _free_mine_at(c: Vector2i) -> void:
	# 雷是「一颗盘 + 九格暗红地毯」，它们都记着自己是哪颗雷的
	for ch in gear_root.get_children():
		if ch is MeshInstance3D and ch.get_meta("mine_owner", Vector2i(-999, -999)) == c:
			ch.queue_free()


func _detonate(c: Vector2i) -> void:
	# 引爆：花掉人类这次行动
	scanning = true
	player_turn = false
	_fx_sound(0.68, -2.0)
	_play(audio_hit)
	var hit := _cheb(c, monster_pos) <= 1
	mine_list.erase(c)
	_free_mine_at(c)
	if hit:
		if _damage_monster():
			human_win = true
			_finish(Texts.s("win_mine_title"), Texts.s("win_mine_sub"), PINK_HOT, "MINE")
			return
		_say(Texts.s("mine_hit"))
		hud_result.add_theme_color_override("font_color", PINK_HOT)
	else:
		_say(Texts.s("mine_miss"))
		hud_result.add_theme_color_override("font_color", PINK_SOFT)
	await get_tree().create_timer(1.0).timeout
	await _monster_turn()


func _damage_monster(amount: float = 1.0) -> bool:
	monster_hp -= amount
	if monster_hp <= 0.001:
		monster_hp = 0.0
		return true
	if monster_skill == GameConfig.MonsterSkill.TOUGH:
		wounded = true
	return false


func _hp_text(v: float = -1.0) -> String:
	var h := monster_hp if v < 0.0 else v
	if absf(h - roundf(h)) < 0.01:
		return "%d" % int(roundf(h))
	return "%.1f" % h


# ---------------------------------------------------------------- 危险区：手雷 / 燃烧

func _leap_dir_toward(from: Vector2i, target: Vector2i) -> Vector2i:
	# 挑一个能落地的方向，跃过去之后离目标更近
	var d := target - from
	var tries: Array[Vector2i] = []
	if absi(d.x) >= absi(d.y):
		tries.append(Vector2i(signi(d.x), 0))
		tries.append(Vector2i(0, signi(d.y)))
	else:
		tries.append(Vector2i(0, signi(d.y)))
		tries.append(Vector2i(signi(d.x), 0))
	for dc in tries:
		if dc == Vector2i.ZERO:
			continue
		var landing := from + dc * 2
		if _in_bounds(landing) and not _is_mountain(landing):
			return dc
	return Vector2i.ZERO


func _tick_hazards() -> void:
	# 一个异形回合结束时结算：先看手雷引信，再看火烧
	if nade_fuse > 0:
		nade_fuse -= 1
		if nade_fuse <= 0 and nade_cell.x >= 0:
			await _explode_nade()
			if ended:
				return
	var keep: Array = []
	for f in fires:
		var c: Vector2i = f["cell"]
		if _cheb(c, monster_pos) <= 1:
			f["hit"] = true
			if _damage_monster(0.5):
				_clear_fires()
				human_win = true
				if side == 0:
					_finish(Texts.s("win_fire_title"), Texts.s("win_fire_sub"), Color(0.85, 0.40, 0.24), "FIRE")
				else:
					_finish(Texts.s("m_fire_title"), Texts.s("m_fire_sub"), Color(0.85, 0.40, 0.24), "FIRE")
				return
		f["turns"] = int(f["turns"]) - 1
		if int(f["turns"]) > 0:
			keep.append(f)
		elif f.has("node") and is_instance_valid(f["node"]):
			f["node"].queue_free()
	fires = keep
	_refresh_hud()


func _clear_fires() -> void:
	for f in fires:
		if f.has("node") and is_instance_valid(f["node"]):
			f["node"].queue_free()
	fires = []


func _explode_nade() -> void:
	var c := nade_cell
	nade_cell = Vector2i(-1, -1)
	nade_fuse = 0
	_play(audio_hit)
	_spawn_blast(c, Color(1.0, 0.55, 0.18), 0.9)
	for ch in gear_root.get_children():
		if ch is MeshInstance3D and ch.position.distance_to(_cell_pos(c) + Vector3(0.0, 0.02, 0.0)) < 0.05:
			ch.queue_free()
	var hit := _cheb(c, monster_pos) <= 1
	await get_tree().create_timer(0.35).timeout
	if hit:
		if _damage_monster(1.0):
			human_win = true
			if side == 0:
				_finish(Texts.s("win_nade_title"), Texts.s("win_nade_sub"), Color(0.85, 0.35, 0.30), "NADE")
			else:
				_finish(Texts.s("m_nade_title"), Texts.s("m_nade_sub"), Color(0.85, 0.35, 0.30), "NADE")
			return
		_notify("炸了 —— 它在里面，但没死。")
	else:
		_notify("炸了。它不在那儿。")


# ---------------------------------------------------------------- 投掷者

func _arm_throw(kind: String) -> void:
	if side != 0 or human_skill != GameConfig.HumanSkill.THROWER:
		return
	if ended or scanning or not player_turn:
		return
	if int(throw_left.get(kind, 0)) <= 0:
		_say(Texts.s("throw_empty"))
		hud_result.add_theme_color_override("font_color", PINK_SOFT)
		hud_result.modulate.a = 1.0
		return
	armed_throw = kind
	var names := {"flash": "闪光弹", "nade": "手雷", "fire": "燃烧弹"}
	_say(Texts.s("throw_arm") % names[kind])
	hud_result.add_theme_color_override("font_color", PINK)
	hud_result.modulate.a = 1.0
	_refresh_hud()


func _throw_cell_ok(cell: Vector2i) -> bool:
	if ended or not _in_bounds(cell):
		return false
	if _is_mountain(cell) or cell == HUMAN_HOME:
		return false
	return true


func _throw_at(mp: Vector2) -> void:
	if armed_throw == "":
		return
	var cell := _cell_at(mp)
	if cell.x < 0:
		return
	if not _throw_cell_ok(cell):
		_say(Texts.s("throw_cant"))
		hud_result.modulate.a = 1.0
		return
	if GameConfig.is_guest():
		_net_send({"t": "cmd", "a": "throw", "k": armed_throw, "c": [cell.x, cell.y]})
		# 本地先扣掉，别等快照 —— 不然按 3 又能把用过的弹举起来
		throw_left[armed_throw] = int(throw_left.get(armed_throw, 1)) - 1
		armed_throw = ""
		player_turn = false
		_say(Texts.s("throw_done"))
		hud_result.modulate.a = 1.0
		_refresh_hud()
		return
	_do_throw(armed_throw, cell)


func _do_throw(kind: String, cell: Vector2i) -> void:
	# 扔出去就花掉这次行动 —— 这回合不能再查
	if int(throw_left.get(kind, 0)) <= 0:
		armed_throw = ""
		return
	armed_throw = ""
	scanning = true
	player_turn = false
	throw_left[kind] = int(throw_left.get(kind, 1)) - 1
	_fx_sound(1.05, -10.0)
	match kind:
		"flash":
			_play(audio_hit)
			_spawn_blast(cell, Color(0.95, 0.95, 0.85), 1.1)
			await get_tree().create_timer(0.45).timeout
			if _cheb(cell, monster_pos) <= 1:
				stun_turns += 1
				_say(Texts.s("flash_hit"))
				hud_result.add_theme_color_override("font_color", PINK_HOT)
				_screen_flash(Color(1.0, 1.0, 0.96), 0.75)
			else:
				_say(Texts.s("flash_miss"))
				hud_result.add_theme_color_override("font_color", PINK_SOFT)
		"nade":
			nade_cell = cell
			nade_fuse = 1
			_spawn_nade(cell)
			_say(Texts.s("nade_placed"))
			hud_result.add_theme_color_override("font_color", PINK)
			await get_tree().create_timer(0.45).timeout
		"fire":
			_spawn_fire(cell)
			_say(Texts.s("fire_placed"))
			hud_result.add_theme_color_override("font_color", PINK)
			await get_tree().create_timer(0.45).timeout
	hud_result.modulate.a = 1.0
	scanning = false
	_refresh_hud()
	await get_tree().create_timer(0.55).timeout
	await _after_human_action()


func _screen_flash(col: Color = Color(1.0, 1.0, 1.0), a: float = 0.8) -> void:
	# 全屏一下白 —— 被闪光弹照脸的时候，不管坐哪边都得有反应
	if flash_rect == null:
		return
	flash_rect.color = Color(col.r, col.g, col.b, 0.0)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", a, 0.06)
	tw.tween_property(flash_rect, "color:a", 0.0, 0.55)


func _spawn_blast(cell: Vector2i, col: Color, size: float) -> void:
	_add_shake(1.0 * size)
	var root := Node3D.new()
	root.position = _cell_pos(cell) + Vector3(0.0, 0.045, 0.0)
	board_root.add_child(root)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			if not _in_bounds(c):
				continue
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(0.24 * size, 0.24 * size)
			mi.mesh = pm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
			mi.material_override = mat
			mi.position = _cell_pos(c) - _cell_pos(cell) + Vector3(0.0, 0.012, 0.0)
			root.add_child(mi)
			var tw := create_tween()
			tw.tween_property(mat, "albedo_color:a", 0.0, 0.55)
	var tw2 := create_tween()
	tw2.tween_interval(0.7)
	tw2.tween_callback(root.queue_free)


func _spawn_nade(cell: Vector2i) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.34, 0.26)
	mat.roughness = 0.7
	mi.material_override = mat
	mi.position = _cell_pos(cell) + Vector3(0.0, 0.06, 0.0)
	gear_root.add_child(mi)


func _spawn_fire(cell: Vector2i) -> void:
	var root := Node3D.new()
	root.position = _cell_pos(cell) + Vector3(0.0, 0.030, 0.0)
	board_root.add_child(root)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			if not _in_bounds(c):
				continue
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(0.235, 0.235)
			mi.mesh = pm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.95, 0.42, 0.12, 0.55)
			mi.material_override = mat
			mi.position = _cell_pos(c) - _cell_pos(cell) + Vector3(0.0, 0.006, 0.0)
			root.add_child(mi)
	fires.append({"cell": cell, "turns": 2, "node": root})



func _ai_deploy() -> void:
	# 玩家当异形时，人类 AI 先布防（你能看见它布了什么）
	if human_skill == GameConfig.HumanSkill.BUILDER:
		for i in range(2):
			for t in range(80):
				var c := Vector2i(randi_range(0, SIZE - 1), randi_range(0, SIZE - 1))
				var vertical := randf() < 0.5
				var two := c + (Vector2i(0, 1) if vertical else Vector2i(1, 0))
				if _setup_cell_ok(c) and _setup_cell_ok(two):
					obstacles.append([c, two])
					for cc in [c, two]:
						obstacle_set[cc] = true
						_spawn_wall(cc)
					break
	else:
		if human_skill != GameConfig.HumanSkill.SAPPER:
			return
		for i in range(MINE_COUNT):
			for t in range(80):
				var c := Vector2i(randi_range(0, SIZE - 1), randi_range(0, SIZE - 1))
				if _setup_cell_ok(c) and not _mine_covers_home(c) and not mine_list.has(c):
					var clear := true
					for dx in range(-1, 2):
						for dy in range(-1, 2):
							var c2 := c + Vector2i(dx, dy)
							if not _in_bounds(c2) or _is_mountain(c2):
								clear = false
					if not clear:
						continue
					mine_list.append(c)
					_spawn_mine(c)
					break


func _try_detonate_at(mp: Vector2) -> bool:
	if side != 0 or ended or scanning or not player_turn:
		return false
	if human_skill != GameConfig.HumanSkill.SAPPER:
		return false
	var cell := _cell_at(mp)
	if cell.x < 0 or not mine_list.has(cell):
		return false
	if GameConfig.is_guest():
		_net_send({"t": "cmd", "a": "boom", "c": [cell.x, cell.y]})
		return true
	_detonate(cell)
	return true


# ---------------------------------------------------------------- 结算：把它的路全画出来

func _reveal_path() -> void:
	# 结算：把它走过的整条路一格一格点亮 —— 这是给人类的「恍然大悟」
	var prev: Vector2i = MONSTER_SPAWN
	for i in range(path.size()):
		var c: Vector2i = path[i]
		var cell_mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.235, 0.235)
		cell_mi.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.95, 0.26, 0.16, 0.0)
		mat.no_depth_test = true
		cell_mi.material_override = mat
		cell_mi.position = _cell_pos(c) + Vector3(0.0, 0.042, 0.0)
		board_root.add_child(cell_mi)
		_reveal_fade(mat, 0.12 * float(i))
		path_nodes.append(cell_mi)

		# 两点之间连一根细红线，让「路径」而不是「一堆点」读得出来
		if i > 0:
			var a := _cell_pos(prev)
			var b := _cell_pos(c)
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.022, 0.012, a.distance_to(b) + 0.10)
			seg.mesh = bm
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.albedo_color = Color(1.0, 0.30, 0.18, 0.0)
			sm.no_depth_test = true
			seg.material_override = sm
			seg.position = (a + b) * 0.5 + Vector3(0.0, 0.038, 0.0)
			var dir: Vector3 = b - a
			if dir.length() > 0.001:
				seg.look_at_from_position(seg.position, seg.position + dir, Vector3.UP)
			board_root.add_child(seg)
			_reveal_fade(sm, 0.12 * float(i))
			path_nodes.append(seg)
		prev = c

	# 终点：一圈红环
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.10
	tm.outer_radius = 0.135
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(1.0, 0.35, 0.22, 0.0)
	rm.no_depth_test = true
	ring.material_override = rm
	ring.position = _cell_pos(monster_pos) + Vector3(0.0, 0.045, 0.0)
	board_root.add_child(ring)
	_reveal_fade(rm, 0.12 * float(path.size()) + 0.10)


func _reveal_fade(mat: StandardMaterial3D, delay: float) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v): mat.albedo_color = Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, v), 0.0, 0.92, 0.18)


func _reveal_trail_glow(mat: StandardMaterial3D, delay: float) -> void:
	# 输掉时点亮的那条路：淡入之后会自己呼吸（发光），比红线更「回头看」
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v): mat.albedo_color = Color(1.0, 0.30, 0.42, v), 0.0, 0.85, 0.22)


func _apply_seat_visuals() -> void:
	hud_result.position = Vector2(500, RESULT_Y)
	hud_result.size = Vector2(600, 44)
	hud_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_view_filter()


func _next_monster_budget() -> int:
	# 手操异形换席时，按技能给这一回合的步数（先读再翻，不然第一回合会白送一个休息）
	if stun_turns > 0:
		# 被晃住：这一回合不动，且不算休息（phase 不翻）
		stun_turns -= 1
		return 0
	if monster_skill == GameConfig.MonsterSkill.BURST:
		var s := 3 if monster_phase == 0 else 0
		monster_phase = 1 - monster_phase
		return s
	if monster_skill == GameConfig.MonsterSkill.PREDATOR:
		return _predator_steps()
	if wounded:
		wounded = false
		return 3
	return 1


func _predator_steps() -> int:
	# 捕食本能：第 7 回合起每回合两步，第 15 回合起每回合三步
	if round_no >= 15:
		return 3
	if round_no >= 7:
		return 2
	return 1


func _survivor_cap() -> int:
	# 求生者：第 7 回合起每回合能连续查 2 格，第 15 回合起 3 格
	if human_skill != GameConfig.HumanSkill.SURVIVOR:
		return 1
	if round_no >= 15:
		return 3
	if round_no >= 7:
		return 2
	return 1


func _survivor_notice() -> void:
	# 跨过 7 / 15 回合的那一刻说一声，否则玩家根本不知道自己的技能生效了
	if side != 0 or human_skill != GameConfig.HumanSkill.SURVIVOR:
		return
	if round_no >= 15 and not survivor_t15:
		survivor_t15 = true
		survivor_t7 = true
		_say("第十五回合了 —— 现在你能连着查三格。", PINK)
	elif round_no >= 7 and not survivor_t7:
		survivor_t7 = true
		_say("第七回合了 —— 从这回合起，你能连着查两格。", PINK)


func _no_steps_reason() -> String:	# 走不动的原因要按技能说，别一律甩「爆发力」
	if stun_turns > 0:
		return "眼前还在白"
	if monster_skill == GameConfig.MonsterSkill.BURST:
		return "爆发力之后要歇一回合"
	return "步数已经走完了"


# ---------------------------------------------------------------- 联机
# 房主（net_mode=1）是权威：所有判定都在它这边跑，客机只发指令、收快照。
# 客机（net_mode=2）不跑规则：本地只做「把格子变成消息」和「把快照画出来」。

func _net() -> Node:
	return get_node_or_null("/root/Net")


func _net_send(d: Dictionary) -> void:
	var n := _net()
	if n != null:
		n.send_msg(d)


func _after_human_action() -> void:
	# 人类行动（探查/引爆/投掷）结算完之后，轮到异形 —— 求生者这一回合还有余额就先不交台
	actions_left -= 1
	if actions_left > 0:
		player_turn = true
		scanning = false
		_say(Texts.s("actions_more") % actions_left)
		_refresh_hud()
		if GameConfig.is_host():
			_broadcast()
		return
	actions_left = 0
	if not GameConfig.is_online() or _net() == null or not _net().is_online():
		await _monster_turn()
		return
	if GameConfig.is_host():
		turn_side = 1
		player_turn = (side == 1)
		# 步数一律由房主算（房主是权威）：客机是异形时，这个数随快照发过去
		monster_steps = _next_monster_budget()
		if side == 1:
			_notify("他查完了。轮到你走 %d 步。" % monster_steps)
		else:
			_net_send({"t": "turn", "who": 1})
			_say(Texts.s("turn_other"))
			hud_result.modulate.a = 1.0
		_refresh_hud()
		_broadcast()


func _broadcast() -> void:
	if not GameConfig.is_host():
		return
	var marks := []
	for m in human_marks:
		var c: Vector2i = m["cell"]
		marks.append([c.x, c.y, int(m["result"])])
	var walls := []
	for g in obstacles:
		for c in g:
			walls.append([c.x, c.y])
	var mines := []
	for c in mine_list:
		mines.append([c.x, c.y])
	var perm := []
	for c in perm_fp_cells.keys():
		perm.append([c.x, c.y])
	var traceline := []
	for c in path:
		traceline.append([c.x, c.y])
	var fire_cells := []
	for f in fires:
		var fc: Vector2i = f["cell"]
		fire_cells.append([fc.x, fc.y, int(f["turns"])])
	var snap := {
		"t": "snap",
		"round": round_no,
		"probes": probes_used,
		"steps": monster_steps,
		"opening": monster_opening,
		"hp": monster_hp,
		"ended": ended,
		"win": human_win,
		"text": hud_result.text,
		"marks": marks,
		"walls": walls,
		"mines": mines,
		"perm": perm,
		"pa": traceline,
		"pos": [monster_pos.x, monster_pos.y],
		"turn": turn_side,
		"title": hud_end.text,
		"sub": end_sub,
		"reason": end_reason,
		"leap": leap_left,
		"stun": stun_turns,
		"nade": [nade_cell.x, nade_cell.y, nade_fuse],
		"fires": fire_cells,
		"throw": [int(throw_left.get("flash", 0)), int(throw_left.get("nade", 0)), int(throw_left.get("fire", 0))],
	}
	# 客机是异形（房主是人类）时，客机需要自己的步数/血/弹跳/晕眩；
	# 客机是人类时这些都属于「对面暗选的东西」，一个字段都不能发 —— 发过去就是泄题。
	var guest_side := 1 - side
	if guest_side == GameConfig.Side.HUMAN:
		for k in ["steps", "opening", "hp", "leap", "stun"]:
			snap.erase(k)
		# 客机是人类时，求生者的「这回合还能查几次」是他自己的事，要发过去
		snap["actions"] = actions_left
	# 房主这边的私人提示语不能整句转发：只告诉客机「是不是轮到你」
	if turn_side == guest_side:
		snap["text"] = Texts.s("turn_you") if guest_side == GameConfig.Side.HUMAN else Texts.s("turn_you_monster")
	elif guest_side == GameConfig.Side.HUMAN:
		snap["text"] = Texts.s("turn_other")
	else:
		snap["text"] = "轮到他了。"
	_net_send(snap)


func _resync_deploy() -> void:
	# 等对面布防：问三次，每次隔 2.5 秒
	for i in 3:
		await get_tree().create_timer(2.5).timeout
		if not remote_deploy or ended or not is_inside_tree():
			return
		_net_send({"t": "need_deploy"})


func _on_peer_left() -> void:
	# 对手掉线：停在这儿，别让对局继续跑
	if ended:
		return
	ended = true
	player_turn = false
	_refresh_hud()
	_say(Texts.s("peer_left"))
	hud_result.modulate.a = 1.0
	hud_end.visible = true
	hud_end.text = Texts.s("peer_left_end")
	hud_end.add_theme_color_override("font_color", Color(0.72, 0.70, 0.68))
	hud_end.modulate.a = 1.0


func _on_net_msg(d: Dictionary) -> void:
	var t := String(d.get("t", ""))
	if t == "snap":
		if GameConfig.is_guest():
			_apply_snapshot(d)
		return
	if t == "turn" and GameConfig.is_guest():
		# 房主说：布防结束（或轮次换了）—— 收起本地的部署界面
		if setup_phase:
			setup_phase = false
			remote_deploy = false
			_say(Texts.s("setup_done_wait"))
			hud_result.modulate.a = 1.0
		var who := int(d.get("who", 0))
		turn_side = who
		player_turn = (who == side)
		if player_turn:
			_say(Texts.s("turn_you") if side == 0 else Texts.s("turn_you_monster"))
		else:
			_say(Texts.s("turn_other") if side == 0 else "轮到他了。")
		hud_result.modulate.a = 1.0
		_refresh_hud()
		return
	if t == "probe_result" and GameConfig.is_guest():
		var pc := Vector2i(int(d.get("c", [0, 0])[0]), int(d.get("c", [0, 0])[1]))
		var pr := int(d.get("r", 0))
		_mark_human_probe(pc, pr)
		var ptxt := {
			0: "那儿什么都没有。",
			1: "有脚印 —— 它走过这儿。",
			2: "找到了！",
		}
		_say(ptxt.get(pr, ""))
		hud_result.add_theme_color_override("font_color", PINK if pr == 2 else PINK_SOFT)
		hud_result.modulate.a = 1.0
		return
	if t == "need_deploy" and GameConfig.is_guest():
		# 房主没收到我的「布防完了」：布完的话重播一遍
		if side == GameConfig.Side.HUMAN and not setup_phase and not ended:
			_net_send({"t": "cmd", "a": "deploy_done"})
		return
	if not GameConfig.is_host():
		return
	if t == "turn":
		# 客机说它那边走完了，把台子交回来
		if int(d.get("who", 0)) == 0:
			await _tick_hazards()
			if ended:
				return
			round_no += 1
			turn_side = 0
			player_turn = true
			monster_steps = 0
			_refresh_hud()
			if round_no > MAX_ROUNDS:
				_finish(Texts.s("m_timeout_title"), Texts.s("m_timeout_sub"), Color(0.75, 0.72, 0.60), "TIMEOUT")
			_broadcast()
		return
	if t == "cmd":
		_apply_cmd(d)


func _apply_cmd(d: Dictionary) -> void:
	var a := String(d.get("a", ""))
	var c := Vector2i(int(d.get("c", [0, 0])[0]), int(d.get("c", [0, 0])[1]))
	match a:
		"probe":
			# 客机当人类时，只有轮到他、且不在部署/开局 4 步时才能查
			if side != 1 or setup_phase or monster_opening or ended or turn_side != 0:
				return
			_remote_human_probe(c)
		"boom":
			if side != 1 or setup_phase or monster_opening or ended or turn_side != 0:
				return
			if mine_list.has(c):
				_detonate(c)
				_broadcast()
		"deploy_done":
			# 对面是人类投掷者：他没有布防，直接开局
			if side != 1 or not setup_phase:
				return
			_finish_setup()
			_broadcast()
		"place":
			if side != 1 or not setup_phase:
				return
			setup_vertical = bool(d.get("v", false))
			_setup_place_cell(c)
			_broadcast()
		"throw":
			if side != 1 or setup_phase or monster_opening or ended or turn_side != 0:
				return
			var k := String(d.get("k", ""))
			if k == "" or int(throw_left.get(k, 0)) <= 0:
				return
			_do_throw(k, c)
		"leap":
			if side != 0 or ended or monster_steps <= 0 or leap_left <= 0:
				return
			if _cheb(monster_pos, c) != 2 or _is_mountain(c):
				return
			var dd: Vector2i = c - monster_pos
			if dd.x != 0 and dd.y != 0:
				return
			_leap_to(c)
			_broadcast()
		"move":
			if side != 0:
				return
			if monster_steps <= 0 or ended:
				return
			if _cheb(monster_pos, c) != 1 or _is_mountain(c):
				return
			_take_step(c)
			_broadcast()
		"walk":
			# 客机点了个远处的格子：整条路由房主来走，逐步扣步数
			if side != 0 or ended or monster_steps <= 0:
				return
			_walk_to(c)
			_broadcast()
		"end":
			if side != 0:
				return
			if monster_opening:
				# 开局的 4 步走完：第 1 回合正式开始
				monster_opening = false
				monster_steps = 0
				player_turn = true
				turn_side = 0
				actions_left = _survivor_cap()
				_say(Texts.s("turn_you"))
				_net_send({"t": "turn", "who": 0})
				_refresh_hud()
				_broadcast()
				return
			await _tick_hazards()
			if ended:
				return
			round_no += 1
			monster_steps = 0
			turn_side = 0
			player_turn = true
			actions_left = _survivor_cap()
			_say(Texts.s("turn_you"))
			_refresh_hud()
			_survivor_notice()
			if round_no > MAX_ROUNDS:
				_finish(Texts.s("m_timeout_title"), Texts.s("m_timeout_sub"), Color(0.75, 0.72, 0.60), "TIMEOUT")
			_net_send({"t": "turn", "who": 0})
			_broadcast()


func _remote_human_probe(cell: Vector2i) -> void:
	# 房主当异形、客机当人类：他查了一格
	var res := 0
	if cell == monster_pos:
		res = 2
	elif visited.has(cell):
		res = 1
	probes_used += 1
	human_marks.append({"cell": cell, "result": res})
	var txt := {0: "他查了 (%d,%d) —— 什么也没有。", 1: "他查了 (%d,%d) —— 有脚印。", 2: "他查到了你！"}
	_notify(txt[res] % [cell.x, cell.y] if res < 2 else "他查到了你！")
	_mark_human_probe(cell, res)
	# 客机是探测方：结果要发回给它自己（它本地不知道踩没踩中）
	_net_send({"t": "probe_result", "c": [cell.x, cell.y], "r": res})
	if res == 2:
		if _damage_monster():
			human_win = false
			_finish(Texts.s("m_probe_title"), Texts.s("m_probe_sub"), Color(0.85, 0.35, 0.30), "PROBE")
			_broadcast()
			return
		_notify("他查到了你 —— 但你还剩一口气。")
	# 求生者：他这一回合可能还有余额，没花完就先不交台
	actions_left -= 1
	if actions_left > 0:
		turn_side = 0
		player_turn = false
		_notify("他还能再查 %d 次。" % actions_left)
		_net_send({"t": "turn", "who": 0})
		_refresh_hud()
		_broadcast()
		return
	actions_left = 0
	monster_steps = _next_monster_budget()
	turn_side = 1
	player_turn = (side == 1)
	_refresh_hud()
	_broadcast()


func _apply_snapshot(d: Dictionary) -> void:
	round_no = int(d.get("round", round_no))
	probes_used = int(d.get("probes", probes_used))
	monster_steps = int(d.get("steps", monster_steps))
	actions_left = int(d.get("actions", actions_left))
	monster_opening = bool(d.get("opening", false))
	monster_hp = float(d.get("hp", monster_hp))
	leap_left = int(d.get("leap", leap_left))
	var new_stun := int(d.get("stun", 0))
	if new_stun > stun_turns and side == 1:
		# 客机异形被闪光弹照了：本地不知道发生了什么，得有人告诉它
		_say("一道白光 —— 你什么都看不见。", Color(0.92, 0.92, 0.86), true)
		_screen_flash(Color(1.0, 1.0, 0.96), 0.8)
	stun_turns = new_stun
	if d.has("nade"):
		var nd = d["nade"]
		var nc := Vector2i(int(nd[0]), int(nd[1]))
		var nf := int(nd[2])
		if nc.x >= 0 and nf > 0 and nade_cell != nc:
			nade_cell = nc
			nade_fuse = nf
			_spawn_nade(nc)
		elif nf <= 0:
			if nade_cell.x >= 0:
				# 对面炸了：这边把那个小圆片收掉，放个爆点
				for ch in gear_root.get_children():
					if ch is MeshInstance3D and ch.position.distance_to(_cell_pos(nade_cell) + Vector3(0.0, 0.02, 0.0)) < 0.05:
						ch.queue_free()
				_spawn_blast(nade_cell, Color(1.0, 0.55, 0.18), 0.9)
			nade_cell = Vector2i(-1, -1)
			nade_fuse = 0
	if d.has("fires"):
		var seen := {}
		for fr in d["fires"]:
			var fc := Vector2i(int(fr[0]), int(fr[1]))
			seen[fc] = true
			var have := false
			for f in fires:
				if f["cell"] == fc:
					have = true
			if not have:
				_spawn_fire(fc)
		# 房主说了算：它那边烧完了的格子，这边也得熄掉，不然火会永远留在盘面上
		var keep_f: Array = []
		for f in fires:
			if seen.has(f["cell"]):
				keep_f.append(f)
			elif f.has("node") and is_instance_valid(f["node"]):
				f["node"].queue_free()
		fires = keep_f
	if d.has("throw"):
		var tt = d["throw"]
		throw_left["flash"] = int(tt[0])
		throw_left["nade"] = int(tt[1])
		throw_left["fire"] = int(tt[2])
		if armed_throw != "" and int(throw_left.get(armed_throw, 0)) <= 0:
			armed_throw = ""
	if d.has("pos"):
		monster_pos = Vector2i(int(d["pos"][0]), int(d["pos"][1]))
	var turn := int(d.get("turn", 0))
	turn_side = turn
	player_turn = (turn == side)
	# 记号
	for m in d.get("marks", []):
		_mark_human_probe(Vector2i(int(m[0]), int(m[1])), int(m[2]))
	# 工事：快照是「当前状态」，不是「增量」。
	# 只增不删的话，客机这边墙塌了、雷炸了都会一直留在原地。
	var wall_now := {}
	for w in d.get("walls", []):
		wall_now[Vector2i(int(w[0]), int(w[1]))] = true
	for c in obstacle_set.keys():
		if not wall_now.has(c):
			obstacle_set.erase(c)
			_free_wall_at(c)
	for c in wall_now.keys():
		if not obstacle_set.has(c):
			obstacle_set[c] = true
			_spawn_wall(c)

	var mine_now := {}
	for mi in d.get("mines", []):
		mine_now[Vector2i(int(mi[0]), int(mi[1]))] = true
	for c in mine_list.duplicate():
		if not mine_now.has(c):
			mine_list.erase(c)
			_free_mine_at(c)
	for c in mine_now.keys():
		if not mine_list.has(c):
			mine_list.append(c)
			_spawn_mine(c)
	if side == 1:
		# 出生点本身也算「它站过的地方」—— 客机异形开局就得看见脚下这一枚
		_add_perm_footprint(MONSTER_SPAWN)
		for p in d.get("perm", []):
			_add_perm_footprint(Vector2i(int(p[0]), int(p[1])))
		_update_self_marker()
	var txt := String(d.get("text", ""))
	if txt != "" and hud_result.text != txt:
		_say(txt)
		hud_result.modulate.a = 1.0
	if bool(d.get("ended", false)) and not ended:
		ended = true
		# 结算文案按「我在哪一边」重算 —— 房主那套字是从房主视角写的，直接搬过来会说反
		var rs := String(d.get("reason", ""))
		if d.has("win"):
			human_win = bool(d["win"])
		if side == 0:
			# 先把快照里的足迹补进本地：_finish 里「点亮全场足迹」要用它，
			# 补晚了就只亮得出出生点那一枚
			for p in d.get("perm", []):
				var pc := Vector2i(int(p[0]), int(p[1]))
				if not visited.has(pc):
					visited[pc] = true
					path.append(pc)
			if not visited.has(MONSTER_SPAWN):
				visited[MONSTER_SPAWN] = true
				path.push_front(MONSTER_SPAWN)
		if side == 0 and bool(d.get("win", false)):
			# 客机人类赢了：本地点亮那条红线要按房主记录的真实路径来
			path.clear()
			for p in d.get("pa", []):
				path.append(Vector2i(int(p[0]), int(p[1])))
		var pair := _end_texts(rs)
		var ttl := String(pair[0])
		var sbb := String(pair[1])
		if ttl == "":
			ttl = String(d.get("title", "结束了。"))
			sbb = String(d.get("sub", ""))
		_finish(ttl, sbb, Color(0.85, 0.35, 0.30), rs)
		if bool(d.get("win", false)) and side == 0:
			_reveal_path()
	_applying_snapshot = true
	_refresh_hud()
	_applying_snapshot = false
