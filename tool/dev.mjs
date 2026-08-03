// A dev server for hc-web: hot restart, and a same-origin API.
//
//   node tool/dev.mjs                       # -> http://localhost:3001, sandbox API
//   HOMECORE_URL=http://10.0.10.150:8080 node tool/dev.mjs   # the real house
//
// Then, in another terminal:
//   flutter run -d web-server --web-port 5001 --web-hostname 127.0.0.1
//
// ...and press `R` to hot-restart. Seconds, not a four-minute image build.
//
// WHY THIS EXISTS AT ALL. The app calls `/api/v1` RELATIVELY, on purpose: one
// build artifact runs anywhere, with no build-time config and no CORS. Core
// sends no CORS headers whatsoever, so a browser simply cannot call it
// cross-origin — something has to make the API same-origin with the app. In
// production that is the nginx inside the container. For development that was
// ALSO the container, which meant rebuilding an image to see a one-line change.
//
// This is the same job in 60 lines: serve the app from Flutter's dev server
// (which does the incremental compile) and proxy /api/v1 to a real homeCore.
//
// WebSockets are proxied too, because without them the app loads and then shows
// stale state forever: /api/v1/events/stream is how it learns the house changed.
import http from 'node:http';
import net from 'node:net';
import {URL} from 'node:url';

const PORT = Number(process.env.PORT ?? 3001);
const FLUTTER = process.env.FLUTTER_URL ?? 'http://127.0.0.1:5001';

// The sandbox, not the house.
//
// This defaulted to http://10.0.10.150:8080 — the live install — so a bare
// `node tool/dev.mjs` served the real house behind a localhost URL, looking
// exactly like a local dev session. The tell was almost nothing: the sandbox
// and live report the same version string, so the page looks identical until
// something you click changes a real light. It cost an afternoon once by
// silently rejecting the sandbox's admin password against live, which reads as
// "the password is broken" rather than "you are on the wrong machine".
//
// Reaching production should be a thing you type, not a thing you forget.
const CORE = process.env.HOMECORE_URL ?? 'http://127.0.0.1:8080';

/// Anything not on this machine is somebody's real house until proven otherwise.
const isLocal = (() => {
  const h = new URL(CORE).hostname;
  return h === '127.0.0.1' || h === 'localhost' || h === '::1' || h === '[::1]';
})();

const target = (req) =>
    req.url.startsWith('/api/') ? new URL(CORE) : new URL(FLUTTER);

const server = http.createServer((req, res) => {
  const t = target(req);
  const proxied = http.request(
      {
        hostname: t.hostname,
        port: t.port || 80,
        path: req.url,
        method: req.method,
        headers: {...req.headers, host: t.host},
      },
      (upstream) => {
        res.writeHead(upstream.statusCode ?? 502, upstream.headers);
        upstream.pipe(res);
      });

  proxied.on('error', (e) => {
    res.writeHead(502, {'content-type': 'text/plain'});
    res.end(
        req.url.startsWith('/api/')
            ? `cannot reach homeCore at ${CORE}: ${e.message}\n`
            : `cannot reach the Flutter dev server at ${FLUTTER}: ${e.message}\n` +
                `start it with:\n` +
                `  flutter run -d web-server --web-port 5001 --web-hostname 127.0.0.1\n`);
  });

  req.pipe(proxied);
});

// The event stream is a WebSocket, and an upgrade is hop-by-hop: it has to be
// forwarded at the socket level, not as an HTTP response.
server.on('upgrade', (req, socket, head) => {
  const t = target(req);
  const upstream = net.connect(Number(t.port) || 80, t.hostname, () => {
    upstream.write(
        `GET ${req.url} HTTP/1.1\r\n` +
        Object.entries({...req.headers, host: t.host})
            .map(([k, v]) => `${k}: ${v}\r\n`)
            .join('') +
        '\r\n');
    if (head?.length) upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  upstream.on('error', () => socket.destroy());
  socket.on('error', () => upstream.destroy());
});

server.listen(PORT, () => {
  console.log(`hc-web dev  →  http://localhost:${PORT}`);
  console.log(`  app  ${FLUTTER}`);
  // Say it loudly when it is not the sandbox. A localhost address in the
  // browser is not evidence of a local backend, and every control on the page
  // is live.
  console.log(
      isLocal ? `  api  ${CORE}` :
                `  api  ${CORE}   ⚠  NOT LOCAL — commands here change real devices`);
  console.log(`\nstart the app with:`);
  console.log(
      `  flutter run -d web-server --web-port 5001 --web-hostname 127.0.0.1`);
});
