// 直连模式探针：不经过 relay，直接连房主游戏进程的 WebSocket 监听。
// 用法：node direct_probe.mjs ws://127.0.0.1:7788
import { WebSocket } from "ws";

const url = process.argv[2] || "ws://127.0.0.1:7788";
const ws = new WebSocket(url);
let greeted = false;

ws.on("open", () => console.log("连接建立", url));
ws.on("message", (buf) => {
  const txt = buf.toString();
  console.log("收到:", txt);
  const msg = JSON.parse(txt);
  if (msg.t === "direct" && !greeted) {
    greeted = true;
    console.log("握手成功 —— 对面是游戏本机（直连）");
    ws.send(JSON.stringify({ t: "roles", side: 0 }));
    ws.send(JSON.stringify({ t: "skill", s: 1 }));
  }
});
ws.on("error", (e) => { console.log("错误:", e.message); process.exit(1); });
setTimeout(() => { console.log("结束"); ws.close(); process.exit(0); }, 30000);
