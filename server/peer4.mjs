// 假人类（客机）：进房、选技能、开始后每轮查一格，用来检查快照里有没有泄题字段。
// 用法： node peer4.mjs <房间号> [技能]
const code = process.argv[2];
const skill = Number(process.argv[3] || 2);
const ws = new WebSocket("ws://127.0.0.1:7788");
const send = (d) => ws.send(JSON.stringify({ t: "relay", data: d }));
let probed = 0;
const cells = [[3, 3], [4, 4], [6, 6], [2, 7], [7, 2], [5, 1]];

ws.onopen = () => ws.send(JSON.stringify({ t: "join", code }));
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.t !== "relay" || !m.data) return;
  const d = m.data;
  if (d.t === "roles") {
    setTimeout(() => send({ t: "skill", s: skill }), 300);
    // 人类这边布防（地雷师）就随便点两下交差，重点是 turn/快照
    setTimeout(() => send({ t: "cmd", a: "deploy_done" }), 1200);
  }
  if (d.t === "snap") {
    const leak = ["steps", "hp", "leap", "stun", "opening"].filter((k) => k in d);
    console.log(
      `[guest] round=${d.round} turn=${d.turn} text="${d.text}" 泄题字段=${leak.length ? leak.join(",") : "无"}`
    );
    if (Number(d.turn) === 0) {
      const c = cells[probed % cells.length];
      probed++;
      setTimeout(() => send({ t: "cmd", a: "probe", c }), 700);
    }
  }
  if (d.t === "probe_result") {
    console.log(`[guest] 探测结果 cell=(${d.c}) r=${d.r}`);
  }
  if (d.t === "need_deploy") {
    console.log("[guest] 房主在问我布防好了没 —— 回一遍");
    send({ t: "cmd", a: "deploy_done" });
  }
};
ws.onclose = () => console.log("[guest] 断开");
setTimeout(() => process.exit(0), 120000);
