// 自测：模拟房主 + 加入者，检查房间号、转发、掉线通知
const URL = "ws://127.0.0.1:7788";
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

function client(name) {
  const ws = new WebSocket(URL);
  ws.inbox = [];
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    ws.inbox.push(m);
    console.log(`  ${name} <-`, JSON.stringify(m));
  };
  return new Promise((res) => (ws.onopen = () => res(ws)));
}

const a = await client("A");
a.send(JSON.stringify({ t: "create" }));
await wait(300);
const code = a.inbox.find((m) => m.t === "created")?.code;
console.log("房间号 =", code);

const b = await client("B");
b.send(JSON.stringify({ t: "join", code }));
await wait(300);

a.send(JSON.stringify({ t: "relay", data: { hello: "from A", n: 42 } }));
await wait(300);

b.send(JSON.stringify({ t: "relay", data: { hello: "from B" } }));
await wait(300);

b.close();
await wait(400);

const ok =
  code &&
  a.inbox.some((m) => m.t === "peer_joined") &&
  b.inbox.some((m) => m.t === "relay" && m.data.hello === "from A") &&
  a.inbox.some((m) => m.t === "relay" && m.data.hello === "from B") &&
  a.inbox.some((m) => m.t === "peer_left");

console.log(ok ? "PASS" : "FAIL");
a.close();
process.exit(ok ? 0 : 1);
