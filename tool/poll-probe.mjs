// Prove the plugins page updates itself: open it, change a plugin's state
// behind the app's back, and capture before/after WITHOUT reloading.
//
//   PROFILE=… BASE=… node tool/poll-probe.mjs before.png after.png \
//     --mutate 'http://127.0.0.1:8080/api/v1/plugins/plugin.wled/stop' --dwell 30000
//
// Also logs every GET /plugins the page makes, with the gap between them, so a
// screenshot that happens to look right cannot be mistaken for a page that is
// actually polling.
import {spawn} from 'node:child_process';
import {writeFileSync} from 'node:fs';

const arg = (n, d) => {
  const i = process.argv.indexOf(`--${n}`);
  return i > 0 ? process.argv[i + 1] : d;
};

const before = process.argv[2] ?? 'before.png';
const after = process.argv[3] ?? 'after.png';
const BASE = process.env.BASE ?? 'http://localhost:3000';
const PROFILE = process.env.PROFILE ?? '/tmp/hc-web-profile';
const [W, H] = arg('size', '1500,1000').split(',').map(Number);
const DWELL = Number(arg('dwell', '30000'));
const MUTATE = arg('mutate', null);
const PORT = 9227;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const chrome = spawn('chromium', [
  '--headless', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
  '--enable-unsafe-swiftshader',
  `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${PROFILE}`,
  `--window-size=${W},${H}`,
  'about:blank',
], {stdio: 'ignore'});
process.on('exit', () => chrome.kill());

let target;
for (let i = 0; i < 80; i++) {
  try {
    const r = await fetch(`http://127.0.0.1:${PORT}/json/list`);
    const pages = (await r.json()).filter((t) => t.type === 'page');
    if (pages.length) { target = pages[0]; break; }
  } catch { /* not up yet */ }
  await sleep(250);
}
if (!target) throw new Error('no debug target');

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

let id = 0;
const pending = new Map();
const polls = [];
const t0 = Date.now();

ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) {
    const {resolve} = pending.get(m.id);
    pending.delete(m.id);
    resolve(m.result);
    return;
  }
  if (m.method === 'Network.requestWillBeSent') {
    const u = m.params.request.url;
    // The list endpoint only — not /plugins/:id/config and friends.
    if (/\/api\/v1\/plugins(\?|$)/.test(u)) polls.push(Date.now() - t0);
  }
};

const send = (method, params = {}) =>
  new Promise((resolve) => {
    const n = ++id;
    pending.set(n, {resolve});
    ws.send(JSON.stringify({id: n, method, params}));
  });

await send('Network.enable');
await send('Page.enable');
await send('Storage.clearDataForOrigin',
    {origin: BASE, storageTypes: 'service_workers,cache_storage'});
await send('Network.setCacheDisabled', {cacheDisabled: true});
await send('Emulation.setDeviceMetricsOverride',
    {width: W, height: H, deviceScaleFactor: 1, mobile: false});

await send('Page.navigate', {url: `${BASE}/#/plugins`});
await sleep(9000);

const shot = async (path) => {
  const {data} = await send('Page.captureScreenshot', {format: 'png'});
  writeFileSync(path, Buffer.from(data, 'base64'));
  console.log(path);
};

await shot(before);
const pollsAtBefore = polls.length;

if (MUTATE) {
  const r = await fetch(MUTATE, {method: 'POST'});
  console.log(`mutate ${MUTATE} -> ${r.status}`);
}

// Sit here. No reload, no navigation, no interaction — anything that changes
// on screen from here can only have come from the page refetching on its own.
await sleep(DWELL);
await shot(after);

console.log(`GET /plugins at ms: ${polls.join(', ')}`);
console.log(`polls before capture 1: ${pollsAtBefore}, during dwell: ${
    polls.length - pollsAtBefore}`);

ws.close();
chrome.kill();
process.exit(0);
