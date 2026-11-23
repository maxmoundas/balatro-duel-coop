-- Balatro Duel & Co-op relay: lobbies, round gates, Duel points, win rules, invites.
--
-- Hands are never gated: everyone plays at their own pace. Two "round gates" keep the
-- players together between blinds:
--   * shop gate  (shop_ready slot S): cashing out after blind S waits until every other
--                 player still in the run has finished blind S.
--   * blind gate (blind_ready slot S): selecting or skipping blind S waits until every
--                 other player still in the run is also ready for blind S (or past it).
--                 A player who skips blind S then waits at blind gate S+1 until everyone
--                 who played blind S has finished it and left the shop.
--
-- Co-op skips: players who skip blind S sit it out. The ones who select it play it, and
-- its requirement scales by how many of them there are (sent as gate_go.playing).
--
-- Co-op saves: when everyone playing a blind is out of hands (team_failed), each of them
-- answers fail_check saying whether a joker like Mr. Bones would save them. Once all have
-- answered, team_fail_result tells everyone whether the team is saved (anyone saved ->
-- the whole team moves on) or loses.
--
-- Co-op ante: a player who redeems an ante-lowering voucher (Hieroglyph / Petroglyph)
-- sends ante_back; everyone else gets team_ante and moves back too (never below ante 1).
--
-- Single source of truth for the multiplayer rules. Transport-agnostic, and runs in two places:
--   * inside the game when a player hosts (LÖVE thread + luasocket, LuaJIT / Lua 5.1)
--   * in the standalone Node server (server/src/server.js, via fengari / Lua 5.3)
-- so it must stick to the common subset of Lua 5.1 and 5.3.
--
-- Usage:
--   local relay = Relay.new{ json = json, min_players = 2, log = print }
--   local player = relay:connect(function(line) ...write line.."\n" to the socket... end)
--   relay:receive(player, line)   -- one JSON message per line
--   relay:disconnect(player)

local Relay = {}
Relay.__index = Relay
Relay.PROTOCOL_VERSION = 5

local MAX_PLAYERS = { duel = 2, coop = 4 }
local SEED_CHARS = 'ABCDEFGHIJKLMNPQRSTUVWXYZ123456789'
local CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'

