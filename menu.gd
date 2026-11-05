extends Control

# 主菜单：标题 → 选阵营 → 选技能 → 开局
# 全部用代码搭，方便以后换成美术资源

const W := 1600
const H := 900

var font: SystemFont
var page_root: Control
var menu_bgm: AudioStreamPlayer
var desc_label: Label
var chosen_side := 0
var side_btn_a: Button
var side_btn_b: Button
var skill_btn_a: Button
var skill_btn_b: Button
var skill_btn_c: Button
var skill_btn_d: Button

# 联机
var online_mode := false
var status_label: Label
var code_label: Label
var addr_edit: LineEdit
var code_edit: LineEdit
var pending_create := false
var my_skill := 0
var peer_skill := 0
var roles_sent := false
var guest_ready := false
var join_code_pending := ""
var relay_check: CheckBox


func _ready() -> void:
	# 「再来一局」时不能 reset：联机状态和房间连接要留着
	var rematch := GameConfig.rematch
	GameConfig.rematch = false
	if not rematch:
		GameConfig.reset()
	online_mode = false
	var bg := ColorRect.new()
	bg.color = Color(0.014, 0.015, 0.021)
	bg.position = Vector2.ZERO
	bg.size = Vector2(W, H)
	add_child(bg)

	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "Segoe UI"])

	page_root = Control.new()
	page_root.position = Vector2.ZERO
	page_root.size = Vector2(W, H)
	add_child(page_root)

	var net := _net()
	net.state_changed.connect(_on_net_state)
	net.room_created.connect(_on_room_created)
	net.room_joined.connect(_on_room_joined)
	net.peer_joined.connect(_on_peer_joined)
	net.peer_left.connect(_on_peer_left)
	net.message.connect(_on_net_message)
	net.net_error.connect(_on_net_error)

	if rematch:
		_enter_rematch()
	else:
		_show_page(0)
	_start_bgm()


func _enter_rematch() -> void:
	# 回到「选阵营」：技能和地形都要重挑，房间连接不动
	online_mode = GameConfig.is_online()
	roles_sent = false
	GameConfig.human_skill = 0
	GameConfig.monster_skill = 0
	GameConfig.map_seed = 0
	my_skill = 0
	peer_skill = 0
	guest_ready = false
	_show_page(1)
	if GameConfig.is_guest():
		_set_status("房主想再来一局 —— 等他挑边。")


func _start_bgm() -> void:
	# 菜单也有房间底噪，音量比对局里更低一档 —— 否则一进游戏会觉得音乐「突然起来了」
	var stream := load("res://audio/bgm_room_dark.wav") as AudioStreamWAV
	if stream == null:
		return
	if stream.format == AudioStreamWAV.FORMAT_16_BITS or stream.format == AudioStreamWAV.FORMAT_8_BITS:
		var bps := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / (bps * (2 if stream.stereo else 1))
	menu_bgm = AudioStreamPlayer.new()
	menu_bgm.stream = stream
	menu_bgm.volume_db = -16.0
	add_child(menu_bgm)
	menu_bgm.play()


func _net() -> Node:
	return get_node_or_null("/root/Net")


func _show_page(n: int) -> void:
	for c in page_root.get_children():
		c.queue_free()
	status_label = null
	code_label = null
	addr_edit = null
	code_edit = null
	match n:
		0:
			_build_title()
		1:
			_build_side()
		2:
			_build_skill()
		3:
			_build_online()


# ---------------------------------------------------------------- 组件

func _label(txt: String, size: int, color: Color, pos: Vector2, w: float = 900.0) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.size = Vector2(w, size * 1.8)
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	page_root.add_child(l)
	return l


func _line(pos: Vector2, w: float, color: Color) -> void:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = Vector2(w, 1)
	page_root.add_child(r)


