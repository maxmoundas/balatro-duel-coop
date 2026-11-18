'use strict';

// Standalone TCP relay server (optional: players can also host from inside the game).
// Protocol: one JSON object per line. All game rules live in the mod's relay.lua.

const net = require('net');
const { RelayHost } = require('./relay-host');

const MAX_LINE = 512 * 1024; // board snapshots (jokers, hand, history) can be a few tens of KB
const IDLE_TIMEOUT_MS = 90 * 1000;

function createServer(opts = {}) {
  const log = opts.log ?? ((...a) => console.log(new Date().toISOString(), ...a));
  const sockets = new Map();
  let nextCid = 1;

  const relay = new RelayHost({
    minPlayers: opts.minPlayers ?? 2,
    log,
    onSend: (cid, line) => {
      const s = sockets.get(cid);
      if (s && !s.destroyed) s.write(line + '\n');
    },
  });

  const server = net.createServer((socket) => {
    const cid = nextCid++;
    sockets.set(cid, socket);
    socket.setNoDelay(true);
    socket.setEncoding('utf8');
    socket.setTimeout(IDLE_TIMEOUT_MS);
    log(`connection ${cid} from ${socket.remoteAddress}`);
    relay.connect(cid);

    let buf = '';
    socket.on('data', (chunk) => {
      buf += chunk;
      if (buf.length > MAX_LINE && buf.indexOf('\n') === -1) { socket.destroy(); return; }
      let nl;
      while ((nl = buf.indexOf('\n')) !== -1) {
        const line = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        if (!line) continue;
        try { relay.line(cid, line); } catch (e) { log(`relay error: ${e.message}`); }
      }
    });
    socket.on('timeout', () => socket.destroy());
    socket.on('error', () => {});
    socket.on('close', () => {
      sockets.delete(cid);
      log(`connection ${cid} closed`);
      try { relay.close(cid); } catch (e) { log(`relay error: ${e.message}`); }
    });
  });

  server.relay = relay;
  return server;
}

if (require.main === module) {
  const port = Number(process.env.PORT) || 8788;
  const host = process.env.HOST || '0.0.0.0';
  const minPlayers = Number(process.env.MIN_PLAYERS) || 2;
  createServer({ minPlayers }).listen(port, host, () => {
    console.log(`Balatro Duel & Co-op relay listening on ${host}:${port} (min players ${minPlayers})`);
  });
}

module.exports = { createServer };
