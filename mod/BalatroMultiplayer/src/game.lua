-- Core multiplayer state, server message handling and game hooks.

local Net = MP.net

MP.lobby = nil      -- latest 'lobby' message from the server
MP.my_id = nil
MP.run = nil        -- non-nil while a multiplayer run is in progress
MP.toasts = {}      -- short-lived HUD notifications

function MP.toast(text, colour)
  table.insert(MP.toasts, { text = text, t = 0, colour = colour })
  if #MP.toasts > 5 then table.remove(MP.toasts, 1) end
end

function MP.in_game()
  return MP.run ~= nil and not MP.run.finished and G.STAGE == G.STAGES.RUN
end

function MP.send(msg)
  return Net.send(msg)
end

function MP.player_name(id)
  if MP.run then
    for _, p in ipairs(MP.run.players) do
      if tostring(p.id) == tostring(id) then return p.name end
    end
  end
  if MP.lobby then
    for _, p in ipairs(MP.lobby.players or {}) do
      if tostring(p.id) == tostring(id) then return p.name end
    end
  end
  return 'Player ' .. tostring(id)
end

local function lock(name, on)
  if G.CONTROLLER and G.CONTROLLER.locks then G.CONTROLLER.locks[name] = on or nil end
end

-- ---------------------------------------------------------------------------
-- Connection / lobby actions

-- Where we're connected. Three ways to play:
--   * host: we run the relay in-game (host.lua) and connect to it on 127.0.0.1;
--     friends reach it through Steam P2P (p2p.lua)
--   * joined: connected to a friend's in-game server through Steam ("steam:<id>"),
--     or to a host:port from an invite
--   * dedicated: a standalone server set under Advanced (config.server_host)
MP.target = nil -- { host, port, kind = 'host' | 'joined' | 'dedicated', steam = id? }

function MP.connect_to(host, port, kind)
  if Net.status ~= 'disconnected' then Net.disconnect() end
  MP.target = { host = host, port = tostring(port), kind = kind }
  Net.connect(host, tonumber(port) or 8788)
end

function MP.connect_steam(id)
  if Net.status ~= 'disconnected' then Net.disconnect() end
  MP.target = { host = 'steam:' .. id, port = '', kind = 'joined', steam = id }
  Net.connect_steam(id)
end

-- "steam:<id>" or "host:port" for the server we're connected to.
local function target_label(t)
  if not t then return 'server' end
  return t.steam and "your friend's game" or (t.host .. ':' .. t.port)
end

function MP.has_dedicated_server()
  return tostring(MP.config.server_host or '') ~= ''
end

-- Used by the Advanced screen's Connect button and auto-connect.
function MP.connect()
  if MP.has_dedicated_server() then
    MP.connect_to(MP.config.server_host, MP.config.server_port, 'dedicated')
  end
end

-- The "host:port" friends should use to reach the lobby we're in (nil if not reachable yet).
function MP.server_string()
  local t = MP.target
  if not t then return nil end
  if t.kind == 'host' then return MP.host.public_address() end
  if t.steam then return 'steam:' .. t.steam end
  return t.host .. ':' .. t.port
end

local function save_config()
  if SMODS and SMODS.save_mod_config and MP.mod then pcall(SMODS.save_mod_config, MP.mod) end
end
MP.save_config = save_config

-- Join a lobby; `server` is the lobby's server from an invite or the friends list:
-- "steam:<id>" for a friend hosting in-game, or "host:port".
function MP.join_lobby(code, server)
  code = tostring(code or ''):upper():gsub('%s', '')
  if code == '' then return end
  MP.pending_invite = nil
  local steam_id = tostring(server or ''):match('^steam:(%d+)$')
  local host, port = tostring(server or ''):match('^(.+):(%d+)$')
  local t = MP.target
  if steam_id then
    if steam_id == (MP.steam and MP.steam.my_id and MP.steam.my_id()) then
      MP.UI.last_error = "That's your own lobby"
    elseif t and t.steam == steam_id and Net.status ~= 'disconnected' then
      if Net.status == 'connected' then MP.send({ type = 'join', code = code }) else MP.pending_join = code end
    else
      MP.pending_join = code
      MP.connect_steam(steam_id)
    end
    MP.UI.refresh()
    return
  end
  local same = t and host and t.host == host and t.port == port
  if host and not same then
    MP.pending_join = code
    MP.connect_to(host, port, 'joined')
  elseif not host and not t then
    if MP.has_dedicated_server() then
      MP.pending_join = code
      MP.connect()
    else
      MP.UI.last_error = 'Join from your Steam friends list, or paste a CODE@host:port invite for a dedicated server'
    end
  elseif Net.status ~= 'connected' then
    MP.pending_join = code
  else
    MP.send({ type = 'join', code = code })
  end
  MP.UI.refresh()
