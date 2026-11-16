'use strict';

// Tests run the mod's relay.lua (via fengari) - the same code the in-game host server runs.

const test = require('node:test');
const assert = require('node:assert');
const net = require('net');
const { RelayHost } = require('../src/relay-host');
const { createServer } = require('../src/server');

function harness(opts = {}) {
  const clients = new Map();
  const host = new RelayHost({
    minPlayers: opts.minPlayers ?? 2,
    onSend: (cid, line) => clients.get(cid).inbox.push(JSON.parse(line)),
  });
  let next = 1;
  return {
    client(name, steamId) {
      const cid = next++;
      const c = {
        inbox: [],
        send: (m) => host.line(cid, JSON.stringify(m)),
        close: () => host.close(cid),
        last: (t) => [...c.inbox].reverse().find(m => m.type === t),
        all: (t) => c.inbox.filter(m => m.type === t),
      };
      clients.set(cid, c);
      host.connect(cid);
      c.send({ type: 'hello', name, steamId, protocol: 4 });
      c.id = c.last('welcome').id;
      return c;
    },
    host,
  };
}

function lobbyOf(mode, n) {
  const h = harness();
  const ps = Array.from({ length: n }, (_, i) => h.client('P' + (i + 1)));
  ps[0].send({ type: 'create', mode });
  const code = ps[0].last('lobby').code;
  ps.slice(1).forEach(p => p.send({ type: 'join', code }));
  ps[0].send({ type: 'start' });
  return { h, ps, code, ev: (p, m) => p.send(m) };
}

function duel() {
  const { h, ps, ev } = lobbyOf('duel', 2);
  return { h, a: ps[0], b: ps[1], ev };
}
const coop = (n) => lobbyOf('coop', n);

// Plays a whole blind for one player: n hands with given scores, then blind_end.
function playBlind(ev, p, slot, scores, won) {
  ev(p, { type: 'blind_start', slot });
  scores.forEach((s, i) => {
    ev(p, { type: 'hand_scored', slot, hand: i + 1, score: s });
  });
  ev(p, { type: 'blind_end', slot, won, hands: scores.length, best: Math.max(...scores) });
}

test('ids are plain strings and start broadcasts the same seed to every player', () => {
  const { a, b } = duel();
  assert.strictEqual(a.id, '1');
  assert.strictEqual(b.id, '2');
  assert.strictEqual(a.last('start').seed, b.last('start').seed);
  assert.match(a.last('start').seed, /^[A-Z1-9]{8}$/);
});

test('hands are never gated: both players play freely', () => {
  const { a, b, ev } = duel();
  ev(a, { type: 'blind_start', slot: 1 });
  ev(a, { type: 'hand_scored', slot: 1, hand: 1, score: 100 });
  ev(a, { type: 'hand_scored', slot: 1, hand: 2, score: 100 });
  assert.strictEqual(b.all('opp_hand').length, 2);
  assert.strictEqual(a.all('gate_status').length, 0);
});

test('shop gate: cashing out waits until the other player finishes the blind', () => {
  const { a, b, ev } = duel();
  playBlind(ev, a, 1, [500], true);
  ev(a, { type: 'shop_ready', slot: 1 });
  assert.strictEqual(a.all('gate_go').length, 0);
  assert.deepStrictEqual(a.last('gate_status').waiting, [{ id: '1', kind: 'shop', slot: 1, waitingFor: ['P2'] }]);
  playBlind(ev, b, 1, [50, 50], true);
  assert.deepStrictEqual(a.last('gate_go'), { type: 'gate_go', kind: 'shop', slot: 1 });
  ev(b, { type: 'shop_ready', slot: 1 });
  assert.strictEqual(b.all('gate_go').length, 1, 'other player already done: no wait');
  assert.strictEqual(Object.keys(a.last('gate_status').waiting).length, 0);
});

test('blind gate: next blind waits until everyone is ready for it', () => {
  const { a, b, ev } = duel();
  playBlind(ev, a, 1, [500], true);
  playBlind(ev, b, 1, [500], true);
  ev(a, { type: 'blind_ready', slot: 2 });
  assert.strictEqual(a.all('gate_go').length, 0, 'b still shopping');
  ev(b, { type: 'blind_ready', slot: 2 });
  assert.strictEqual(a.all('gate_go').length, 1);
  assert.strictEqual(b.all('gate_go').length, 1);
});

test('gates ignore players whose run is over', () => {
  const { a, b, ev } = duel();
  playBlind(ev, a, 1, [500], true);
  ev(a, { type: 'shop_ready', slot: 1 });
  ev(b, { type: 'run_over', slot: 1 });
  assert.strictEqual(a.all('gate_go').length, 1);
});