func _button(txt: String, pos: Vector2, w: float, h: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = pos
	b.size = Vector2(w, h)
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color(0.70, 0.67, 0.60))
	b.add_theme_color_override("font_hover_color", Color(0.98, 0.92, 0.80))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.55, 0.42))
	b.add_theme_color_override("font_focus_color", Color(0.70, 0.67, 0.60))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.05, 0.06, 0.55)
	normal.border_color = Color(0.34, 0.31, 0.26, 0.65)
	normal.set_border_width_all(1)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.10, 0.08, 0.07, 0.75)
	hover.border_color = Color(0.72, 0.58, 0.40, 0.95)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.14, 0.07, 0.06, 0.85)
	pressed.border_color = Color(0.85, 0.42, 0.30, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.pressed.connect(cb)
	page_root.add_child(b)
	return b


func _edit(default_text: String, pos: Vector2, w: float, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.text = default_text
	e.position = pos
	e.size = Vector2(w, 54)
	e.max_length = max_len
	e.add_theme_font_override("font", font)
	e.add_theme_font_size_override("font_size", 22)
	e.add_theme_color_override("font_color", Color(0.88, 0.84, 0.76))
	e.add_theme_color_override("font_placeholder_color", Color(0.36, 0.35, 0.32))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.05, 0.85)
	sb.border_color = Color(0.34, 0.31, 0.26, 0.65)
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	page_root.add_child(e)
	return e


# ---------------------------------------------------------------- 第 0 页：标题

func _build_title() -> void:
	_label("异 形 入 侵", 76, Color(0.86, 0.83, 0.76), Vector2(160, 250), 1200)
	_line(Vector2(162, 372), 620, Color(0.40, 0.22, 0.18, 0.85))
	_label("一张桌子，十格见方。它在黑暗里，一步一步往你家走。", 22, Color(0.52, 0.50, 0.46), Vector2(162, 396), 1200)
	_label("你每回合只能查一格。二十回合后，天就亮了。", 22, Color(0.52, 0.50, 0.46), Vector2(162, 434), 1200)

	_button("开   始", Vector2(162, 540), 300, 62, func(): _show_page(1))
	_button("联   机", Vector2(500, 540), 300, 62, func(): _show_page(3))
	_button("退   出", Vector2(838, 540), 300, 62, func(): get_tree().quit())

	_label("v1.1 · 人类 / 异形双席位 · 八技能 · 联机直连", 16, Color(0.30, 0.29, 0.27), Vector2(162, 820), 900)


# ---------------------------------------------------------------- 第 1 页：选阵营

func _build_side() -> void:
	_label("你要坐在哪一边？", 44, Color(0.86, 0.83, 0.76), Vector2(160, 140), 1200)
	_line(Vector2(162, 216), 900, Color(0.40, 0.22, 0.18, 0.85))

	side_btn_a = _button("人 类 · 值 班 员", Vector2(162, 270), 560, 90, func(): _set_side(0))
	_label("你看不见它。你只有二十次机会，和一间越来越暗的值班室。", 18, Color(0.50, 0.48, 0.44), Vector2(162, 372), 560)

	side_btn_b = _button("异 形 · 它", Vector2(782, 270), 560, 90, func(): _set_side(1))
	_label("你看得见它查每一格。你要在二十回合内，摸到 (0,0)。", 18, Color(0.50, 0.48, 0.44), Vector2(782, 372), 560)

	_label("两边是同一张桌子的对面。换座位不换局面。", 17, Color(0.34, 0.33, 0.30), Vector2(162, 470), 900)

	if GameConfig.is_online() and GameConfig.is_guest():
		# 客机不能挑边，得等房主 —— 不说明的话，两边都点不动会像卡住
		_label("对面正在挑边 —— 他选完，你就自动进下一步。", 18, Color(0.60, 0.52, 0.55), Vector2(162, 520), 900)
		side_btn_a.disabled = true
		side_btn_b.disabled = true

	_button("返 回", Vector2(162, 760), 200, 54, func(): _show_page(0))


func _set_side(s: int) -> void:
	# 联机时只有房主挑边，客机等 roles
	if GameConfig.is_online() and GameConfig.is_guest():
		return
	chosen_side = s
	GameConfig.player_side = s
	if online_mode and GameConfig.is_host() and not roles_sent:
		roles_sent = true
		_net().send_msg({"t": "roles", "side": s})
	_show_page(2)


# ---------------------------------------------------------------- 第 2 页：选技能

func _build_skill() -> void:
	var is_human := GameConfig.player_side == 0
	_label("暗选一个技能" if is_human else "暗选一个技能", 44, Color(0.86, 0.83, 0.76), Vector2(160, 120), 1200)
	_line(Vector2(162, 196), 900, Color(0.40, 0.22, 0.18, 0.85))
	_label("选完就锁死，对手不会知道你选了什么 —— 直到它显形。", 19, Color(0.48, 0.46, 0.42), Vector2(162, 212), 1000)

	if is_human:
		skill_btn_a = _button("布 障 者", Vector2(130, 280), 310, 96, func(): _pick_skill(1))
		skill_btn_b = _button("地 雷 师", Vector2(460, 280), 310, 96, func(): _pick_skill(2))
		skill_btn_c = _button("投 掷 者", Vector2(790, 280), 310, 96, func(): _pick_skill(3))
		skill_btn_d = _button("求 生 者", Vector2(1120, 280), 310, 96, func(): _pick_skill(4))
		_label("立墙改路", 16, Color(0.44, 0.42, 0.38), Vector2(130, 384), 310)
		_label("埋雷押注", 16, Color(0.44, 0.42, 0.38), Vector2(460, 384), 310)
		_label("三颗投掷物", 16, Color(0.44, 0.42, 0.38), Vector2(790, 384), 310)
		_label("后期多查几眼", 16, Color(0.44, 0.42, 0.38), Vector2(1120, 384), 310)
	else:
		skill_btn_a = _button("强 健 体 魄", Vector2(130, 280), 310, 96, func(): _pick_skill(1))
		skill_btn_b = _button("爆 发 力", Vector2(460, 280), 310, 96, func(): _pick_skill(2))
		skill_btn_c = _button("弹 跳 力", Vector2(790, 280), 310, 96, func(): _pick_skill(3))
		skill_btn_d = _button("捕 食 本 能", Vector2(1120, 280), 310, 96, func(): _pick_skill(4))
		_label("两条命", 16, Color(0.44, 0.42, 0.38), Vector2(130, 384), 310)
		_label("三步，然后僵住", 16, Color(0.44, 0.42, 0.38), Vector2(460, 384), 310)
		_label("跃过一格，两次", 16, Color(0.44, 0.42, 0.38), Vector2(790, 384), 310)
		_label("后期越走越快", 16, Color(0.44, 0.42, 0.38), Vector2(1120, 384), 310)

	desc_label = _label("", 20, Color(0.72, 0.68, 0.60), Vector2(162, 450), 1220)

	skill_btn_a.mouse_entered.connect(func(): _preview(1))
	skill_btn_b.mouse_entered.connect(func(): _preview(2))
	skill_btn_c.mouse_entered.connect(func(): _preview(3))
	skill_btn_d.mouse_entered.connect(func(): _preview(4))
	_preview(1)

	# 三局两胜：这一整场已经用过的职业不允许再选
	if GameConfig.is_bo3():
		var used: Array = GameConfig.used_human if is_human else GameConfig.used_monster
		var btns := [skill_btn_a, skill_btn_b, skill_btn_c, skill_btn_d]
		for i in btns.size():
			var b: Button = btns[i]
			if used.has(i + 1):
				b.disabled = true
				b.text = "（已用过）"
		_label("第 %d 局 · 比分 人类 %d : %d 异形 —— 用过的职业不能再选。" % [
			GameConfig.match_round, GameConfig.wins_human, GameConfig.wins_monster],
			18, Color(0.72, 0.55, 0.58), Vector2(162, 244), 1240)

	_button("返 回", Vector2(162, 760), 200, 54, func(): _show_page(1))


func _preview(which: int) -> void:
	var is_human := GameConfig.player_side == 0
	if is_human:
		match which:
			1:
				desc_label.text = "布障者：两组墙，盲放。它穿得过去，但会撞碎墙 —— 那一声你听得见，方位也听得出来。用它把它的必经之路逼到你下几眼能查到的地方。"
			2:
				desc_label.text = "地雷师：三颗雷，盲放，每颗盖九格。人类回合可以引爆（花掉这一次行动），它在雷边就吃一发；打空就永久没了。"
			3:
				desc_label.text = "投掷者：闪光弹（九格里有没有它，有就晃住它一回合）、手雷（延迟一回合爆，伤害 1）、燃烧弹（两回合，每回合 0.5）。各一颗，扔出去这回合就不能再查。"
			_:
				desc_label.text = "求生者：第七回合起，每回合能连着查两格；第十五回合起，能连着查三格。没有别的手段 —— 就是把最后几轮的眼睛翻倍。"
	else:
		match which:
			1:
				desc_label.text = "强健体魄：两条命。被查中一次不会死，你会带着伤爆发逃开（下一回合走三步）。"
			2:
				desc_label.text = "爆发力：一回合走三步，下一回合必须站着不动 —— 那两回合里，他连查两次。"
			3:
				desc_label.text = "弹跳力：跃过相邻一格落到再下一格，被跳过的那格不留脚印。整局两次，跳跃算一步。"
			_:
				desc_label.text = "捕食本能：第七回合起，每回合走两步；第十五回合起，每回合走三步。越到后面越追不上。"


func _pick_skill(which: int) -> void:
	var is_human := GameConfig.player_side == 0
	if is_human:
		GameConfig.human_skill = which
	else:
		GameConfig.monster_skill = which

	if online_mode:
		my_skill = which
		_net().send_msg({"t": "skill", "s": which})
		_set_status("选好了。等对面……")
		_lock_skill_buttons()
		_try_start_online()
		return

	# 单机：对手随机暗选，玩家看不见
	randomize()
	if is_human:
		GameConfig.monster_skill = randi_range(1, 4)
	else:
		GameConfig.human_skill = randi_range(1, 4)
	get_tree().change_scene_to_file("res://main.tscn")


# ---------------------------------------------------------------- 第 3 页：联机

func _build_online() -> void:
	online_mode = true
	_label("联 机", 44, Color(0.86, 0.83, 0.76), Vector2(160, 150), 1200)
	_line(Vector2(162, 226), 900, Color(0.40, 0.22, 0.18, 0.85))
	_label("默认直连：一个人点「开 房」，另一个把地址填成 ws://他的IP:7788 点「加 入」。\n只有当你们不在同一个局域网/虚拟局域网里时，才勾上下面那个「走中转」，并用 server\\启动服务器.bat。", 19, Color(0.48, 0.46, 0.42), Vector2(162, 244), 1200)

	_label("服务器地址（加入时填房主的地址）", 17, Color(0.46, 0.44, 0.40), Vector2(162, 320), 600)
	addr_edit = _edit(_net().server_url, Vector2(162, 348), 640, 120)

	relay_check = CheckBox.new()
	relay_check.text = "走中转服务器（跨公网才需要）"
	relay_check.position = Vector2(162, 396)
	relay_check.size = Vector2(400, 32)
	relay_check.add_theme_font_override("font", font)
	relay_check.add_theme_color_override("font_color", Color(0.50, 0.48, 0.44))
	page_root.add_child(relay_check)

	_button("开 房", Vector2(162, 440), 300, 62, func(): _do_create())
	_button("加 入", Vector2(500, 440), 200, 62, func(): _do_join())
	code_edit = _edit("", Vector2(720, 444), 160, 4)
	code_edit.placeholder_text = "房间号(中转)"

	status_label = _label("", 21, Color(0.72, 0.68, 0.60), Vector2(162, 540), 1200)
	code_label = _label("", 44, Color(0.94, 0.72, 0.42), Vector2(162, 600), 1200)

	# 玩法：三种联机模式（经典 / 三局两胜 / 死里逃生 / 亡命追猎）
	_label("玩法", 17, Color(0.46, 0.44, 0.40), Vector2(900, 320), 400)
	var modes := [
		["经 典", GameConfig.Mode.CLASSIC],
		["三局两胜", GameConfig.Mode.BO3],
		["死里逃生", GameConfig.Mode.ESCAPE],
		["亡命追猎", GameConfig.Mode.HUNT],
	]
	for i in modes.size():
		var m: Array = modes[i]
		var b := _button(String(m[0]), Vector2(900, 348 + i * 52), 220, 44, func(): _set_mode(int(m[1])))
		if GameConfig.mode == int(m[1]):
			b.add_theme_color_override("font_color", Color(0.98, 0.62, 0.78))
	_button("返 回", Vector2(162, 760), 200, 54, func(): _leave_online())


func _set_mode(m: int) -> void:
	GameConfig.mode = m
	GameConfig.match_round = 1
	GameConfig.wins_human = 0
	GameConfig.wins_monster = 0
	GameConfig.used_human = []
	GameConfig.used_monster = []
	GameConfig.win_marks = []
	_show_page(3)


func _set_status(txt: String) -> void:
	if status_label != null:
		status_label.text = txt


func _do_create() -> void:
	var net := _net()
	var use_relay: bool = relay_check != null and relay_check.button_pressed
	if not use_relay:
		# 直连：本机开监听 + 广播房间号，客机只要报个号就能找到你
		if net.is_online():
			net.close()
		_set_status("正在开房……")
		net.host(7788)
		return
	if net.is_online():
		net.create_room()
		return
	pending_create = true
	_set_status("连接中……")
	net.connect_to(addr_edit.text if addr_edit != null else "")


func _do_join() -> void:
	var net := _net()
	var use_relay: bool = relay_check != null and relay_check.button_pressed
	var url := addr_edit.text.strip_edges() if addr_edit != null else ""
	if not use_relay:
		var code := code_edit.text.strip_edges() if code_edit != null else ""
		if code.length() == 4:
			_set_status("在局域网里找他……")
			net.join_by_code(code)
			return
		if url != "":
			_set_status("连接中……")
			net.join_direct(url)
			return
		_set_status("填四位数房间号；或者填房主的地址 ws://他的IP:7788")
		return
	var code := code_edit.text.strip_edges()
	if code.length() < 4:
		_set_status("四个数字的房间号。")
		return
	pending_create = false
	if net.is_online():
		net.join_room(code)
		_set_status("进房中……")
		return
	_set_status("连接中……")
	net.connect_to(url)
	join_code_pending = code


func _leave_online() -> void:
	online_mode = false
	_net().close()
	_show_page(0)


func _on_net_state() -> void:
	var net := _net()
	if net.status != 2:
		return
	if pending_create:
		pending_create = false
		net.create_room()
	elif join_code_pending != "":
		var c := join_code_pending
		join_code_pending = ""
		net.join_room(c)


func _on_room_created(code: String) -> void:
	GameConfig.net_mode = 1
	if _net().direct:
		# 直连：报房间号就行；IP 是给「不在同一个局域网」时兜底的
		var ip: String = String(_net().local_ipv4())
		_set_status("房间号告诉对面，他在「加入」里填这四位数。\n不在同一个局域网/虚拟网里时，才让他填 ws://%s:7788。" % ip)
		if code_label != null:
			code_label.text = code
	else:
		_set_status("把房间号告诉对面。等他进来。")
		if code_label != null:
			code_label.text = code


func _on_room_joined(code: String) -> void:
	GameConfig.net_mode = 2
	if _net().direct:
		_set_status("连上了（直连）。等房主选完阵营……")
	else:
		_set_status("进来了。等房主选完阵营……")
	if code_label != null:
		code_label.text = "" if _net().direct else code


func _on_peer_joined() -> void:
	if not GameConfig.is_host():
		return
	_set_status("对手进来了。你先选阵营。")
	_show_page(1)


func _on_peer_left() -> void:
	if status_label != null:
		_set_status("对手断开了。")


func _on_net_error(why: String) -> void:
	var m := {
		"no_room": "没有这个房间号。",
		"room_full": "这间房已经两个人了。",
		"host_gone": "房主已经走了。",
		"connect_failed": "连不上服务器。",
		"room_not_found": "没找到这个房间号 —— 你们要在同一个局域网（或同一个虚拟局域网）里。\n还是不行的话，让他把房间开好，你在「服务器地址」里填 ws://他的IP:7788 再点加入。",
		"listen_failed": "端口 7788 被占了 —— 是不是已经开了一个窗口在当房主？",
	}
	_set_status(m.get(why, "出错了：" + why))


func _on_net_message(data: Dictionary) -> void:
	match String(data.get("t", "")):
		"roles":
			if GameConfig.is_guest():
				GameConfig.player_side = 1 - int(data.get("side", 0))
				_set_status("房主选了%s。你坐另一边。" % ("人类" if int(data.get("side", 0)) == 0 else "异形"))
				_show_page(2)
		"skill":
			peer_skill = int(data.get("s", 1))
			guest_ready = true
			_try_start_online()
		"start":
			if GameConfig.is_guest():
				GameConfig.map_seed = int(data.get("seed", 0))
				get_tree().change_scene_to_file("res://main.tscn")
		"bye":
			if status_label != null:
				_set_status("对手走了。")
		"rematch":
			# 对面想再来一局：房主主动按 R 时客机收到，客机按 R 时房主收到
			_enter_rematch()


func _lock_skill_buttons() -> void:
	for b in [skill_btn_a, skill_btn_b, skill_btn_c, skill_btn_d]:
		if b != null and is_instance_valid(b):
			b.disabled = true


func _try_start_online() -> void:
	if not GameConfig.is_host():
		return
	if my_skill == 0 or not guest_ready:
		return
	if not _net().peer_present:
		_set_status("对面还没连上 —— 等他进来再选。")
		return
	var host_side := GameConfig.player_side
	if host_side == 0:
		GameConfig.human_skill = my_skill
		GameConfig.monster_skill = peer_skill
	else:
		GameConfig.monster_skill = my_skill
		GameConfig.human_skill = peer_skill
	# 地形种子由房主定，双方用同一个种子生成同一张地图
	GameConfig.map_seed = int(randi() % 1000000000) + 1
	_net().send_msg({"t": "start", "seed": GameConfig.map_seed})
	get_tree().change_scene_to_file("res://main.tscn")
