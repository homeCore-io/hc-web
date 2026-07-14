// Screenshot a page of the running hc-web, waiting in REAL time.
//
//   node tool/shot.mjs '/#/devices' out.png [--wait 10000] [--size 1600,1000]
//
// Why not `chromium --screenshot --virtual-time-budget=N`, which is the usual
// trick for a canvas app: virtual time fast-forwards the page's CLOCK, but an
// HTTP response still arrives in real wall-clock time. So the capture can fire
// before the API call lands, and you get a screenshot of the app's loading
// state that looks exactly like a bug — I chased a phantom "0 Devices against a
// house with 167" for a while before realising the screenshot, not the app, was
// lying. Waiting for real time and idle network is slower and honest.
//
// Flutter web paints into a <canvas>, so there is no DOM to wait on: no
// networkidle heuristic from the DOM side, no selector to await. We wait for the
// API calls to go quiet, then give the engine a beat to paint.
import {spawn} from 'node:child_process';
import {writeFileSync} from 'node:fs';

const arg = (n, d) => {
  const i = process.argv.indexOf(`--${n}`);
  return i > 0 ? process.argv[i + 1] : d;
};

const route = process.argv[2] ?? '/#/';
const out = process.argv[3] ?? 'shot.png';
const BASE = process.env.BASE ?? 'http://localhost:3000';
const PROFILE = process.env.PROFILE ?? '/tmp/hc-web-profile';
const [W, H] = arg('size', '1600,1000').split(',').map(Number);
const SETTLE = Number(arg('wait', '4000'));
const PORT = 9224;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const chrome = spawn('chromium', [
  '--headless', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
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
let inflight = 0;
let lastActivity = Date.now();

ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) {
    const {resolve} = pending.get(m.id);
    pending.delete(m.id);
    resolve(m.result);
    return;
  }
  // Track only API traffic: canvaskit.wasm and fonts finish early and would
  // otherwise declare the page "idle" long before the house has loaded.
  if (m.method === 'Network.requestWillBeSent' &&
      m.params.request.url.includes('/api/')) {
    inflight++;
    lastActivity = Date.now();
  }
  if ((m.method === 'Network.loadingFinished' ||
       m.method === 'Network.loadingFailed') && inflight > 0) {
    inflight--;
    lastActivity = Date.now();
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

// Evict the Flutter service worker and its asset cache before every shot.
//
// The profile is reused across runs to keep the login session, and that means it
// also keeps the service worker. nginx sends no-cache for index.html and
// main.dart.js, so the CODE updates — but the SW serves ASSETS (fonts, wasm)
// from its own cache. The result is a new app running against an old font: I
// added an icon, the new main.dart.js asked for its codepoint, the stale
// tree-shaken Phosphor.ttf did not contain it, and the icon silently rendered as
// nothing. I "fixed" that phantom twice before spotting it.
//
// Only service_workers + cache_storage are cleared. NOT local_storage, which is
// where the session token lives.
await send('Storage.clearDataForOrigin', {
  origin: BASE,
  storageTypes: 'service_workers,cache_storage',
});
await send('Network.setCacheDisabled', {cacheDisabled: true});
// Pin the viewport: --window-size alone is not honoured reliably in headless,
// and a screenshot at the wrong size makes every coordinate in it a lie.
await send('Emulation.setDeviceMetricsOverride',
    {width: W, height: H, deviceScaleFactor: 1, mobile: false});

await send('Page.navigate', {url: BASE + route});

// Wait for the API to go quiet, then let the engine paint.
const deadline = Date.now() + 30000;
while (Date.now() < deadline) {
  await sleep(250);
  if (inflight === 0 && Date.now() - lastActivity > 1500) break;
}
await sleep(SETTLE);

// Optional click before capturing — for things that are not routes.
// A sheet, a menu, a palette: they are STATE, not URLs, so the only way to see
// one is to open it. There is no DOM to query, so the click is a coordinate.
const click = arg('click', null);
if (click) {
  const [cx, cy] = click.split(',').map(Number);
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent',
        {type, x: cx, y: cy, button: 'left', clickCount: 1});
  }
  await sleep(1200); // let the sheet finish sliding in
}

const {data} = await send('Page.captureScreenshot', {format: 'png'});
writeFileSync(out, Buffer.from(data, 'base64'));
console.log(out);

ws.close();
chrome.kill();
process.exit(0);
