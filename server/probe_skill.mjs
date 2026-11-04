import WebSocket from "ws";
const url = process.argv[2] || "ws://127.0.0.1:7788";
const ws = new WebSocket(url);
ws.on("open", () => console.log("已连上"));
ws.on("message", (b) => {
  const t = b.toString();
  console.log("收到:", t);
  if (t.includes('"direct"')) { ws.send(JSON.stringify({t:"skill",s:2})); console.log("已发 skill"); }
});
setTimeout(() => process.exit(0), 40000);
