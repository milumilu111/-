// 假对手：加入房间，按房主的消息自动应答，用来在没有第二个窗口时测联机。
// 用法： node peer.mjs 1860 [技能 1|2] [阵营 human|monster]
const code = process.argv[2];
const skill = Number(process.argv[3] || 2);
const prefer = process.argv[4] || "human";

const ws = new WebSocket("ws://127.0.0.1:7788");
const log = (...a) => console.log("[peer]", ...a);

ws.onopen = () => ws.send(JSON.stringify({ t: "join", code }));

ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  log("<-", JSON.stringify(m).slice(0, 300));
  if (m.t === "joined") log("进房成功，等房主选阵营");
  if (m.t === "relay" && m.data) {
    const d = m.data;
    if (d.t === "roles") {
      const host = Number(d.side);
      const mine = host === 0 ? 1 : 0;
      log("房主坐", host === 0 ? "人类" : "异形", "→ 我坐", mine === 0 ? "人类" : "异形");
      setTimeout(() => ws.send(JSON.stringify({ t: "relay", data: { t: "skill", s: skill } })), 400);
    }
    if (d.t === "turn") log("轮到", Number(d.who) === 0 ? "人类" : "异形");
    if (d.t === "snap") {
      log(
        "快照 回合", d.round, "· 探查", d.probes, "· 步数", d.steps,
        "· 轮到", Number(d.turn) === 0 ? "人类" : "异形",
        "· 墙", (d.walls || []).length, "· 雷", (d.mines || []).length,
        "· 脚印", (d.perm || []).length
      );
    }
  }
};

ws.onclose = () => log("断开");
setTimeout(() => process.exit(0), 120000);