test('duel points: best hand and fewest hands, ties award both', () => {
  const { a, b, ev } = duel();
  playBlind(ev, a, 1, [100, 400], true);
  playBlind(ev, b, 1, [300, 200, 100], true);
  assert.deepStrictEqual(a.last('slot_result').points, { 1: 2, 2: 0 });
  playBlind(ev, a, 2, [300, 300], true);
  playBlind(ev, b, 2, [500, 100], true);
  assert.deepStrictEqual(a.last('slot_result').points, { 1: 3, 2: 2 });
});

test("duel: losing player's opponent must clear that round before winning", () => {
  const { a, b, ev } = duel();
  playBlind(ev, a, 1, [10, 10, 10, 10], false);
  ev(a, { type: 'run_over', slot: 1 });
  assert.strictEqual(a.all('game_over').length, 0, 'b may still lose the same round');
  playBlind(ev, b, 1, [100], true);
  const go = a.last('game_over');
  assert.strictEqual(go.winnerId, '2');
  assert.strictEqual(go.reason, 'outlasted');
});

test('duel: both lose the same round -> points decide', () => {
  const { a, b, ev } = duel();
  playBlind(ev, a, 1, [500], true);
  playBlind(ev, b, 1, [100, 100], true);
  playBlind(ev, a, 2, [1], false);
  playBlind(ev, b, 2, [2], false);
  ev(b, { type: 'run_over', slot: 2 });
  assert.strictEqual(a.all('game_over').length, 0);
  ev(a, { type: 'run_over', slot: 2 });
  const go = b.last('game_over');
  assert.strictEqual(go.reason, 'both_lost_same_round');
  assert.strictEqual(go.winnerId, '1');
});

test('duel: equal points on the same losing round is a draw', () => {
  const { a, b, ev } = duel();
  playBlind(ev, a, 1, [5], false);
  playBlind(ev, b, 1, [5], false);
  ev(a, { type: 'run_over', slot: 1 });
  ev(b, { type: 'run_over', slot: 1 });
  const go = a.last('game_over');
  assert.strictEqual(go.reason, 'both_lost_same_round');
  assert.strictEqual(go.winnerId, undefined);
});

test('duel: Mr. Bones save (lost blind but run continues) is not a loss', () => {
  const { a, b, ev } = duel();
  playBlind(ev, a, 1, [10], false);
  ev(a, { type: 'run_over', slot: 1 });
  playBlind(ev, b, 1, [10], false);
  assert.strictEqual(a.all('game_over').length, 0, '...but might be saved');
  ev(b, { type: 'blind_start', slot: 2 });
  assert.strictEqual(a.last('game_over').winnerId, '2');
});

test('duel: both beat the final boss -> most points wins', () => {
  const { a, b, ev } = duel();
  playBlind(ev, a, 1, [100], true);
  playBlind(ev, b, 1, [50, 50], true);
  ev(a, { type: 'run_won', slot: 24 });
  assert.strictEqual(a.all('game_over').length, 0);
  ev(b, { type: 'run_won', slot: 24 });
  const go = a.last('game_over');
  assert.strictEqual(go.reason, 'both_won');
  assert.strictEqual(go.winnerId, '1');
});

test('duel: one wins the run, other loses later -> winner', () => {
  const { a, b, ev } = duel();
  ev(a, { type: 'run_won', slot: 24 });
  ev(b, { type: 'run_over', slot: 24 });
  assert.strictEqual(a.last('game_over').winnerId, '1');
});

test('duel: opponent disconnect forfeits', () => {
  const { a, b } = duel();
  b.close();
  assert.strictEqual(a.last('game_over').winnerId, '1');
  assert.strictEqual(a.last('game_over').reason, 'opponent_left');
});

test('coop: blind gate waits for everyone', () => {
  const { ps, ev } = coop(3);
  ev(ps[0], { type: 'blind_ready', slot: 1 });
  ev(ps[1], { type: 'blind_ready', slot: 1 });
  assert.strictEqual(ps[0].all('gate_go').length, 0);
  ev(ps[2], { type: 'blind_ready', slot: 1 });
  ps.forEach(p => assert.strictEqual(p.all('gate_go').length, 1));
});

test('coop: scores relayed to teammates with running total', () => {
  const { ps, ev } = coop(2);
  ev(ps[0], { type: 'hand_scored', slot: 1, hand: 1, score: 120 });
  ev(ps[1], { type: 'hand_scored', slot: 1, hand: 1, score: 80 });
  assert.strictEqual(ps[1].last('team_score').score, 120);
  assert.strictEqual(ps[0].last('team_score').total, 200);
  assert.strictEqual(ps[0].all('team_score').length, 1, 'not echoed back to sender');
});