end

-- Create a lobby: on our dedicated server if one is set, otherwise host it ourselves.
function MP.create_lobby(params)
  MP.UI.creating = true
  if MP.target and MP.target.kind ~= 'joined' and Net.status == 'connected' then
    MP.send(params)
    return
  end
  MP.pending_create = params
  if MP.has_dedicated_server() then
    MP.connect()
  elseif MP.host.running() then
    MP.connect_to('127.0.0.1', MP.host.port(), 'host')
  else
    MP.host.start() -- MP.on_host_listening connects us once the server is up
  end
end

function MP.on_host_listening()
  if MP.pending_create and not (MP.target and MP.target.kind == 'host' and Net.status ~= 'disconnected') then
    MP.connect_to('127.0.0.1', MP.host.port(), 'host')
  end
  if MP.UI.flush_invites then MP.UI.flush_invites() end
end

function MP.on_host_failed(msg)
  MP.pending_create = nil
  MP.UI.creating = false
  MP.UI.last_error = 'Could not host: ' .. tostring(msg)
end

local function update_presence()
  if not (MP.steam and MP.steam.ok) then return end
  pcall(MP.steam.set_lobby_presence, MP.lobby, MP.server_string(), MP.UI and MP.UI.invited_ids and MP.UI.invited_ids() or nil)
end
MP.update_presence = update_presence


local function on_status(status)
  if status == 'connected' then
    local steam_id = MP.steam and MP.steam.my_id and MP.steam.my_id() or nil
    MP.send({ type = 'hello', name = MP.display_name(), steamId = steam_id, protocol = MP.PROTOCOL })
  else
    if MP.pending_join or MP.pending_create then
      local t = MP.target
      MP.UI.last_error = 'Could not connect to ' .. target_label(t) ..
        (Net.error and (' (' .. tostring(Net.error) .. ')') or '') ..
        (t and t.kind == 'dedicated' and ' - check Advanced, or clear the server to host in-game' or '')
      MP.UI.creating = false
    end
    MP.pending_join, MP.pending_create = nil, nil
    MP.lobby = nil
    update_presence()
    if MP.run and not MP.run.finished then
      MP.run.disconnected = true
      MP.release_all_gates()
      MP.toast('Disconnected from server', G.C.RED)
    end
  end
  MP.UI.refresh()
end

-- Round gates: cashing out (-> shop) and selecting/skipping the next blind wait until
-- every other player still in the run has caught up. Hands are never gated.
local function run_gate(w)
  if w.kind == 'shop' then
    MP.orig.cash_out(w.e)
  elseif w.action == 'skip' then
    MP.skip_blind_now(w.e)
  else
    MP.begin_blind(w.e)
  end
end

function MP.release_gate(kind, slot)
  local run = MP.run
  local w = run and run.gate
  if not w or (kind and (w.kind ~= kind or w.slot ~= slot)) then return end
  run.gate = nil
  run.gate_waiting_for = nil
  lock('mp_gate', false)
  run_gate(w)
end

function MP.release_all_gates()
  if MP.run then MP.release_gate() end
  lock('mp_gate', false)
end

-- Hold `e`'s action until the server says everyone is ready. Returns false if no gate applies.
local function hold_at_gate(kind, slot, e, action)
  local run = MP.run
  if not MP.in_game() or run.disconnected or Net.status ~= 'connected' then return false end
  if run.gate then return true end -- already waiting; ignore repeat clicks
  run.gate = { kind = kind, slot = slot, e = e, action = action }
  run.gate_waiting_for = nil
  lock('mp_gate', true)
  MP.send({ type = kind == 'shop' and 'shop_ready' or 'blind_ready', slot = slot })
  return true
end

-- ---------------------------------------------------------------------------
-- Starting a run