local function rand_string(chars, len)
  local t = {}
  for i = 1, len do
    local k = math.random(1, #chars)
    t[i] = chars:sub(k, k)
  end
  return table.concat(t)
end

local function int(v, default)
  local n = tonumber(v)
  if not n or n ~= n then return default end
  return n
end

local function fail(msg) error(msg, 0) end

local function list_filter(list, pred)
  local out = {}
  for _, v in ipairs(list) do if pred(v) then out[#out + 1] = v end end
  return out
end

local function index_of(list, v)
  for i, x in ipairs(list) do if x == v then return i end end
end

-- ---------------------------------------------------------------------------
-- Lobby

local Lobby = {}
Lobby.__index = Lobby

function Lobby.new(code, host, opts)
  if not MAX_PLAYERS[opts.mode] then fail('invalid mode') end
  local self = setmetatable({}, Lobby)
  self.code = code
  self.mode = opts.mode
  self.deck = type(opts.deck) == 'string' and opts.deck or 'b_red'
  local stake = tonumber(opts.stake)
  self.stake = (stake and stake == math.floor(stake) and stake >= 1 and stake <= 64) and stake or 1
  local seed = type(opts.seed) == 'string' and opts.seed:upper() or nil
  self.seed = (seed and seed:match('^[A-Z1-9]+$') and #seed <= 8) and seed or rand_string(SEED_CHARS, 8)
  -- Same seed for everyone (the default), or a different random seed for each player.
  self.same_seed = opts.same_seed ~= false
  -- Challenge id (e.g. 'c_omelette_1'); a challenge brings its own deck, rules and stake.
  local ch = type(opts.challenge) == 'string' and opts.challenge or nil
  self.challenge = (ch and #ch <= 64 and ch:match('^[%w_%-]+$')) and ch or nil
  if self.challenge then self.stake = 1 end
  self.min_players = opts.min_players or 2
  self.json = opts.json
  self.players = {}
  self.started = false
  self.finished = false
  self:add(host)
  return self
end

function Lobby:max_players() return MAX_PLAYERS[self.mode] end
function Lobby:host_id() return self.players[1] and self.players[1].id end

function Lobby:add(player)
  if self.started then fail('game already started') end
  if #self.players >= self:max_players() then fail('lobby is full') end
  player.lobby = self
  player.game = nil
  self.players[#self.players + 1] = player
  self:broadcast_lobby()
end

function Lobby:player_list()
  local t = {}
  for i, p in ipairs(self.players) do t[i] = { id = p.id, name = p.name } end
  return t
end

function Lobby:info()
  return {
    type = 'lobby', code = self.code, mode = self.mode, deck = self.deck, stake = self.stake,
    seed = self.seed, sameSeed = self.same_seed, challenge = self.challenge, started = self.started, hostId = self:host_id(), players = self:player_list(),
  }
end

function Lobby:broadcast(msg, except)
  for _, p in ipairs(self.players) do
    if p ~= except then p:send(msg) end
  end
end

function Lobby:broadcast_lobby() self:broadcast(self:info()) end

function Lobby:opponent(player)
  for _, p in ipairs(self.players) do if p ~= player then return p end end
end

function Lobby:alive_players()
  return list_filter(self.players, function(p) return p.game and p.game.status == 'alive' end)
end

function Lobby:start(player)
  if player.id ~= self:host_id() then fail('only the host can start') end
  if self.started then fail('already started') end
  if #self.players < self.min_players then fail('need at least ' .. self.min_players .. ' players') end
  self.started = true
  for _, p in ipairs(self.players) do
    p.game = {
      status = 'alive',   -- alive | lost | won | left
      end_slot = nil,
      max_slot = 0,       -- highest slot this player has started
      results = {},       -- slot -> { won, hands, best, skipped }
      wait = nil,         -- { kind = 'shop' | 'blind', slot } while held at a round gate
      out_of_hands = {},  -- slot -> true
      skipping = {},      -- slot -> true when the player chose to skip that blind
      points = 0,
      last_hand = nil,
    }
  end
  self.scored_slots = {}
  self.coop_slots = {}
  self.last_gate_status = self.json and self.json.encode({}) or '0' -- nobody waiting yet
  for _, p in ipairs(self.players) do
    p:send({
      type = 'start', mode = self.mode, deck = self.deck, stake = self.stake, challenge = self.challenge,
      seed = self.same_seed and self.seed or rand_string(SEED_CHARS, 8), sameSeed = self.same_seed,
      playerCount = #self.players, players = self:player_list(),
    })
  end
end

-- Lobby options the host can change before the game starts.
function Lobby:set_options(player, msg)
  if player.id ~= self:host_id() then fail('only the host can change the lobby options') end
  if self.started then fail('already started') end
  if msg.sameSeed ~= nil then self.same_seed = msg.sameSeed ~= false end
  self:broadcast_lobby()
end

-- ---- in-game events --------------------------------------------------------

function Lobby:handle(player, msg)
  if not self.started or not player.game then return end
  if msg.type == 'snapshot' then
    -- Latest board for the in-run player viewer; relayed even after the game ends.
    if type(msg.data) ~= 'table' then return end
    player.game.snapshot = msg.data
    self:broadcast({ type = 'player_snapshot', id = player.id, name = player.name, data = msg.data }, player)
    return
  end
  if self.finished then return end
  local g = player.game
  local slot = int(msg.slot, 0)
  if slot > g.max_slot and msg.type ~= 'run_over' and msg.type ~= 'run_won' then g.max_slot = slot end

  local t = msg.type
  if t == 'blind_start' then
    if self.mode == 'duel' then
      local opp = self:opponent(player)
      if opp then opp:send({ type = 'opp_blind_start', slot = slot }) end
      self:check_duel_outcome()
    end
  elseif t == 'blind_ready' then
    local skip = msg.action == 'skip'
    player.game.wait = { kind = 'blind', slot = slot, action = skip and 'skip' or 'select' }
    player.game.skipping[slot] = skip or nil
  elseif t == 'shop_ready' then player.game.wait = { kind = 'shop', slot = slot }
  elseif t == 'hand_scored' then self:on_hand_scored(player, slot, int(msg.hand, 0), math.max(0, int(msg.score, 0)))
  elseif t == 'blind_end' then
    self:on_blind_end(player, slot, { won = msg.won == true, hands = int(msg.hands, 0), best = int(msg.best, 0), skipped = false })
  elseif t == 'blind_skip' then self:on_blind_end(player, slot, { won = false, hands = 0, best = 0, skipped = true })
  elseif t == 'out_of_hands' then self:on_out_of_hands(player, slot)
  elseif t == 'run_over' then self:on_run_end(player, 'lost', slot)
  elseif t == 'run_won' then self:on_run_end(player, 'won', slot)
  elseif t == 'ante_back' then self:on_ante_back(player, msg)
  elseif t == 'fail_check' then self:on_fail_check(player, slot, msg.saved == true)
  end
  self:update_gates()
end

function Lobby:remove(player)
  local idx = index_of(self.players, player)
  if not idx then return end
  table.remove(self.players, idx)
  player.lobby = nil
  if not self.started then
    self:broadcast_lobby()
    return
  end
  if player.game then player.game.status = 'left' end
  self:broadcast({ type = 'player_left', id = player.id, name = player.name })
  if self.finished then return end
  if self.mode == 'duel' then
    local other = self.players[1]
    if other then self:finish({ winnerId = other.id, reason = 'opponent_left' }) end
  else
    if #self.players == 0 then self.finished = true return end
    for s in pairs(self.coop_slots) do self:check_coop_failure(s) end
    self:check_coop_win()
  end
  self:update_gates()
end

-- ---- round gates ---------------------------------------------------------------

-- Is `other` holding up `w` (a gate some player is waiting at)?
local function blocks(other, w)
  local g = other.game
  if not g or g.status ~= 'alive' then return false end
  if w.kind == 'shop' then
    return g.results[w.slot] == nil and g.max_slot <= w.slot
  end
  return g.max_slot < w.slot -- blind gate: other hasn't reached blind w.slot yet
end

-- Release every player whose gate is clear, and tell everyone who is waiting on whom.
function Lobby:update_gates()
  if not self.started then return end
  local status = {}
  for _, p in ipairs(self.players) do
    local w = p.game and p.game.wait
    if w then
      local blockers = {}
      if p.game.status == 'alive' and not self.finished then
        for _, o in ipairs(self.players) do
          if o ~= p and blocks(o, w) then blockers[#blockers + 1] = o.name end
        end
      end
      if #blockers == 0 then
        p.game.wait = nil
        local go = { type = 'gate_go', kind = w.kind, slot = w.slot }
        if w.kind == 'blind' and self.mode == 'coop' then go.playing = #self:coop_players(w.slot) end
        p:send(go)
      else
        status[#status + 1] = { id = p.id, kind = w.kind, slot = w.slot, action = w.action, waitingFor = blockers }
      end
    end
  end
  local encoded = self.json and self.json.encode(status) or tostring(#status)
  if encoded ~= self.last_gate_status then
    self.last_gate_status = encoded
    self:broadcast({ type = 'gate_status', waiting = status })
  end
end

-- ---- duel --------------------------------------------------------------------

function Lobby:on_hand_scored(player, slot, hand, score)
  player.game.last_hand = { slot = slot, hand = hand, score = score }
  if self.mode == 'duel' then
    local opp = self:opponent(player)
    if opp then
      opp:send({ type = 'opp_hand', slot = slot, hand = hand, score = score })
    end
  else
    local s = self:coop_slot(slot)
    s.total = s.total + score
    self:broadcast({ type = 'team_score', slot = slot, from = player.id, name = player.name, hand = hand, score = score, total = s.total }, player)
  end
end

function Lobby:on_blind_end(player, slot, result)
  local g = player.game
  g.results[slot] = result
  if self.mode == 'duel' then
    local opp = self:opponent(player)
    if opp then
      opp:send({ type = 'opp_blind', slot = slot, won = result.won, hands = result.hands, best = result.best, skipped = result.skipped })
    end
    self:score_duel_slots()
    self:check_duel_outcome()
  else
    if result.skipped then g.skipping[slot] = true end
    local s = self:coop_slot(slot)
    if result.won then
      -- With different seeds, teammates can face different bosses and so different targets:
      -- the first player to beat theirs beats the blind for the whole team.
      if not s.won then self:broadcast({ type = 'team_blind_won', slot = slot, from = player.id, name = player.name }, player) end
      s.won = true
    else
      self:check_coop_failure(slot)
    end
  end
end

function Lobby:score_duel_slots()
  local a, b = self.players[1], self.players[2]
  if not a or not b then return end
  local slots = {}
  for slot in pairs(a.game.results) do slots[#slots + 1] = slot end
  table.sort(slots)
  for _, slot in ipairs(slots) do
    local ra, rb = a.game.results[slot], b.game.results[slot]
    if rb and not self.scored_slots[slot] then
      self.scored_slots[slot] = true
      local entries = { { a, ra }, { b, rb } }
      local awards = {}

      local played = list_filter(entries, function(e) return not e[2].skipped and e[2].best > 0 end)
      if #played > 0 then
        local top = 0
        for _, e in ipairs(played) do top = math.max(top, e[2].best) end
        for _, e in ipairs(played) do
          if e[2].best == top then
            e[1].game.points = e[1].game.points + 1
            awards[#awards + 1] = { id = e[1].id, kind = 'best_hand', value = top }
          end
        end
      end
      local winners = list_filter(entries, function(e) return not e[2].skipped and e[2].won end)
      if #winners > 0 then
        local fewest = math.huge
        for _, e in ipairs(winners) do fewest = math.min(fewest, e[2].hands) end
        for _, e in ipairs(winners) do
          if e[2].hands == fewest then
            e[1].game.points = e[1].game.points + 1
            awards[#awards + 1] = { id = e[1].id, kind = 'fewest_hands', value = fewest }
          end
        end
      end
      self:broadcast({ type = 'slot_result', slot = slot, awards = awards, points = self:points_table() })
    end
  end
end

function Lobby:points_table()
  local t = {}
  for _, p in ipairs(self.players) do t[p.id] = p.game and p.game.points or 0 end
  return t
end

function Lobby:check_duel_outcome()
  if self.finished or self.mode ~= 'duel' then return end
  local a, b = self.players[1], self.players[2]
  if not a or not b then return end
  local ga, gb = a.game, b.game
  local function by_points(reason)
    if ga.points == gb.points then return self:finish({ winnerId = nil, reason = reason }) end
    return self:finish({ winnerId = ga.points > gb.points and a.id or b.id, reason = reason })
  end

  if ga.status == 'won' and gb.status == 'won' then return by_points('both_won') end
  if ga.status == 'lost' and gb.status == 'lost' then
    if ga.end_slot == gb.end_slot then return by_points('both_lost_same_round') end
    return self:finish({ winnerId = ga.end_slot > gb.end_slot and a.id or b.id, reason = 'outlasted' })
  end
  for _, pair in ipairs({ { a, b }, { b, a } }) do
    local loser, other = pair[1], pair[2]
    local lg, og = loser.game, other.game
    if lg.status == 'lost' then
      if og.status == 'won' then return self:finish({ winnerId = other.id, reason = 'outlasted' }) end
      -- Other is alive: they win once they've clearly survived the loser's final round.
      local r = og.results[lg.end_slot]
      if (r and (r.won or r.skipped)) or og.max_slot > lg.end_slot then
        return self:finish({ winnerId = other.id, reason = 'outlasted' })
      end
    end
  end
end

-- ---- coop ----------------------------------------------------------------------

function Lobby:coop_slot(slot)
  if not self.coop_slots[slot] then self.coop_slots[slot] = { total = 0, won = false, failed = false } end
  return self.coop_slots[slot]
end

local function ids_where(players, pred)
  local t = {}
  for _, p in ipairs(players) do if pred(p) then t[#t + 1] = p.id end end
  return t
end

function Lobby:on_out_of_hands(player, slot)
  if self.mode ~= 'coop' then return end
  player.game.out_of_hands[slot] = true
  self:broadcast({ type = 'team_status', slot = slot,
    outOfHands = ids_where(self.players, function(p) return p.game.out_of_hands[slot] end) })
  self:check_coop_failure(slot)
end

-- A player redeemed an ante-lowering voucher: the whole team goes back with them.
-- Each client clamps at ante 1 itself.
function Lobby:on_ante_back(player, msg)
  if self.mode ~= 'coop' then return end
  local amount = math.floor(int(msg.amount, 1))
  if amount < 1 then return end
  if amount > 8 then amount = 8 end
  local voucher = type(msg.voucher) == 'string' and msg.voucher:sub(1, 40) or nil
  self:broadcast({ type = 'team_ante', amount = amount, from = player.id, name = player.name, voucher = voucher }, player)
end

-- Players still in the run who are playing blind `slot` (didn't skip it).
function Lobby:coop_players(slot)
  return list_filter(self:alive_players(), function(p) return not p.game.skipping[slot] end)
end

function Lobby:check_coop_failure(slot)
  local s = self:coop_slot(slot)
  if s.won then return end
  if s.failed then return self:resolve_coop_failure(slot) end
  local playing = self:coop_players(slot)
  if #playing == 0 then return end
  for _, p in ipairs(playing) do
    if not p.game.out_of_hands[slot] then return end
  end
  s.failed = true
  s.checks = {}
  self:broadcast({ type = 'team_failed', slot = slot })
end

function Lobby:on_fail_check(player, slot, saved)
  if self.mode ~= 'coop' then return end
  local s = self.coop_slots[slot]
  if not (s and s.failed and s.checks) or s.resolved then return end
  s.checks[player.id] = saved
  self:resolve_coop_failure(slot)
end

-- Everyone playing the failed blind has said whether they'd be saved: anyone saved saves the team.
function Lobby:resolve_coop_failure(slot)
  local s = self.coop_slots[slot]
  if not (s and s.failed and s.checks) or s.resolved then return end
  local saved = false
  for _, p in ipairs(self:coop_players(slot)) do
    local c = s.checks[p.id]
    if c == nil then return end
    if c then saved = true end
  end
  s.resolved = true
  self:broadcast({ type = 'team_fail_result', slot = slot, saved = saved })
end

-- ---- run end ---------------------------------------------------------------------

function Lobby:on_run_end(player, status, slot)
  local g = player.game
  if g.status ~= 'alive' then return end
  g.status = status
  g.end_slot = (slot and slot ~= 0) and slot or g.max_slot
  self:broadcast({ type = 'player_run_end', id = player.id, status = status, slot = g.end_slot }, player)

  if self.mode == 'duel' then
    self:check_duel_outcome()
  elseif status == 'lost' then
    self:finish({ result = 'lost', reason = self.endless and 'endless_over' or 'team_failed' })
  else
    self:check_coop_win()
  end
end

-- Co-op: once every player still in the run has beaten the final boss, the team wins.
-- The run carries on in Endless mode for whoever continues: everyone is back in play and
-- the round gates keep the team together (a player who leaves from the win screen drops out).
-- The game only ends when the team loses an endless blind.
function Lobby:check_coop_win()
  if self.finished or self.endless or self.mode ~= 'coop' or #self.players == 0 then return end
  for _, p in ipairs(self.players) do
    if not p.game or p.game.status ~= 'won' then return end
  end
  self.endless = true
  for _, p in ipairs(self.players) do
    p.game.status = 'alive'
    p.game.end_slot = nil
  end
  self:broadcast({ type = 'game_over', mode = self.mode, result = 'won', reason = 'final_boss_beaten',
    endless = true, points = self:points_table() })
end

function Lobby:finish(outcome)
  if self.finished then return end
  self.finished = true
  local msg = { type = 'game_over', mode = self.mode, points = self:points_table() }
  for k, v in pairs(outcome) do msg[k] = v end
  self:broadcast(msg)
end

-- ---------------------------------------------------------------------------
-- Relay (connections, lobby directory, invites)

local Player = {}
Player.__index = Player
function Player:send(msg) self.send_line(self.relay.json.encode(msg)) end

function Relay.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Relay)
  self.json = assert(opts.json, 'json module required')
  self.min_players = opts.min_players or 2
  self.log = opts.log or function() end
  self.lobbies = {}
  self.online = {}
  self.next_id = 1
  return self
end

function Relay:connect(send_line)
  local p = setmetatable({ relay = self, send_line = send_line, name = 'Player' }, Player)
  p.id = string.format('%d', self.next_id)
  self.next_id = self.next_id + 1
  self.online[p] = true
  return p
end

function Relay:new_code()
  while true do
    local c = rand_string(CODE_CHARS, 4)
    if not self.lobbies[c] then return c end
  end
end

function Relay:leave_lobby(player)
  local lobby = player.lobby
  if not lobby then return end
  lobby:remove(player)
  if #lobby.players == 0 then
    self.lobbies[lobby.code] = nil
    self.log('lobby ' .. lobby.code .. ' closed')
  end
end

function Relay:disconnect(player)
  self.online[player] = nil
  self:leave_lobby(player)
end

function Relay:dispatch(player, msg)
  local t = msg.type
  if t == 'ping' then return player:send({ type = 'pong' }) end
  if t == 'hello' then
    player.name = tostring(msg.name or 'Player'):sub(1, 20)
    local sid = tostring(msg.steamId or '')
    player.steam_id = (sid:match('^%d+$') and #sid >= 5 and #sid <= 20) and sid or nil
    player.protocol = tonumber(msg.protocol) or 1
    return player:send({ type = 'welcome', id = player.id, protocol = Relay.PROTOCOL_VERSION })
  end
  if (t == 'create' or t == 'join') and player.protocol ~= Relay.PROTOCOL_VERSION then
    fail('different mod version - everyone needs the latest Balatro Duel & Co-op (re-run the installer)')
  end
  if t == 'create' then
    self:leave_lobby(player)
    local code = self:new_code()
    local lobby = Lobby.new(code, player, {
      mode = msg.mode, deck = msg.deck, stake = msg.stake, seed = msg.seed, same_seed = msg.sameSeed, challenge = msg.challenge,
      min_players = self.min_players, json = self.json,
    })
    self.lobbies[code] = lobby
    self.log('lobby ' .. code .. ' created (' .. lobby.mode .. ') by ' .. player.name)
    return
  end
  if t == 'join' then
    local code = tostring(msg.code or ''):upper():gsub('%s', '')
    local lobby = self.lobbies[code]
    if not lobby then fail('no lobby with code ' .. code) end
    if player.lobby == lobby then return end
    self:leave_lobby(player)
    lobby:add(player)
    return
  end
  if t == 'leave' then return self:leave_lobby(player) end
  if t == 'start' then
    if not player.lobby then fail('not in a lobby') end
    player.lobby:start(player)
    self.log('lobby ' .. player.lobby.code .. ' started with ' .. #player.lobby.players .. ' players')
    return
  end
  if t == 'lobby_options' then
    if not player.lobby then fail('not in a lobby') end
    return player.lobby:set_options(player, msg)
  end
  if t == 'invite' then
    -- Push an in-game invite to a Steam friend who is connected to this server.
    if not player.lobby or player.lobby.started then fail('open a lobby first') end
    local sid = tostring(msg.steamId or '')
    local delivered = false
    for other in pairs(self.online) do
      if other ~= player and other.steam_id and other.steam_id == sid and not (other.lobby and other.lobby.started) then
        other:send({ type = 'invited', fromName = player.name, fromId = player.id, code = player.lobby.code, mode = player.lobby.mode })
        delivered = true
      end
    end
    return player:send({ type = 'invite_result', steamId = sid, delivered = delivered })
  end
  if player.lobby then player.lobby:handle(player, msg) end
end

function Relay:receive(player, line)
  local msg = self.json.decode(line)
  if type(msg) ~= 'table' then return player:send({ type = 'error', msg = 'bad json' }) end
  if type(msg.type) ~= 'string' then return end
  local ok, err = pcall(self.dispatch, self, player, msg)
  if not ok then player:send({ type = 'error', msg = tostring(err) }) end
end

Relay.Lobby = Lobby
return Relay
