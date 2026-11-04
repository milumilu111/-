// 异形入侵 —— 中转服务器
// 只做三件事：发房间号、把两个人的消息互相转过去、有人掉线时通知另一个。
// 规则不在服务器上跑：房主的 Godot 端是权威，这里不掺和游戏逻辑。
//
// 启动： node relay.mjs            （默认 0.0.0.0:7788）
// 端口： node relay.mjs 9000

import { WebSocketServer } from "ws";

const PORT = Number(process.argv[2] || 7788);
const rooms = new Map(); // code -> { host: ws, guest: ws, created: ts }

const wss = new WebSocketServer({ port: PORT, host: "0.0.0.0" });

function send(ws, obj) {
  if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function newCode() {
  for (let i = 0; i < 200; i++) {
    const c = String(Math.floor(1000 + Math.random() * 9000));
    if (!rooms.has(c)) return c;
  }
  return String(Date.now()).slice(-4);
}

function leave(ws) {
  const code = ws._room;
  if (!code || !rooms.has(code)) return;
  const room = rooms.get(code);
  if (room.host === ws) {
    send(room.guest, { t: "peer_left" });
    room.host = null;
    if (!room.guest) rooms.delete(code);
    else room.hostGone = true;
  } else if (room.guest === ws) {
    send(room.host, { t: "peer_left" });
    room.guest = null;
    if (!room.host) rooms.delete(code);
  }
  ws._room = null;
  log(`room ${code}: 有人断开，剩 ${(room.host ? 1 : 0) + (room.guest ? 1 : 0)} 人`);
}

function log(msg) {
  const t = new Date().toTimeString().slice(0, 8);
  console.log(`[${t}] ${msg}`);
}

wss.on("connection", (ws, req) => {
  ws._room = null;
  log(`连接 ${req.socket.remoteAddress}`);

  ws.on("message", (buf) => {
    let msg;
    try {
      msg = JSON.parse(buf.toString());
    } catch {
      return send(ws, { t: "error", why: "bad_json" });
    }

    switch (msg.t) {
      case "ping":
        return send(ws, { t: "pong", ts: Date.now() });

      case "create": {
        const code = newCode();
        rooms.set(code, { host: ws, guest: null, created: Date.now() });
        ws._room = code;
        log(`房间 ${code} 建立`);
        return send(ws, { t: "created", code });
      }

      case "join": {
        const code = String(msg.code || "").trim();
        const room = rooms.get(code);
        if (!room) return send(ws, { t: "error", why: "no_room", code });
        if (room.guest) return send(ws, { t: "error", why: "room_full", code });
        if (!room.host) return send(ws, { t: "error", why: "host_gone", code });
        room.guest = ws;
        ws._room = code;
        send(ws, { t: "joined", code });
        send(room.host, { t: "peer_joined", code });
        return log(`房间 ${code}: 对手加入`);
      }

      case "relay": {
        const code = ws._room;
        const room = code && rooms.get(code);
        if (!room) return send(ws, { t: "error", why: "not_in_room" });
        const other = room.host === ws ? room.guest : room.host;
        if (!other) return;
        return send(other, { t: "relay", data: msg.data });
      }

      default:
        return send(ws, { t: "error", why: "unknown_t" });
    }
  });

  ws.on("close", () => leave(ws));
  ws.on("error", () => leave(ws));
});

// 60 秒清一次空房间（都断了但没触发 close 的残留）
setInterval(() => {
  const now = Date.now();
  for (const [code, room] of rooms) {
    if (!room.host && !room.guest) {
      rooms.delete(code);
      continue;
    }
    if (now - room.created > 3 * 60 * 60 * 1000) {
      send(room.host, { t: "error", why: "room_expired" });
      send(room.guest, { t: "error", why: "room_expired" });
      rooms.delete(code);
    }
  }
}, 60000);

log(`中转服务器已启动 ws://0.0.0.0:${PORT}`);
