extends Node
# 联机连接层。两种跑法：
#   ① 直连（默认）：房主的游戏进程自己开监听，客机直接连过来 —— 局域网/虚拟局域网用这个，不需要外面那个 relay。
#   ② 中转：两边都连 server/relay.mjs，由它配对转发 —— 跨公网时才需要。
# 规则不在这里 —— 房主那一端是权威，guest 只发指令、收快照。

signal state_changed                    # 连接状态变了（0 未连 / 1 连接中 / 2 已连）
signal room_created(code: String)       # 房主：房间开好了（直连时 code 是端口号）
signal room_joined(code: String)        # 加入者：进去了
signal peer_joined                      # 对手来了
signal peer_left                        # 对手走了
signal message(data: Dictionary)        # 对手发来的业务消息
signal net_error(code: String)          # 错误

const DEFAULT_URL := "ws://127.0.0.1:7788"
const STATE_IDLE := 0
const STATE_CONNECTING := 1
const STATE_OPEN := 2
const DEFAULT_PORT := 7788

var ws: WebSocketPeer = null
var tcp := TCPServer.new()              # 只有房主用：本机的监听
var status := STATE_IDLE
var room_code := ""
var is_host := false
var peer_present := false
var server_url := DEFAULT_URL
var last_error := ""
var direct := false                     # 直连模式（房主监听 / 客机直连房主）
var listen_port := DEFAULT_PORT
var _greeted := false

# 房间码寻址：局域网/虚拟局域网里用 UDP 广播问一句「谁开着 4821 这间房」
const DISCOVERY_PORT := 7789
var udp := PacketPeerUDP.new()
var _want_code := ""                    # 客机：正在找的房间号
var _discovery_deadline := 0            # 客机：找房的截止时间（毫秒）
var find_ip := ""


func _ready() -> void:
	set_process(true)
	# 跨场景存活
	process_mode = Node.PROCESS_MODE_ALWAYS


# ---------------------------------------------------------------- 直连

func host(port: int = DEFAULT_PORT) -> void:
	close()
	listen_port = port
	var err := tcp.listen(port, "*")
	if err != OK:
		last_error = "listen_failed"
		status = STATE_IDLE
		state_changed.emit()
		net_error.emit(last_error)
		return
	is_host = true
	direct = true
	_greeted = false
	status = STATE_OPEN
	# 房间号：4 位随机，给对面念的数字，同时用于局域网广播寻址
	room_code = str(randi() % 9000 + 1000)
	_start_discovery_listen()
	state_changed.emit()
	room_created.emit(room_code)


# 客机：只知道房间号，先在局域网里广播问一句，谁答应了就连谁
func join_by_code(code: String) -> void:
	close()
	is_host = false
	direct = false
	_want_code = code.strip_edges()
	find_ip = ""
	udp.close()
	udp.set_broadcast_enabled(true)
	var err := udp.bind(0)                # 随便给个本地端口，回包会送到这儿
	if err != OK:
		last_error = "discovery_failed"
		net_error.emit(last_error)
		return
	_discovery_deadline = Time.get_ticks_msec() + 2600
	_broadcast_who()


func _broadcast_who() -> void:
	if _want_code == "":
		return
	var msg := JSON.stringify({"t": "who", "code": _want_code}).to_utf8_buffer()
	var sent := {}
	# 每个网卡各发一份子网广播 —— 机器上常有 Wi-Fi + 虚拟网卡同时开着，只发 255.255.255.255 可能从错的出口出去
	for a in IP.get_local_addresses():
		var s := String(a)
		if not s.contains(".") or s.begins_with("127."):
			continue
		var parts := s.split(".")
		if parts.size() != 4:
			continue
		var bcast := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if sent.has(bcast):
			continue
		sent[bcast] = true
		udp.set_dest_address(bcast, DISCOVERY_PORT)
		udp.put_packet(msg)
	udp.set_dest_address("127.0.0.1", DISCOVERY_PORT)   # 本机双开也能找到
	udp.put_packet(msg)


func _start_discovery_listen() -> void:
	udp.close()
	udp.set_broadcast_enabled(true)
	udp.bind(DISCOVERY_PORT)              # 失败就算了，还能用 IP 直连


func join_direct(url: String) -> void:
	close()
	direct = false                       # 等对面握过手才置 true
	is_host = false
	connect_to(url)


# ---------------------------------------------------------------- 中转

func connect_to(url: String) -> void:
	if ws != null:
		ws.close()
		ws = null
	server_url = url if url.strip_edges() != "" else DEFAULT_URL
	ws = WebSocketPeer.new()
	var err := ws.connect_to_url(server_url)
	if err != OK:
		last_error = "connect_failed"
		status = STATE_IDLE
		state_changed.emit()
		net_error.emit(last_error)
		return
	status = STATE_CONNECTING
	state_changed.emit()


func create_room() -> void:
	is_host = true
	direct = false
	_send({"t": "create"})


func join_room(code: String) -> void:
	is_host = false
	direct = false
	_send({"t": "join", "code": code.strip_edges()})


