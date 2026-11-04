// 房间码寻址探针：模拟客机的 UDP 广播，问「谁开着 XXXX」。
// 用法：node udp_who.mjs 4821
import dgram from "node:dgram";

const code = process.argv[2] || "4821";
const sock = dgram.createSocket({ type: "udp4", reuseAddr: true });
let got = false;

sock.on("message", (buf, rinfo) => {
  console.log(`回包 from ${rinfo.address}:${rinfo.port} ->`, buf.toString());
  const msg = JSON.parse(buf.toString());
  if (msg.t === "here" && msg.code === code) {
    got = true;
    console.log(`找到房主：${rinfo.address}:${msg.port}`);
    sock.close();
    process.exit(0);
  }
});

sock.bind(0, () => {
  sock.setBroadcast(true);
  const payload = Buffer.from(JSON.stringify({ t: "who", code }));
  sock.send(payload, 7789, "255.255.255.255");
  sock.send(payload, 7789, "127.0.0.1");
  console.log("已广播:", payload.toString());
});

setTimeout(() => {
  if (!got) { console.log("没有回包（房主没开 / 不在同一网段 / 端口被占）"); process.exit(2); }
}, 3000);