test('coop: team fails only when everyone is out of hands', () => {
  const { ps, ev } = coop(2);
  ev(ps[0], { type: 'out_of_hands', slot: 1 });
  assert.strictEqual(ps[0].all('team_failed').length, 0);
  ev(ps[1], { type: 'out_of_hands', slot: 1 });
  assert.strictEqual(ps[0].all('team_failed').length, 1);
});

test('coop: one teammate saved (Mr. Bones) saves the whole team', () => {
  const { ps, ev } = coop(3);
  ps.forEach(p => ev(p, { type: 'out_of_hands', slot: 1 }));
  ev(ps[0], { type: 'fail_check', slot: 1, saved: false });
  ev(ps[1], { type: 'fail_check', slot: 1, saved: true });
  assert.strictEqual(ps[0].all('team_fail_result').length, 0, 'waits for every answer');
  ev(ps[2], { type: 'fail_check', slot: 1, saved: false });
  ps.forEach(p => assert.deepStrictEqual(p.last('team_fail_result'), { type: 'team_fail_result', slot: 1, saved: true }));
  ev(ps[2], { type: 'fail_check', slot: 1, saved: true });
  assert.strictEqual(ps[0].all('team_fail_result').length, 1, 'resolved once');
});

test('coop: nobody saved -> team fail result says so; a leaver does not stall it', () => {
  const { ps, ev } = coop(3);
  ps.forEach(p => ev(p, { type: 'out_of_hands', slot: 1 }));
  ev(ps[0], { type: 'fail_check', slot: 1, saved: false });
  ev(ps[1], { type: 'fail_check', slot: 1, saved: false });
  ps[2].close();
  assert.strictEqual(ps[0].last('team_fail_result').saved, false);
});

test('coop: no failure if the blind was already won', () => {
  const { ps, ev } = coop(2);
  ev(ps[0], { type: 'out_of_hands', slot: 1 });
  ev(ps[1], { type: 'blind_end', slot: 1, won: true, hands: 3, best: 10 });
  ev(ps[1], { type: 'out_of_hands', slot: 1 });
  assert.strictEqual(ps[0].all('team_failed').length, 0);
});

test('coop: skipping a blind - the rest play it, scaled to them; skipper waits for the next blind', () => {
  const { ps, ev } = coop(3);
  ev(ps[0], { type: 'blind_ready', slot: 1, action: 'skip' });
  ev(ps[1], { type: 'blind_ready', slot: 1, action: 'select' });
  ev(ps[2], { type: 'blind_ready', slot: 1, action: 'select' });
  ps.forEach(p => assert.strictEqual(p.last('gate_go').playing, 2, 'two players play blind 1'));
  ev(ps[0], { type: 'blind_skip', slot: 1 });

  // The skipper is ready for blind 2 right away but waits for the others to finish blind 1.
  ev(ps[0], { type: 'blind_ready', slot: 2, action: 'select' });
  assert.strictEqual(ps[0].all('gate_go').length, 1);
  assert.deepStrictEqual(ps[0].last('gate_status').waiting[0].waitingFor, ['P2', 'P3']);

  // Their shop gate doesn't wait on the skipper.
  ev(ps[1], { type: 'blind_end', slot: 1, won: true, hands: 2, best: 50 });
  ev(ps[2], { type: 'blind_end', slot: 1, won: true, hands: 2, best: 50 });
  ev(ps[1], { type: 'shop_ready', slot: 1 });
  assert.strictEqual(ps[1].last('gate_go').kind, 'shop');

  ev(ps[1], { type: 'blind_ready', slot: 2, action: 'select' });
  ev(ps[2], { type: 'blind_ready', slot: 2, action: 'select' });
  ps.forEach(p => assert.deepStrictEqual(p.last('gate_go'), { type: 'gate_go', kind: 'blind', slot: 2, playing: 3 }));
});

test('coop: team fails when everyone playing the blind is out of hands (skippers excluded)', () => {
  const { ps, ev } = coop(2);
  ev(ps[0], { type: 'blind_ready', slot: 1, action: 'skip' });
  ev(ps[1], { type: 'blind_ready', slot: 1 });
  ev(ps[1], { type: 'out_of_hands', slot: 1 });
  assert.strictEqual(ps[0].all('team_failed').length, 1);
});