local function new_run(msg)
  return {
    mode = msg.mode,
    seed = msg.seed,
    players = msg.players or {},
    player_count = msg.playerCount or #(msg.players or {}),
    slot = 0,          -- nth blind of the run (selected or skipped)
    hands = 0,         -- hands played in the current blind
    best = 0,          -- best single hand in the current blind
    points = {},       -- duel points by player id
    opp = { hands = 0, last = nil, best = 0, slot = 0, status = 'alive' },
    team = {},         -- coop: id -> { last, total }
    team_total = 0,    -- coop: teammates' contribution to the current blind
    pending = {},      -- coop: teammate scores not yet applied { slot, score, name }
    history = {},      -- one record per blind slot: { slot, ante, blind, hands = {scores}, best, total, won, skipped }
    snapshots = {},    -- other players' latest state: id -> { data, name, t }
    snap_timer = 0,
    finished = false,
    result = nil,
  }
end

function MP.start_game(msg)
  MP.run = new_run(msg)
  if MP.lobby then MP.lobby.started = true end
  update_presence()
  if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
  local center = G.P_CENTERS[msg.deck] or G.P_CENTERS.b_red
  G.GAME.viewed_back = Back(center)
  MP.starting_run = true
  G.FUNCS.start_run(nil, { stake = tonumber(msg.stake) or 1, seed = msg.seed, deck_choice = { name = center.name } })
  MP.starting_run = false
  MP.toast((msg.mode == 'duel' and 'Duel' or 'Co-op') .. ' started! Seed ' .. tostring(msg.seed), G.C.GREEN)
end

-- ---------------------------------------------------------------------------
-- Incoming messages

local handlers = {}

handlers.welcome = function(m)
  if tonumber(m.protocol) ~= MP.PROTOCOL then
    MP.pending_join, MP.pending_create = nil, nil
    MP.UI.creating = false
    MP.UI.last_error = 'That game runs a different version of the mod. Everyone needs the latest version (re-run the installer).'
    MP.toast(MP.UI.last_error, G.C.RED)
    Net.disconnect()
    MP.UI.refresh()
    return
  end
  MP.my_id = tostring(m.id)
  if MP.pending_join then
    MP.send({ type = 'join', code = MP.pending_join })
    MP.pending_join = nil
  end
  if MP.pending_create then
    MP.send(MP.pending_create)
    MP.pending_create = nil
  end
end

handlers.invited = function(m)
  if MP.lobby and tostring(MP.lobby.code) == tostring(m.code) then return end
  MP.pending_invite = { code = m.code, mode = m.mode, from = m.fromName, server = MP.server_string() }
  local mode = m.mode == 'duel' and 'Duel' or 'Co-op'
  MP.toast(tostring(m.fromName) .. ' invited you to a ' .. mode .. '!', G.C.GOLD)
  if G.STAGE == G.STAGES.MAIN_MENU then
    if not G.OVERLAY_MENU then MP.UI.open() else MP.UI.refresh() end
  else
    MP.toast('Open Multiplayer from the main menu to join', G.C.GOLD)
  end
end

handlers.invite_result = function(m)
  if m.delivered then MP.toast('Invite popped up in their game', G.C.GREEN) end
end

handlers.player_snapshot = function(m)
  if not MP.run or type(m.data) ~= 'table' then return end
  MP.run.snapshots[tostring(m.id)] = { data = m.data, name = m.name, t = love.timer.getTime() }
end
handlers.pong = function() end
handlers.error = function(m) MP.UI.creating = false; MP.toast('Server: ' .. tostring(m.msg), G.C.RED); MP.UI.last_error = m.msg; MP.UI.refresh() end
handlers.lobby = function(m)
  MP.lobby = m
  MP.UI.creating = false
  if MP.pending_invite and tostring(MP.pending_invite.code) == tostring(m.code) then MP.pending_invite = nil end
  update_presence()
  MP.UI.refresh()
end
handlers.start = function(m) MP.start_game(m) end

handlers.player_left = function(m)
  MP.toast(tostring(m.name) .. ' left the game', G.C.RED)
  if MP.run then
    for i, p in ipairs(MP.run.players) do
      if tostring(p.id) == tostring(m.id) then table.remove(MP.run.players, i) break end
    end
  end
end

-- Duel ------------------------------------------------------------------------

handlers.gate_go = function(m)
  MP.release_gate(m.kind, tonumber(m.slot))
end

