// Dump the browser console + uncaught exceptions for a page of the running app.
//
//   node tool/console.mjs '/#/'            # what is the blank dashboard saying?
//   node tool/console.mjs '/#/automations'
//
// Flutter web swallows a lot: a widget that throws during build renders as
// nothing (or a red box in debug, which release strips), so a blank page and a
// working-but-empty page look identical from a screenshot. The console is where
// the difference lives.
import {spawn} from 'node:child_process';

const route = process.argv[2] ?? '/#/';
const BASE = process.env.BASE ?? 'http://localhost:3000';
const PROFILE = process.env.PROFILE ?? '/tmp/hc-web-profile';
const PORT = 9223;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const chrome = spawn('chromium', [
  '--headless', '--disable-gpu', '--no-sandbox',
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
  } catch { /* not up yet */ }
  await sleep(250);
}
if (!target) throw new Error('no debug target');

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

let id = 0;
const send = (method, params = {}) =>
    new Promise((r) => { ws.send(JSON.stringify({id: ++id, method, params})); r(); });

ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.method === 'Runtime.consoleAPICalled') {
    const text = m.params.args
        .map((a) => a.value ?? a.description ?? a.type).join(' ');
    console.log(`[${m.params.type}] ${text}`);
  }
  if (m.method === 'Runtime.exceptionThrown') {
    const d = m.params.exceptionDetails;
    console.log(`[EXCEPTION] ${d.exception?.description ?? d.text}`);
  }
  if (m.method === 'Log.entryAdded') {
    const {level, text, url} = m.params.entry;
    console.log(`[${level}] ${text}${url ? ` (${url})` : ''}`);
  }
};

ws.addEventListener('message', (e) => {
  const m = JSON.parse(e.data);
  if (m.method === 'Network.responseReceived') {
    const {url, status} = m.params.response;
    if (url.includes('/api/')) console.log(`[net] ${status} ${url}`);
  }
  if (m.method === 'Network.loadingFailed') {
    console.log(`[net FAILED] ${m.params.errorText}`);
  }
});

await send('Runtime.enable');
await send('Log.enable');
await send('Network.enable');
await send('Page.enable');
await send('Page.navigate', {url: BASE + route});

await sleep(12000);
console.log('--- end ---');
ws.close();
chrome.kill();
process.exit(0);
