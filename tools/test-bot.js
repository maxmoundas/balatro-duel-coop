#!/usr/bin/env node
// Stand-in second player for testing Balatro Multiplayer alone.
//
//   node tools/test-bot.js CODE                  (your in-game lobby, on this PC)
//   node tools/test-bot.js CODE@steam:<id>       (pasted invite code - same thing)
//   node tools/test-bot.js CODE@host:port        (a lobby on a dedicated server)
//
// The bot connects to your in-game server directly on 127.0.0.1:8788, so it tests the
// game rules and menus but not the Steam connection itself. Once you press Start Game the bot
// shadows you: it starts/skips the same blinds, takes part in every hand sync
// (Duel) or blind gate (Co-op), posts scores near yours, and mirrors your board
// so the player viewer has something to show.
//
// Options: --name Bot   --skill 1.0 (score multiplier vs yours; >1 = tougher)
'use strict';
const net = require('net');

const args = process.argv.slice(2);
function opt(name, def) {
  const i = args.indexOf('--' + name);
  if (i < 0) return def;
  const v = args[i + 1];
  args.splice(i, 2);
  return v;
}
const NAME = opt('name', 'TestBot');
const SKILL = Number(opt('skill', '1.0')) || 1.0;
const link = (args[0] || '').trim();
if (!link) {
  console.log('Usage: node tools/test-bot.js CODE@host:port  [--name Bot] [--skill 1.0]');
  process.exit(1);
}
let code = link, host = '127.0.0.1', port = 8788;
const m = link.match(/^(\w+)@(.+):(\d+)$/);
if (m && m[2] !== 'steam') { code = m[1]; host = m[2]; port = Number(m[3]); }
else if (link.includes('@')) code = link.split('@')[0];

const log = (...a) => console.log(new Date().toTimeString().slice(0, 8), ...a);
const rnd = (lo, hi) => lo + Math.random() * (hi - lo);

let myId = null, mode = null, started = false;
const duel = { slot: 0, hand: 0, hands: 0, best: 0 };

const sock = net.connect({ host, port }, () => {
  log(`connected to ${host}:${port}`);
  send({ type: 'hello', name: NAME, protocol: 3 });
});
sock.setNoDelay(true);
sock.setEncoding('utf8');

function send(msg) { sock.write(JSON.stringify(msg) + '\n'); }

let buf = '';
sock.on('data', (chunk) => {
  buf += chunk;
  let nl;
  while ((nl = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { log('bad line:', line.slice(0, 80)); continue; }
    try { handle(msg); } catch (e) { log('handler error:', e.message); }
  }
});
sock.on('error', (e) => { log('socket error:', e.message); process.exit(1); });
sock.on('close', () => { log('disconnected'); process.exit(0); });
setInterval(() => send({ type: 'ping' }), 20000); // stay under the server's idle timeout

// ---- Duel: shadow the opponent's blinds ----
function duelStartBlind(slot) {
  Object.assign(duel, { slot, hand: 1, hands: 0, best: 0 });
  send({ type: 'blind_start', slot });
}

// Round gates: whenever you wait at one, the bot catches up so you're released.
const gateDone = new Set();
function catchUp(w) {
  const key = w.kind + ':' + w.slot;
  if (gateDone.has(key)) return;
  gateDone.add(key);
  if (w.kind === 'blind' && mode === 'coop' && w.action === 'skip') {
    log(`you're skipping blind ${w.slot}; bot skips too`);
    send({ type: 'blind_ready', slot: w.slot, action: 'skip' });
    send({ type: 'blind_skip', slot: w.slot });
  } else if (w.kind === 'blind') {
    log(`you're ready for blind ${w.slot}; bot ready too`);
    send({ type: 'blind_ready', slot: w.slot });
  } else {
    log(`you finished blind ${w.slot}; bot finishes it too`);
    send({ type: 'blind_end', slot: w.slot, won: true, hands: 1, best: duel.best || 1 });
  }
}

function handle(msg) {
  switch (msg.type) {
    case 'welcome':
      myId = String(msg.id);
      log(`hello ok (id ${myId}), joining lobby ${code}`);
      send({ type: 'join', code });
      break;
    case 'error':
      log('server error:', msg.msg);
      break;
    case 'lobby':
      mode = msg.mode;
      log(`in lobby ${msg.code}: ${msg.mode}, ${(msg.players || []).map((p) => p.name).join(', ')}` +
        (started ? '' : '  -> press Start Game in Balatro'));
      break;
    case 'start':
      started = true;
      mode = msg.mode;
      log(`game started: ${msg.mode}, seed ${msg.seed}, ${msg.playerCount} players`);
      break;
    case 'player_snapshot':
      send({ type: 'snapshot', data: msg.data }); // mirror your board into the viewer
      break;

    // Duel
    case 'opp_blind_start':
      log(`you started blind ${msg.slot}`);
      duelStartBlind(msg.slot);
      break;
    case 'gate_status':
      for (const w of Object.values(msg.waiting || {})) {
        if (String(w.id) !== myId) catchUp(w);
      }
      break;
    case 'opp_hand': {
      if (msg.slot !== duel.slot) break;
      const score = Math.max(1, Math.round(msg.score * SKILL * rnd(0.7, 1.3)));
      duel.hands = msg.hand;
      duel.best = Math.max(duel.best, score);
      log(`you scored ${msg.score} on hand ${msg.hand}; bot scores ${score}`);
      send({ type: 'hand_scored', slot: duel.slot, hand: msg.hand, score });
      break;
    }
    case 'opp_blind': {
      if (msg.skipped) {
        log(`you skipped blind ${msg.slot}; bot skips too`);
        send({ type: 'blind_skip', slot: msg.slot });
        break;
      }
      // Win with roughly your hand count (sometimes one more/less) so points split.
      const hands = Math.max(1, (msg.hands || duel.hands || 1) + Math.round(rnd(-1, 1)));
      log(`blind ${msg.slot} done (you: ${msg.won ? 'won' : 'lost'} in ${msg.hands}); bot won in ${hands}`);
      send({ type: 'blind_end', slot: msg.slot, won: true, hands, best: duel.best || 1 });
      break;
    }
    case 'slot_result':
      log(`round ${msg.slot} points:`, JSON.stringify(msg.points));
      break;

    // Co-op
    case 'team_status':
      if (msg.outOfHands && msg.outOfHands.length && !msg.outOfHands.map(String).includes(myId)) {
        log(`you're out of hands on blind ${msg.slot}; so is the bot`);
        send({ type: 'out_of_hands', slot: msg.slot });
      }
      break;
    case 'team_score': {
      if (String(msg.from) === myId) break;
      const score = Math.max(1, Math.round(msg.score * SKILL * rnd(0.7, 1.3)));
      log(`you scored ${msg.score}; bot adds ${score}`);
      send({ type: 'hand_scored', slot: msg.slot, hand: msg.hand, score });
      break;
    }
    case 'team_failed':
      log(`team failed blind ${msg.slot}`);
      break;

    // Run end
    case 'player_run_end':
      log(`your run ended: ${msg.status} at round ${msg.slot}`);
      if (msg.status === 'won') send({ type: 'run_won', slot: msg.slot }); // finish alongside you
      break;
    case 'game_over':
      log('GAME OVER:', JSON.stringify(msg));
      setTimeout(() => process.exit(0), 500);
      break;
    case 'player_left':
      log(`${msg.name} left`);
      break;
    case 'pong':
    case 'gate_go':
      break;
    default:
      log('<-', msg.type);
  }
}
