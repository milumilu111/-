// 假房主：UDP 应答房间码 + 在本机 7900 开一个 WebSocket 服务器。
// 用来验证「客机只知道房间号」这条路径。
// 用法：node fake_host.mjs 4821
import dgram from "node:dgram";
import { WebSocketServer } from "ws";

const code = process.argv[2] || "4821";
const WS_PORT = 7900;

const udp = dgram.createSocket({ type: "udp4", reuseAddr: true });
udp.on("message", (buf, rinfo) => {
  let msg;
  try { msg = JSON.parse(buf.toString()); } catch { return; }
  console.log(`UDP from ${rinfo.address}:${rinfo.port}`, msg);
  if (msg.t === "who" && msg.code === code) {
    const reply = Buffer.from(JSON.stringify({ t: "here", code, port: WS_PORT }));
    udp.send(reply, rinfo.port, rinfo.address);
    console.log("已回 here");
  }
});
udp.bind(7789, () => console.log("UDP 7789 就绪，房间号", code));

const wss = new WebSocketServer({ port: WS_PORT, host: "0.0.0.0" });
wss.on("connection", (ws) => {
  console.log("客机连上来了");
  ws.send(JSON.stringify({ t: "direct" }));
  ws.on("message", (b) => console.log("收到:", b.toString()));
});
wss.on("listening", () => console.log("WS", WS_PORT, "就绪"));

setTimeout(() => { console.log("结束"); process.exit(0); }, 20000);
