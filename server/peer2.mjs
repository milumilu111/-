// 假异形：进房、选阵营、按房主给的回合自己走几步再交回。
// 用法： node peer2.mjs <房间号> [技能]
const code = process.argv[2];
const skill = Number(process.argv[3] || 2);

const ws = new WebSocket("ws://127.0.0.1:7788");
const log = (...a) => console.log("[peer]", ...a);
let pos = [9, 9];
let steps = 0;
let busy = false;

const send = (data) => ws.send(JSON.stringify({ t: "relay", data }));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

ws.onopen = () => ws.send(JSON.stringify({ t: "join", code }));

async function takeTurn() {
  if (busy) return;
  busy = true;
  for (let i = 0; i < steps; i++) {
    // 朝 (0,0) 小步挪：先 x 后 y
    const cands = [];
    if (pos[0] > 0) cands.push([pos[0] - 1, pos[1]]);
    if (pos[1] > 0) cands.push([pos[0], pos[1] - 1]);
    const c = cands[0];
    if (!c) break;
    send({ t: "cmd", a: "move", c });
    pos = c;
    await sleep(700);
  }
  await sleep(400);
  send({ t: "cmd", a: "end" });
  busy = false;
}

ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.t === "joined") log("进房", code);
  if (m.t !== "relay" || !m.data) return;
  const d = m.data;
  if (d.t === "roles") {
    setTimeout(() => send({ t: "skill", s: skill }), 400);
  }
  if (d.t === "snap") {
    pos = [d.pos[0], d.pos[1]];
    steps = d.steps;
    log(
      `快照 回合${d.round} 步数${d.steps} 轮到${Number(d.turn) === 0 ? "人类" : "异形"} ` +
        `探查${d.probes} 雷${(d.mines || []).length} 位置(${pos}) ${d.text}`
    );
    if (Number(d.turn) === 1 && !busy) takeTurn();
  }
};

ws.onclose = () => log("断开");
setTimeout(() => process.exit(0), 180000);
