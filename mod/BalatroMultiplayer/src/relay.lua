-- Balatro Multiplayer relay: lobbies, hand/blind gates, Duel points, win rules, invites.
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
Relay.PROTOCOL_VERSION = 1

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
  self.min_players = opts.min_players or 2
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
    seed = self.seed, started = self.started, hostId = self:host_id(), players = self:player_list(),
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
      hand_ready = nil,   -- { slot, hand } while waiting at the duel hand gate
      blind_ready = 0,    -- slot this player is waiting to start (coop gate)
      out_of_hands = {},  -- slot -> true
      points = 0,
      last_hand = nil,
    }
  end
  self.scored_slots = {}
  self.coop_slots = {}
  self:broadcast({
    type = 'start', mode = self.mode, seed = self.seed, deck = self.deck, stake = self.stake,
    playerCount = #self.players, players = self:player_list(),
  })
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
  elseif t == 'blind_ready' then self:on_blind_ready(player, slot)
  elseif t == 'hand_ready' then
    local hand = int(msg.hand, 0)
    if hand == 0 then hand = 1 end
    self:on_hand_ready(player, slot, hand)
  elseif t == 'hand_scored' then self:on_hand_scored(player, slot, int(msg.hand, 0), math.max(0, int(msg.score, 0)))
  elseif t == 'blind_end' then
    self:on_blind_end(player, slot, { won = msg.won == true, hands = int(msg.hands, 0), best = int(msg.best, 0), skipped = false })
  elseif t == 'blind_skip' then self:on_blind_end(player, slot, { won = false, hands = 0, best = 0, skipped = true })
  elseif t == 'out_of_hands' then self:on_out_of_hands(player, slot)
  elseif t == 'run_over' then self:on_run_end(player, 'lost', slot)
  elseif t == 'run_won' then self:on_run_end(player, 'won', slot)
  end
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
    self:release_coop_blind_gates()
    for s in pairs(self.coop_slots) do self:check_coop_failure(s) end
  end
end

-- ---- duel --------------------------------------------------------------------

-- An opponent "is past" a slot if it no longer makes sense to wait for them there.
function Lobby:duel_past(opp, slot)
  local g = opp.game
  if not g or g.status ~= 'alive' then return true end
  return g.results[slot] ~= nil or g.max_slot > slot
end

function Lobby:on_hand_ready(player, slot, hand)
  if self.mode ~= 'duel' then return end
  player.game.hand_ready = { slot = slot, hand = hand }
  self:try_release_hand(player)
  local opp = self:opponent(player)
  if opp then self:try_release_hand(opp) end
end

function Lobby:try_release_hand(player)
  local r = player.game.hand_ready
  if not r then return end
  local opp = self:opponent(player)
  local og = opp and opp.game
  local function release(p)
    local pr = p.game.hand_ready
    p.game.hand_ready = nil
    p:send({ type = 'hand_go', slot = pr.slot, hand = pr.hand })
  end
  if og and og.hand_ready and og.hand_ready.slot == r.slot and og.hand_ready.hand == r.hand then
    release(player)
    release(opp)
    return
  end
  local opp_already_played = og and og.last_hand and og.last_hand.slot == r.slot and og.last_hand.hand >= r.hand
  if not opp or opp_already_played or self:duel_past(opp, r.slot) then release(player) end
end

function Lobby:on_hand_scored(player, slot, hand, score)
  player.game.last_hand = { slot = slot, hand = hand, score = score }
  if self.mode == 'duel' then
    local opp = self:opponent(player)
    if opp then
      opp:send({ type = 'opp_hand', slot = slot, hand = hand, score = score })
      self:try_release_hand(opp)
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
  g.hand_ready = nil
  if self.mode == 'duel' then
    local opp = self:opponent(player)
    if opp then
      opp:send({ type = 'opp_blind', slot = slot, won = result.won, hands = result.hands, best = result.best, skipped = result.skipped })
      self:try_release_hand(opp)
    end
    self:score_duel_slots()
    self:check_duel_outcome()
  else
    local s = self:coop_slot(slot)
    if result.won then s.won = true
    elseif not result.skipped then self:check_coop_failure(slot) end
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

function Lobby:on_blind_ready(player, slot)
  if self.mode ~= 'coop' then
    player:send({ type = 'blind_go', slot = slot })
    return
  end
  player.game.blind_ready = slot
  self:broadcast({ type = 'team_status', slot = slot,
    waiting = ids_where(self.players, function(p) return p.game.blind_ready == slot end) })
  self:release_coop_blind_gates()
end

function Lobby:release_coop_blind_gates()
  local alive = self:alive_players()
  local slots = {}
  for _, p in ipairs(alive) do
    if p.game.blind_ready and p.game.blind_ready ~= 0 then slots[p.game.blind_ready] = true end
  end
  for slot in pairs(slots) do
    local all = true
    for _, p in ipairs(alive) do if p.game.blind_ready ~= slot then all = false end end
    if all then
      for _, p in ipairs(alive) do p.game.blind_ready = 0 end
      self:broadcast({ type = 'blind_go', slot = slot })
    end
  end
end

function Lobby:on_out_of_hands(player, slot)
  if self.mode ~= 'coop' then return end
  player.game.out_of_hands[slot] = true
  self:broadcast({ type = 'team_status', slot = slot,
    outOfHands = ids_where(self.players, function(p) return p.game.out_of_hands[slot] end) })
  self:check_coop_failure(slot)
end

function Lobby:check_coop_failure(slot)
  local s = self:coop_slot(slot)
  if s.won or s.failed then return end
  local alive = self:alive_players()
  if #alive == 0 then return end
  for _, p in ipairs(alive) do
    if not p.game.out_of_hands[slot] then return end
  end
  s.failed = true
  self:broadcast({ type = 'team_failed', slot = slot })
end

-- ---- run end ---------------------------------------------------------------------

function Lobby:on_run_end(player, status, slot)
  local g = player.game
  if g.status ~= 'alive' then return end
  g.status = status
  g.end_slot = (slot and slot ~= 0) and slot or g.max_slot
  self:broadcast({ type = 'player_run_end', id = player.id, status = status, slot = g.end_slot }, player)

  if self.mode == 'duel' then
    local opp = self:opponent(player)
    if opp then self:try_release_hand(opp) end
    self:check_duel_outcome()
  elseif status == 'lost' then
    self:finish({ result = 'lost', reason = 'team_failed' })
  else
    local all_won = true
    for _, p in ipairs(self.players) do if p.game.status ~= 'won' then all_won = false end end
    if all_won then
      self:finish({ result = 'won', reason = 'final_boss_beaten' })
    else
      self:release_coop_blind_gates()
    end
  end
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
    return player:send({ type = 'welcome', id = player.id, protocol = Relay.PROTOCOL_VERSION })
  end
  if t == 'create' then
    self:leave_lobby(player)
    local code = self:new_code()
    local lobby = Lobby.new(code, player, {
      mode = msg.mode, deck = msg.deck, stake = msg.stake, seed = msg.seed, min_players = self.min_players,
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
