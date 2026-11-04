// 假房主：建房、等客机、走完选人流程，然后定期下发快照 —— 用来单独测客机那一半。
// 用法： node host.mjs [技能]
const skill = Number(process.argv[2] || 2);
const ws = new WebSocket("ws://127.0.0.1:7788");
const log = (...a) => console.log("[host]", ...a);
const send = (data) => ws.send(JSON.stringify({ t: "relay", data }));
let started = false;

ws.onopen = () => ws.send(JSON.stringify({ t: "create" }));

function snapshot(i) {
  send({
    t: "snap",
    round: 3 + i,
    probes: 2 + i,
    steps: 3,
    opening: false,
    hp: 1,
    ended: false,
    win: false,
    text: `他查了 (${4 + i},6) —— 有脚印。`,
    marks: [[4, 6, 1], [8, 8, 0]],
    walls: [[2, 4], [2, 5]],
    mines: [[6, 6]],
    perm: [[9, 9], [8, 9], [7, 9]],
    pos: [7, 9],
    turn: 1,
    title: "",
  });
}

ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.t === "created") log("房间号", m.code, "——— 让客机用这个号进来");
  if (m.t === "peer_joined") {
    log("客机进来了，发 roles（我坐人类）");
    setTimeout(() => send({ t: "roles", side: 0 }), 800);
  }
  if (m.t !== "relay" || !m.data) return;
  const d = m.data;
  if (d.t === "skill") {
    log("客机技能 =", d.s);
    if (!started) {
      started = true;
      setTimeout(() => {
        send({ t: "start" });
        log("已发 start");
        let i = 0;
        setInterval(() => {
          if (i > 2) return;
          snapshot(i);
          log("下发快照", i);
          i++;
        }, 4000);
      }, 600);
    }
  }
};

ws.onclose = () => log("断开");
setTimeout(() => process.exit(0), 240000);