handlers.gate_status = function(m)
  local run = MP.run
  if not run then return end
  run.gate_waiting_for = nil
  for _, w in pairs(m.waiting or {}) do
    if tostring(w.id) == MP.my_id then run.gate_waiting_for = w.waitingFor end
  end
end

handlers.opp_hand = function(m)
  local run = MP.run
  if not run then return end
  run.opp.last = m.score
  run.opp.hands = m.hand
  run.opp.slot = m.slot
  if m.slot == run.slot then run.opp.best = math.max(run.opp.best or 0, m.score or 0) end
end

handlers.opp_blind_start = function(m)
  if MP.run then MP.run.opp.slot = m.slot; MP.run.opp.hands = 0 end
end

handlers.opp_blind = function(m)
  local run = MP.run
  if not run then return end
  if m.skipped then MP.toast('Opponent skipped the blind')
  elseif m.won then MP.toast('Opponent beat the blind in ' .. tostring(m.hands) .. ' hand(s)')
  else MP.toast('Opponent failed the blind', G.C.RED) end
end

handlers.slot_result = function(m)
  local run = MP.run
  if not run then return end
  run.points = m.points or run.points
  for _, a in ipairs(m.awards or {}) do
    local who = tostring(a.id) == MP.my_id and 'You' or MP.player_name(a.id)
    local what = a.kind == 'best_hand' and ('best hand (' .. MP.fmt(a.value) .. ')') or ('fewest hands (' .. tostring(a.value) .. ')')
    MP.toast(who .. ' +1 point: ' .. what, tostring(a.id) == MP.my_id and G.C.GREEN or G.C.RED)
  end
end

handlers.player_run_end = function(m)
  if not MP.run then return end
  if MP.run.mode == 'duel' then
    MP.run.opp.status = m.status
    MP.toast(m.status == 'won' and 'Opponent beat the final boss!' or 'Opponent\'s run ended!', G.C.ORANGE)
  else
    MP.toast(MP.player_name(m.id) .. (m.status == 'won' and ' won!' or ' lost!'), G.C.ORANGE)
  end
end

-- Co-op -----------------------------------------------------------------------

handlers.team_score = function(m)
  local run = MP.run
  if not run then return end
  local t = run.team[tostring(m.from)] or { total = 0 }
  t.last = m.score
  run.team[tostring(m.from)] = t
  table.insert(run.pending, { slot = tonumber(m.slot), score = tonumber(m.score) or 0, name = m.name })
end

handlers.team_status = function(m)
  if MP.run then MP.run.team_status = m end
end

handlers.team_failed = function(m)
  local run = MP.run
  if not run then return end
  run.team_failed_slot = tonumber(m.slot)
end

-- Game over ---------------------------------------------------------------------

handlers.game_over = function(m)
  local run = MP.run
  if not run then return end
  run.finished = true
  run.result = m
  run.points = m.points or run.points
  MP.release_all_gates()
end

local function on_message(m)
  local h = handlers[m.type]
  if h then
    local ok, err = pcall(h, m)
    if not ok then print('[BalatroMultiplayer] handler error for ' .. tostring(m.type) .. ': ' .. tostring(err)) end
  end
end

-- ---------------------------------------------------------------------------
-- Helpers

function MP.fmt(n)
  if number_format then return number_format(n or 0) end
  return tostring(n or 0)
end

local function blind_target()
  return G.GAME and G.GAME.blind and G.GAME.blind.chips or 0
end

local function score_of_current_hand()
  -- Steamodded records the final score synchronously at the end of evaluate_play.
  if SMODS and type(SMODS.last_hand_score) == 'number' then
    return math.floor(SMODS.last_hand_score)
  end
  if SMODS and SMODS.calculate_round_score then
    local ok, v = pcall(SMODS.calculate_round_score)
    if ok and type(v) == 'number' then return math.floor(v) end
  end
  if type(hand_chips) == 'number' and type(mult) == 'number' then
    return math.floor(hand_chips * mult)
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- History + snapshots (what other players see in the player viewer)

function MP.blind_name()
  local b = G.GAME and G.GAME.blind
  if not b then return nil end
  if b.config and b.config.blind and b.config.blind.key then
    local ok, name = pcall(localize, { type = 'name_text', set = 'Blind', key = b.config.blind.key })
    if ok and name and name ~= 'ERROR' then return name end
  end
  return b.name
end