# ---------------------------------------------------------------- 收发

func send_msg(data: Dictionary) -> void:
	if direct:
		_send(data)                      # 直连：业务消息就是消息本体
	else:
		_send({"t": "relay", "data": data})


func is_online() -> bool:
	return status == STATE_OPEN


func close() -> void:
	if tcp.is_listening():
		tcp.stop()
	if udp != null:
		udp.close()
	_want_code = ""
	_discovery_deadline = 0
	if ws != null:
		ws.close()
	ws = null
	status = STATE_IDLE
	room_code = ""
	peer_present = false
	direct = false
	_greeted = false
	state_changed.emit()


func _send(obj: Dictionary) -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	ws.send_text(JSON.stringify(obj))


func _process(_delta: float) -> void:
	_tick_discovery()
	# 房主：把进来的 TCP 连接升成 WebSocket
	if tcp.is_listening() and ws == null and tcp.is_connection_available():
		var conn := tcp.take_connection()
		ws = WebSocketPeer.new()
		ws.accept_stream(conn)
		_greeted = false
		status = STATE_CONNECTING
		state_changed.emit()

	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_CLOSED:
		if is_host and tcp.is_listening():
			# 房主：对手断了但要继续等人进来
			ws = null
			_greeted = false
			peer_present = false
			status = STATE_OPEN
			state_changed.emit()
			peer_left.emit()
			return
		if status != STATE_IDLE:
			status = STATE_IDLE
			peer_present = false
			state_changed.emit()
			peer_left.emit()
		ws = null
		return
	if st == WebSocketPeer.STATE_OPEN:
		if status != STATE_OPEN and not is_host:
			status = STATE_OPEN
			state_changed.emit()
		if not _greeted:
			# 握手：房主自报家门，客机靠这一句认出「对面是游戏本机，不是中转服务器」
			_greeted = true
			status = STATE_OPEN              # 握手完成才算真的在线（房主接进连接时状态被置成 CONNECTING 过）
			state_changed.emit()
			if is_host:
				_send({"t": "direct"})
				peer_present = true
				peer_joined.emit()
	while ws != null and ws.get_available_packet_count() > 0:
		var txt := ws.get_packet().get_string_from_utf8()
		_handle(txt)


func _handle(txt: String) -> void:
	var msg = JSON.parse_string(txt)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match String(msg.get("t", "")):
		"direct":
			if not is_host:
				direct = true
				room_code = "直连"
				peer_present = true
				status = STATE_OPEN
				state_changed.emit()
				room_joined.emit(room_code)
		"created":
			room_code = String(msg.get("code", ""))
			room_created.emit(room_code)
		"joined":
			room_code = String(msg.get("code", ""))
			peer_present = true
			room_joined.emit(room_code)
		"peer_joined":
			peer_present = true
			peer_joined.emit()
		"peer_left":
			peer_present = false
			peer_left.emit()
		"relay":
			var d = msg.get("data", {})
			if typeof(d) == TYPE_DICTIONARY:
				message.emit(d)
		"error":
			last_error = String(msg.get("why", "unknown"))
			net_error.emit(last_error)
		_:
			# 直连时对面发来的就是业务消息本体
			if direct:
				message.emit(msg)


# ---------------------------------------------------------------- 房间码寻址

func _tick_discovery() -> void:
	# 房主：听到「谁开着 XXXX」，号码对上就回一句「我这儿」
	# 客机：听到「我这儿」，连过去
	if udp == null:
		return
	while udp.get_available_packet_count() > 0:
		var txt := udp.get_packet().get_string_from_utf8()
		var from_ip := udp.get_packet_ip()
		var from_port := udp.get_packet_port()
		var msg = JSON.parse_string(txt)
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		var t := String(msg.get("t", ""))
		if t == "who" and is_host and String(msg.get("code", "")) == room_code:
			var reply := JSON.stringify({"t": "here", "code": room_code, "port": listen_port})
			udp.set_dest_address(from_ip, from_port)
			udp.put_packet(reply.to_utf8_buffer())
		elif t == "here" and _want_code != "" and String(msg.get("code", "")) == _want_code:
			var ip := from_ip
			if ip == "" or ip.begins_with("0."):
				ip = "127.0.0.1"
			find_ip = ip
			var port := int(msg.get("port", DEFAULT_PORT))
			_want_code = ""
			_discovery_deadline = 0
			udp.close()
			join_direct("ws://%s:%d" % [ip, port])
			return
	if _want_code != "" and _discovery_deadline > 0 and Time.get_ticks_msec() > _discovery_deadline:
		_want_code = ""
		_discovery_deadline = 0
		last_error = "room_not_found"
		net_error.emit(last_error)
	elif _want_code != "" and _discovery_deadline > 0 and (Time.get_ticks_msec() % 900) < 20:
		_broadcast_who()


# ---------------------------------------------------------------- 给菜单用的本机地址

func local_ipv4() -> String:
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.contains(".") and not s.begins_with("127.") and not s.begins_with("169.254."):
			return s
	return "127.0.0.1"