test('coop: leaver no longer blocks gates', () => {
  const { ps, ev } = coop(3);
  ev(ps[0], { type: 'blind_ready', slot: 1 });
  ev(ps[1], { type: 'blind_ready', slot: 1 });
  ps[2].close();
  assert.strictEqual(ps[0].all('gate_go').length, 1);
});

test('coop: any run loss ends the game for the team; all wins -> team win', () => {
  let { ps, ev } = coop(2);
  ev(ps[0], { type: 'run_over', slot: 3 });
  assert.strictEqual(ps[1].last('game_over').result, 'lost');

  ({ ps, ev } = coop(2));
  ev(ps[0], { type: 'run_won', slot: 24 });
  assert.strictEqual(ps[1].all('game_over').length, 0);
  ev(ps[1], { type: 'run_won', slot: 24 });
  assert.strictEqual(ps[1].last('game_over').result, 'won');
});

test('coop: an ante-lowering voucher moves every teammate back', () => {
  const { ps, ev } = coop(3);
  ev(ps[0], { type: 'ante_back', slot: 3, amount: 1, voucher: 'Hieroglyph' });
  assert.strictEqual(ps[0].all('team_ante').length, 0);
  for (const p of ps.slice(1)) {
    const m = p.last('team_ante');
    assert.strictEqual(m.amount, 1);
    assert.strictEqual(m.from, ps[0].id);
    assert.strictEqual(m.voucher, 'Hieroglyph');
  }
  ev(ps[1], { type: 'ante_back', slot: 3, amount: 99 });
  assert.strictEqual(ps[0].last('team_ante').amount, 8);
  ev(ps[1], { type: 'ante_back', slot: 3, amount: 0 });
  assert.strictEqual(ps[0].all('team_ante').length, 1);
});

test('duel: ante-lowering vouchers stay personal', () => {
  const { a, b, ev } = duel();
  ev(a, { type: 'ante_back', slot: 3, amount: 1 });
  assert.strictEqual(b.all('team_ante').length, 0);
});

test('challenge lobbies pass the challenge to everyone at stake 1', () => {
  const h = harness();
  const a = h.client('A'), b = h.client('B');
  a.send({ type: 'create', mode: 'coop', challenge: 'c_omelette_1', stake: 5 });
  const code = a.last('lobby').code;
  assert.strictEqual(a.last('lobby').challenge, 'c_omelette_1');
  b.send({ type: 'join', code });
  a.send({ type: 'start' });
  assert.strictEqual(b.last('start').challenge, 'c_omelette_1');
  assert.strictEqual(b.last('start').stake, 1);

  const c = h.client('C');
  c.send({ type: 'create', mode: 'duel', challenge: 'bad id!' });
  assert.strictEqual(c.last('lobby').challenge, undefined);
});

test('snapshots are relayed to the other players, also after game over', () => {
  const { a, b, ev } = duel();
  ev(a, { type: 'snapshot', data: { money: 7, jokers: [{ k: 'j_joker' }] } });
  assert.deepStrictEqual(b.last('player_snapshot'), { type: 'player_snapshot', id: '1', name: 'P1', data: { money: 7, jokers: [{ k: 'j_joker' }] } });
  assert.strictEqual(a.all('player_snapshot').length, 0, 'not echoed to sender');
  ev(a, { type: 'run_won', slot: 24 });
  ev(b, { type: 'run_won', slot: 24 });
  assert.ok(a.last('game_over'));
  ev(b, { type: 'snapshot', data: { money: 1 } });
  assert.strictEqual(a.last('player_snapshot').data.money, 1);
});

test('lobby limits and errors', () => {
  const h = harness();
  const [p1, p2, p3] = [h.client('A'), h.client('B'), h.client('C')];
  p1.send({ type: 'create', mode: 'duel' });
  const code = p1.last('lobby').code;
  p2.send({ type: 'join', code: code.toLowerCase() });
  p3.send({ type: 'join', code });
  assert.match(p3.last('error').msg, /full/);
  p3.send({ type: 'join', code: 'ZZZZ' });
  assert.match(p3.last('error').msg, /no lobby/);
  p2.send({ type: 'start' });
  assert.match(p2.last('error').msg, /only the host/);
  p3.send({ type: 'create', mode: 'battle-royale' });
  assert.match(p3.last('error').msg, /invalid mode/);

  const c = [h.client('1'), h.client('2'), h.client('3'), h.client('4'), h.client('5')];
  c[0].send({ type: 'create', mode: 'coop', seed: 'abc123' });
  const coopLobby = c[0].last('lobby');
  assert.strictEqual(coopLobby.seed, 'ABC123', 'custom seed kept (uppercased)');
  c.slice(1).forEach(p => p.send({ type: 'join', code: coopLobby.code }));
  assert.match(c[4].last('error').msg, /full/);
});

