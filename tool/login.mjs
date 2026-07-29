// Seed a Chromium profile with a logged-in hc-web session, so screenshots show
// the app instead of its login page.
//
//   node tool/login.mjs [--base http://localhost:3000] [--user admin] [--pass password]
//
// It gets a JWT from the API and writes it where the app looks for it, rather
// than driving the login form. Driving the form means clicking pixel
// coordinates, because Flutter web paints the entire UI into one <canvas> and
// there is no DOM to select — I tried, and a few pixels off put "admin" in the
// password box and left the username empty.
//
// The storage format is not guessed. shared_preferences_web (2.4.3) defines it:
//
//     static const String _defaultPrefix = 'flutter.';
//     String _encodeValue(Object? value) => json.encode(value);
//
// so a String lands in localStorage as `flutter.<key>` → a JSON-encoded (i.e.
// double-quoted) string. Miss either half and the app just shows the login page
// again, with nothing anywhere saying why.
//
// Node 26 has a global WebSocket and fetch, so this needs no dependencies.
import {spawn} from 'node:child_process';
import {mkdirSync} from 'node:fs';

const arg = (n, d) => {
  const i = process.argv.indexOf(`--${n}`);
  return i > 0 ? process.argv[i + 1] : d;
};

const BASE = arg('base', 'http://localhost:3000');
const PROFILE = arg('profile', '/tmp/hc-web-profile');
const USER = arg('user', 'admin');
const PASS = arg('pass', 'password');
const PORT = 9222;

// Must match HomecoreClient._tokenKey in lib/core/api/homecore_client.dart.
const TOKEN_KEY = 'flutter.jwt_token';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 1. A real token from the real core.
const res = await fetch(`${BASE}/api/v1/auth/login`, {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({username: USER, password: PASS}),
});
if (!res.ok) {
  console.error(`login failed: HTTP ${res.status} ${await res.text()}`);
  process.exit(1);
}
const {token} = await res.json();
if (!token) {
  console.error('login returned no token');
  process.exit(1);
}

// 2. A profile that will remember it.
mkdirSync(PROFILE, {recursive: true});
const chrome = spawn('chromium', [
  '--headless',
  '--disable-gpu',
  '--no-sandbox',
  '--hide-scrollbars',
  `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${PROFILE}`,
  '--window-size=1600,1000',
  'about:blank',
], {stdio: 'ignore'});
process.on('exit', () => chrome.kill());

let target;
for (let i = 0; i < 80; i++) {
  try {
    const r = await fetch(`http://127.0.0.1:${PORT}/json/list`);
    const pages = (await r.json()).filter((t) => t.type === 'page');
    if (pages.length) { target = pages[0]; break; }
  } catch { /* debug port not listening yet */ }
  await sleep(250);
}
if (!target) throw new Error('chromium never exposed a debug target');

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

let id = 0;
const pending = new Map();
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) {
    const {resolve, reject} = pending.get(m.id);
    pending.delete(m.id);
    m.error ? reject(new Error(JSON.stringify(m.error))) : resolve(m.result);
  }
};
const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const n = ++id;
    pending.set(n, {resolve, reject});
    ws.send(JSON.stringify({id: n, method, params}));
  });

await send('Page.enable');
await send('Runtime.enable');

// 3. localStorage is per-origin, so the origin has to exist before we can write
//    to it. Load the app once (it will bounce to /login — that is fine).
await send('Page.navigate', {url: BASE});
await sleep(6000);

const {result} = await send('Runtime.evaluate', {
  expression: `localStorage.setItem(${JSON.stringify(TOKEN_KEY)}, ${
      JSON.stringify(JSON.stringify(token))}); localStorage.getItem(${
      JSON.stringify(TOKEN_KEY)}) ? 'ok' : 'failed'`,
  returnByValue: true,
});
if (result.value !== 'ok') {
  console.error('could not write the token to localStorage');
  process.exit(1);
}

// 4. Reload so the app boots WITH the token, and confirm it actually got past
//    the login page. Writing the key is not evidence that the app accepted it.
await send('Page.reload');
await sleep(9000);

const {result: stillLogin} = await send('Runtime.evaluate', {
  expression: `localStorage.getItem(${JSON.stringify(TOKEN_KEY)}) === null`,
  returnByValue: true,
});
if (stillLogin.value) {
  console.error('the app cleared the token — core rejected it');
  process.exit(1);
}

// 5. Close the BROWSER, do not kill it. localStorage lives in a LevelDB that is
//    flushed on clean shutdown; SIGKILL right after the write loses it, and the
//    next run silently gets the login page again. This cost me a debug cycle.
await send('Browser.close').catch(() => {});
ws.close();
await sleep(1500);
console.log(`session seeded in ${PROFILE}`);
console.log(`  ${TOKEN_KEY} = "${token.slice(0, 20)}…"`);
console.log(`now: tool/shot.sh /automations shot.png`);