local function current_record()
  local run = MP.run
  local rec = run and run.history[#run.history]
  if rec and rec.slot == run.slot then return rec end
end

local function start_record(skipped)
  local run = MP.run
  run.history[#run.history + 1] = {
    slot = run.slot,
    ante = G.GAME.round_resets and G.GAME.round_resets.ante or 0,
    blind = skipped and ((G.GAME.blind_on_deck or '') .. ' Blind') or nil,
    hands = {}, best = 0, total = 0, skipped = skipped or nil,
  }
end

local function record_hand(score)
  local rec = current_record()
  if not rec then return end
  rec.blind = rec.blind or MP.blind_name()
  rec.hands[#rec.hands + 1] = score
  rec.best = math.max(rec.best, score)
  rec.total = rec.total + score
end

local function record_end(won)
  local rec = current_record()
  if not rec then return end
  rec.blind = rec.blind or MP.blind_name()
  rec.won = won
  rec.target = G.GAME.blind and G.GAME.blind.chips or nil
end

-- Copy plain data only (no objects/functions), bounded in depth and size.
local function sanitize(v, depth)
  local t = type(v)
  if t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
  elseif t == 'string' or t == 'boolean' then
    return v
  elseif t == 'table' and depth > 0 and getmetatable(v) == nil then
    local out, n = {}, 0
    for k, val in pairs(v) do
      local kt = type(k)
      if kt == 'string' or kt == 'number' then
        local s = sanitize(val, depth - 1)
        if s ~= nil then
          out[k] = s
          n = n + 1
          if n >= 48 then break end
        end
      end
    end
    return out
  end
  return nil
end

local function edition_key(card)
  local e = card.edition
  if type(e) ~= 'table' then return nil end
  if e.key then return e.key end
  if e.type then return 'e_' .. e.type end
  for _, k in ipairs({ 'foil', 'holo', 'polychrome', 'negative' }) do
    if e[k] then return 'e_' .. k end
  end
end

-- G.P_CARDS key ("H_K") of a playing card's current suit and rank (Strength, Sigil etc.
-- change them after creation, so config.card_key alone can be stale).
local function card_key_of(c)
  local cc = c.config and c.config.card
  if cc and SMODS and SMODS.Suits and SMODS.Ranks then
    local su, ra = SMODS.Suits[cc.suit], SMODS.Ranks[cc.value]
    if su and ra and su.card_key and ra.card_key then
      local k = su.card_key .. '_' .. ra.card_key
      if G.P_CARDS[k] then return k end
    end
  end
  return c.config and c.config.card_key
end

-- Permanent upgrades on a playing card (Hiker's +chips, etc.): only the perm_* fields,
-- the rest comes from the card's enhancement.
local function perm_ability(c)
  local out
  for k, v in pairs(c.ability or {}) do
    if type(k) == 'string' and k:sub(1, 5) == 'perm_' and type(v) == 'number' and v ~= 0 and v == v then
      out = out or {}
      out[k] = v
    end
  end
  return out
end

local function playing_card_data(c, full_ability)
  return {
    c = card_key_of(c),
    e = c.config.center and c.config.center.key or nil,
    s = c.seal or nil,
    ed = edition_key(c),
    ab = full_ability and sanitize(c.ability, 3) or perm_ability(c),
  }
end

local function cards_of(area, playing)
  local out = {}
  if not (area and area.cards) then return out end
  for _, c in ipairs(area.cards) do
    if playing and c.facing == 'back' then
      out[#out + 1] = { hidden = true } -- face-down (e.g. The House): don't reveal it
    elseif playing then
      out[#out + 1] = playing_card_data(c, true)
    else
      out[#out + 1] = {
        k = c.config.center and c.config.center.key or nil,
        ed = edition_key(c),
        ab = sanitize(c.ability, 3),
      }
    end
  end
  return out
end

-- Every card the player owns (G.playing_cards), wherever it currently is.
local function full_deck()
  local out = {}
  for _, c in ipairs(G.playing_cards or {}) do out[#out + 1] = playing_card_data(c, false) end
  return out
end

local function voucher_keys()
  local out = {}
  for k, v in pairs(G.GAME.used_vouchers or {}) do
    if v and G.P_CENTERS[k] then out[#out + 1] = k end
  end
  table.sort(out, function(a, b) return (G.P_CENTERS[a].order or 0) < (G.P_CENTERS[b].order or 0) end)
  return out
end

local function tag_keys()
  local out = {}
  for _, t in ipairs(G.GAME.tags or {}) do
    if type(t) == 'table' and t.key then out[#out + 1] = t.key end
  end
  return out
end

local STATE_NAMES
local function state_name()
  if not STATE_NAMES then
    local S = G.STATES
    STATE_NAMES = {
      [S.SELECTING_HAND] = 'In blind', [S.HAND_PLAYED] = 'In blind', [S.DRAW_TO_HAND] = 'In blind',
      [S.NEW_ROUND] = 'In blind', [S.ROUND_EVAL] = 'Cashing out', [S.SHOP] = 'Shopping',
      [S.BLIND_SELECT] = 'Choosing blind', [S.GAME_OVER] = 'Game over',
      [S.TAROT_PACK] = 'Opening pack', [S.PLANET_PACK] = 'Opening pack', [S.SPECTRAL_PACK] = 'Opening pack',
      [S.STANDARD_PACK] = 'Opening pack', [S.BUFFOON_PACK] = 'Opening pack',
    }
  end
  if MP.run and MP.run.coop_waiting then return 'Out of hands' end
  return STATE_NAMES[G.STATE] or (G.STATE and G.STATE > 900 and 'Opening pack') or 'Playing'
end

function MP.build_snapshot()
  local g, run = G.GAME, MP.run
  -- Every poker hand that's visible in the run info screen, in its usual order.
  local hands = {}
  for name, h in pairs(g.hands or {}) do
    if h.visible ~= false or (h.played or 0) > 0 then
      hands[#hands + 1] = { n = name, l = h.level, p = h.played, c = h.chips, m = h.mult, o = h.order }
    end
  end
  table.sort(hands, function(a, b) return (a.o or 99) < (b.o or 99) end)

  local best = 0
  for _, rec in ipairs(run.history) do best = math.max(best, rec.best or 0) end
  local in_blind = state_name() == 'In blind' or state_name() == 'Out of hands'
  local deck_key = g.selected_back and g.selected_back.effect and g.selected_back.effect.center and g.selected_back.effect.center.key

  return {
    ante = g.round_resets and g.round_resets.ante, round = g.round, slot = run.slot,
    money = g.dollars, state = state_name(),
    hands_left = g.current_round and g.current_round.hands_left,
    discards_left = g.current_round and g.current_round.discards_left,
    chips = in_blind and g.chips or nil, target = in_blind and g.blind and g.blind.chips or nil,
    blind = in_blind and MP.blind_name() or nil,
    deck = deck_key,
    deck_count = G.deck and G.deck.cards and #G.deck.cards or 0,
    deck_total = G.playing_cards and #G.playing_cards or 0,
    joker_slots = G.jokers and G.jokers.config.card_limit, cons_slots = G.consumeables and G.consumeables.config.card_limit,
    jokers = cards_of(G.jokers), cons = cards_of(G.consumeables), hand = cards_of(G.hand, true),
    hand_size = G.hand and G.hand.config and G.hand.config.card_limit,
    full_deck = full_deck(),
    vouchers = voucher_keys(),
    tags = tag_keys(),
    poker_hands = hands,
    best = best,
    history = run.history,
    status = run.reported_end and (g.won and 'won' or 'lost') or 'alive',
  }
end

local function maybe_send_snapshot(dt)
  local run = MP.run
  if not run or G.STAGE ~= G.STAGES.RUN or not G.GAME then return end
  run.snap_timer = run.snap_timer + dt
  if run.snap_timer < 1 then return end
  run.snap_timer = 0
  local ok, snap = pcall(MP.build_snapshot)
  if not ok then return end
  local ok2, encoded = pcall(MP.json.encode, snap)
  if ok2 and encoded ~= run.last_snapshot then
    run.last_snapshot = encoded
    run.my_snapshot = snap
    MP.send({ type = 'snapshot', data = snap })
  end
end

-- ---------------------------------------------------------------------------
-- Gated actions

function MP.begin_blind(e)
  local run = MP.run
  run.slot = run.slot + 1
  start_record(false)
  run.hands = 0
  run.best = 0
  run.team_total = 0
  run.coop_waiting = nil
  run.team_failed_slot = nil
  run.opp.best = 0
  if run.mode == 'duel' then MP.send({ type = 'blind_start', slot = run.slot }) end
  MP.orig.select_blind(e)
end

function MP.skip_blind_now(e)
  local run = MP.run
  run.slot = run.slot + 1
  start_record(true)
  MP.send({ type = 'blind_skip', slot = run.slot })
  MP.orig.skip_blind(e)
end

-- ---------------------------------------------------------------------------
-- Hooks

MP.orig = {}

function MP.install_hooks()
  local orig = MP.orig

  -- Starting the next blind waits until every player is ready for it (round gate).
  orig.select_blind = G.FUNCS.select_blind
  G.FUNCS.select_blind = function(e)
    local run = MP.run
    if not run then return orig.select_blind(e) end
    if hold_at_gate('blind', run.slot + 1, e, 'select') then return end
    return MP.begin_blind(e)
  end

  orig.skip_blind = G.FUNCS.skip_blind
  G.FUNCS.skip_blind = function(e)
    local run = MP.run
    if not MP.in_game() then return orig.skip_blind(e) end
    if run.mode == 'coop' then
      MP.toast('Skipping blinds is disabled in Co-op', G.C.RED)
      return
    end
    if hold_at_gate('blind', run.slot + 1, e, 'skip') then return end
    return MP.skip_blind_now(e)
  end

  -- Going to the shop waits until every player has finished this blind (round gate).
  orig.cash_out = G.FUNCS.cash_out
  G.FUNCS.cash_out = function(e)
    local run = MP.run
    if run and hold_at_gate('shop', run.slot, e) then return end
    return orig.cash_out(e)
  end

  -- Hands are played freely: just count them.
  orig.play_cards_from_highlighted = G.FUNCS.play_cards_from_highlighted
  G.FUNCS.play_cards_from_highlighted = function(e)
    local run = MP.run
    if run and MP.in_game() and not (G.play and G.play.cards[1]) then run.hands = run.hands + 1 end
    return orig.play_cards_from_highlighted(e)
  end

  -- Scoring: hand_chips/mult are final once evaluate_play returns (events only animate)
  orig.evaluate_play = G.FUNCS.evaluate_play
  G.FUNCS.evaluate_play = function(e)
    local ret = orig.evaluate_play(e)
    local run = MP.run
    if run and MP.in_game() then
      local score = score_of_current_hand()
      run.best = math.max(run.best, score)
      run.last_hand = score
      record_hand(score)
      MP.send({ type = 'hand_scored', slot = run.slot, hand = run.hands, score = score })
    end
    return ret
  end

  -- Co-op: blind requirement scales with the number of players
  orig.set_blind = Blind.set_blind
  function Blind:set_blind(blind, reset, silent)
    local ret = orig.set_blind(self, blind, reset, silent)
    local run = MP.run
    if run and run.mode == 'coop' and (run.player_count or 1) > 1 and blind and not reset and (self.chips or 0) > 0 then
      self.chips = self.chips * run.player_count
      self.chip_text = number_format(self.chips)
    end
    return ret
  end

  -- End of blind
  orig.end_round = end_round
  end_round = function()
    local run = MP.run
    if not run or not MP.in_game() then return orig.end_round() end
    local won = G.GAME.chips - blind_target() >= 0
    if run.mode == 'coop' and not won and not run.force_fail and not run.disconnected then
      -- Out of hands but teammates may still carry the blind: wait instead of losing.
      if run.coop_waiting ~= run.slot then
        run.coop_waiting = run.slot
        MP.send({ type = 'out_of_hands', slot = run.slot })
      end
      return
    end
    run.coop_waiting = nil
    run.force_fail = nil
    record_end(won)
    MP.send({ type = 'blind_end', slot = run.slot, won = won, hands = run.hands, best = run.best })
    return orig.end_round()
  end

  orig.update_game_over = Game.update_game_over
  function Game:update_game_over(dt)
    local run = MP.run
    if run and not run.reported_end and not G.STATE_COMPLETE then
      run.reported_end = true
      MP.send({ type = 'run_over', slot = run.slot })
    end
    return orig.update_game_over(self, dt)
  end

  orig.win_game = win_game
  win_game = function()
    local run = MP.run
    if run and not run.reported_end then
      run.reported_end = true
      MP.send({ type = 'run_won', slot = run.slot })
    end
    return orig.win_game()
  end

  -- Multiplayer runs are not resumable; don't overwrite the single-player save.
  orig.save_run = save_run
  save_run = function(...)
    if MP.run then return end
    return orig.save_run(...)
  end

  -- Leaving the run forfeits / leaves the lobby.
  orig.go_to_menu = G.FUNCS.go_to_menu
  G.FUNCS.go_to_menu = function(e)
    if MP.run then
      MP.send({ type = 'leave' })
      MP.run = nil
      MP.lobby = nil
      lock('mp_gate', false)
      update_presence()
    end
    return orig.go_to_menu(e)
  end

  -- Any run started outside of MP.start_game (e.g. "New Run" on the game-over
  -- screen) is single-player: drop multiplayer state so the hooks go inert.
  orig.start_run = G.FUNCS.start_run
  G.FUNCS.start_run = function(e, args)
    if MP.run and not MP.starting_run then
      MP.send({ type = 'leave' })
      MP.run = nil
      MP.lobby = nil
      lock('mp_gate', false)
      update_presence()
    end
    return orig.start_run(e, args)
  end

  orig.update = Game.update
  function Game:update(dt)
    orig.update(self, dt)
    MP.update(dt)
  end
end

-- ---------------------------------------------------------------------------
-- Per-frame logic

local function events_idle()
  return G.E_MANAGER and G.E_MANAGER.queues and #G.E_MANAGER.queues.base == 0
end

local function startup()
  MP.started_up = true
  if MP.steam then MP.steam.init() end
  pcall(MP.host.cleanup_legacy)
  -- Accepted a Steam invite while the game was closed: Steam launched us with "+mp_join CODE host:port".
  local ok, launch = pcall(function() return MP.steam and MP.steam.launch_join() end)
  if ok and launch then
    MP.toast('Joining lobby ' .. launch.code .. '...', G.C.GOLD)
    MP.join_lobby(launch.code, launch.server)
    MP.UI.open()
  elseif MP.config.auto_connect ~= false and MP.has_dedicated_server() then
    MP.connect() -- so in-game invites can reach us
  end
  -- Closing Balatro stops the in-game server (and tells connected friends).
  local orig_quit = love.quit
  love.quit = function(...)
    pcall(MP.host.stop)
    if orig_quit then return orig_quit(...) end
  end
end

function MP.update(dt)
  if not MP.started_up and G.STAGE == G.STAGES.MAIN_MENU then startup() end
  if MP.p2p then MP.p2p.update(dt) end
  Net.poll(dt, on_message, on_status)
  MP.host.update(dt)
  maybe_send_snapshot(dt)
  if MP.viewer then MP.viewer.update() end
  if MP.UI.update then MP.UI.update() end

  for i = #MP.toasts, 1, -1 do
    local t = MP.toasts[i]
    t.t = t.t + dt
    if t.t > 5 then table.remove(MP.toasts, i) end
  end

  local run = MP.run
  if not run or run.mode ~= 'coop' or not MP.in_game() then return end

  local in_hand = G.STATE == G.STATES.SELECTING_HAND
  local waiting = run.coop_waiting == run.slot

  -- Apply teammates' scores only while no hand of ours is animating, so the
  -- vanilla chip ease can't overwrite them.
  if (in_hand or waiting) and #run.pending > 0 and G.GAME.blind and blind_target() > 0 then
    local keep = {}
    for _, p in ipairs(run.pending) do
      if p.slot == run.slot then
        G.GAME.chips = G.GAME.chips + p.score
        run.team_total = run.team_total + p.score
        MP.toast('+' .. MP.fmt(p.score) .. ' from ' .. tostring(p.name), G.C.BLUE)
        pcall(function()
          local ui = G.HUD:get_UIE_by_ID('chip_UI_count')
          if ui then ui:juice_up() end
          play_sound('chips2')
        end)
      elseif p.slot > run.slot then
        keep[#keep + 1] = p
      end
    end
    run.pending = keep
  end

  local target = blind_target()
  if target > 0 and G.GAME.chips >= target then
    if waiting then
      run.coop_waiting = nil
      end_round()
    elseif in_hand and events_idle() and not (G.play and G.play.cards[1]) then
      G.STATE = G.STATES.NEW_ROUND
      G.STATE_COMPLETE = false
    end
  elseif waiting and run.team_failed_slot == run.slot then
    run.force_fail = true
    end_round()
  end
end