test('min players is enforced', () => {
  const h = harness();
  const p = h.client('Solo');
  p.send({ type: 'create', mode: 'coop' });
  p.send({ type: 'start' });
  assert.match(p.last('error').msg, /at least 2/);
  const h1 = harness({ minPlayers: 1 });
  const q = h1.client('Solo');
  q.send({ type: 'create', mode: 'coop' });
  q.send({ type: 'start' });
  assert.ok(q.last('start'));
});

test('empty lobbies are deleted when everyone leaves', () => {
  const h = harness();
  const p = h.client('A');
  p.send({ type: 'create', mode: 'duel' });
  assert.strictEqual(h.host.lobbyCount(), 1);
  p.send({ type: 'leave' });
  assert.strictEqual(h.host.lobbyCount(), 0);
});

test('Steam invite is pushed to a connected friend', () => {
  const h = harness();
  const host = h.client('Host', '76561198000000001');
  const friend = h.client('Friend', '76561198000000002');
  host.send({ type: 'invite', steamId: '76561198000000002' });
  assert.match(host.last('error').msg, /open a lobby/);
  host.send({ type: 'create', mode: 'coop' });
  const code = host.last('lobby').code;
  host.send({ type: 'invite', steamId: '76561198000000002' });
  assert.deepStrictEqual(friend.last('invited'), { type: 'invited', fromName: 'Host', fromId: '1', code, mode: 'coop' });
  assert.strictEqual(host.last('invite_result').delivered, true);
  host.send({ type: 'invite', steamId: '76561198000000099' });
  assert.strictEqual(host.last('invite_result').delivered, false);
});

test('clients on an older mod version cannot create or join', () => {
  const h = harness();
  const host = h.client('Host');
  host.send({ type: 'create', mode: 'duel' });
  const code = host.last('lobby').code;
  const old = h.client('Old');
  old.send({ type: 'hello', name: 'Old' }); // v0.1 clients send no protocol
  old.send({ type: 'join', code });
  assert.match(old.last('error').msg, /different mod version/);
  assert.strictEqual(host.last('lobby').players.length, 1);
});

test('bad input is rejected without crashing', () => {
  const h = harness();
  const p = h.client('A');
  h.host.line(1, '{not json');
  assert.strictEqual(p.last('error').msg, 'bad json');
  h.host.line(1, '{"no_type":1}');
  p.send({ type: 'hand_scored', slot: 'x', score: 'y' }); // not in a lobby: ignored
  p.send({ type: 'ping' });
  assert.ok(p.last('pong'));
});

async function tcpClient(port) {
  const s = await new Promise(resolve => { const c = net.connect(port, '127.0.0.1', () => resolve(c)); });
  s.msgs = [];
  let buf = '';
  s.on('data', d => {
    buf += d;
    let i;
    while ((i = buf.indexOf('\n')) !== -1) { s.msgs.push(JSON.parse(buf.slice(0, i))); buf = buf.slice(i + 1); }
  });
  s.sendj = m => s.write(JSON.stringify(m) + '\n');
  s.waitFor = (type) => new Promise((resolve, reject) => {
    const t0 = Date.now();
    const iv = setInterval(() => {
      const m = s.msgs.find(x => x.type === type);
      if (m) { clearInterval(iv); resolve(m); } else if (Date.now() - t0 > 2000) { clearInterval(iv); reject(new Error('timeout ' + type)); }
    }, 5);
  });
  return s;
}

test('TCP end-to-end: create, join, start, disconnect', async () => {
  const server = createServer({ log: () => {} });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  const a = await tcpClient(port), b = await tcpClient(port);
  a.sendj({ type: 'hello', name: 'Alice', protocol: 4 });
  b.sendj({ type: 'hello', name: 'Bob', protocol: 4 });
  a.sendj({ type: 'create', mode: 'duel', deck: 'b_blue', stake: 2 });
  const lobby = await a.waitFor('lobby');
  b.sendj({ type: 'join', code: lobby.code });
  await b.waitFor('lobby');
  a.sendj({ type: 'start' });
  const [sa, sb] = await Promise.all([a.waitFor('start'), b.waitFor('start')]);
  assert.strictEqual(sa.seed, sb.seed);
  assert.strictEqual(sb.deck, 'b_blue');
  assert.strictEqual(sb.stake, 2);
  b.destroy();
  const go = await a.waitFor('game_over');
  assert.strictEqual(go.reason, 'opponent_left');
  a.destroy();
  await new Promise(r => server.close(r));
});
