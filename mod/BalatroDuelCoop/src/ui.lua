-- Lobby menu + in-run HUD (status bar, notices, toasts), all built from Balatro UIBoxes.

local Net = MP.net
local UI = { is_open = false, last_error = nil, picking = nil, creating = false }
MP.UI = UI

UI.state = { join_code = '' }

UI.MODE_INFO = {
  duel = {
    title = 'DUEL', sub = '1 vs 1', colour = G.C.RED,
    lines = {
      'Same deck and stake, head to head.',
      'Play at your own pace; rounds stay in sync.',
      'Each blind: +1 point for the best hand,',
      '+1 for beating it in the fewest hands.',
      'Outlast your rival - or outscore them.',
    },
  },
  coop = {
    title = 'CO-OP', sub = '2 - 4 players', colour = G.C.BLUE,
    lines = {
      'Everyone plays their own run.',
      'All scores pool into one blind.',
      'Blind targets scale with player count.',
      'Out of hands? Your team can carry you.',
      'Beat Ante 8 together.',
    },
  },
}

local function deck_name(key)
  local c = G.P_CENTERS and G.P_CENTERS[key]
  if not c then return tostring(key) end
  local ok, name = pcall(localize, { type = 'name_text', set = 'Back', key = key })
  return (ok and name and name ~= 'ERROR') and name or c.name or key
end

local function stake_name(order)
  local s = G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake and G.P_CENTER_POOLS.Stake[order]
  if not s then return 'Stake ' .. tostring(order) end
  local ok, name = pcall(localize, { type = 'name_text', set = 'Stake', key = s.key })
  return (ok and name and name ~= 'ERROR') and name or s.name or s.key
end

local function text_row(str, scale, colour)
  return { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
    { n = G.UIT.T, config = { text = str, scale = scale or 0.4, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true } },
  } }
end

local function pill(nodes, colour, padding)
  return { n = G.UIT.C, config = { align = 'cm', padding = padding or 0.06, r = 0.08, colour = colour or G.C.BLACK }, nodes = nodes }
end

local function label(str, scale, colour)
  return { n = G.UIT.T, config = { text = str, scale = scale, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true } }
end

local function button_row(label, fn, colour, minw)
  return { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
    UIBox_button { label = { label }, button = fn, colour = colour or G.C.BLUE, minw = minw or 4, minh = 0.6, scale = 0.45 },
  } }
end

local function input_row(label, ref_table, ref_value, max_length, all_caps, id)
  return { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
    { n = G.UIT.C, config = { align = 'cr', minw = 2 }, nodes = {
      { n = G.UIT.T, config = { text = label, scale = 0.38, colour = G.C.UI.TEXT_LIGHT } },
    } },
    { n = G.UIT.C, config = { align = 'cl', padding = 0.05 }, nodes = {
      create_text_input { id = id, w = 4.5, max_length = max_length, all_caps = all_caps, extended_corpus = true,
        prompt_text = label, ref_table = ref_table, ref_value = ref_value },
    } },
  } }
end

-- Mode description card. With `button`, a button is added underneath.
-- NOTE: the card itself must not be clickable. Balatro draws a drop shadow under
-- every text node inside a button container (engine/ui.lua, `button_UIE`), which
-- ghosts the dark description text on the white panel.
local function mode_card(mode, button, compact)
  local info = UI.MODE_INFO[mode]
  local desc = {}
  for _, line in ipairs(info.lines) do
    desc[#desc + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.01 }, nodes = {
      { n = G.UIT.T, config = { text = line, scale = 0.32, colour = G.C.UI.TEXT_DARK } },
    } }
  end
  local header = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
    { n = G.UIT.T, config = { text = info.title, scale = compact and 0.45 or 0.6, colour = G.C.WHITE, shadow = true } },
    { n = G.UIT.T, config = { text = '  ' .. info.sub, scale = 0.32, colour = G.C.WHITE, shadow = true } },
  } }
  local body = { n = G.UIT.R, config = { align = 'cm', padding = 0.08, r = 0.1, colour = G.C.WHITE, minw = 4.4 }, nodes = desc }
  local cfg = { align = 'cm', padding = 0.1, r = 0.1, colour = info.colour, emboss = 0.05, minw = 4.6 }
  local nodes = { header, body }
  if button then
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
      UIBox_button { label = { 'Choose deck & stake' }, button = button, colour = darken(info.colour, 0.35),
        minw = 4, minh = 0.55, scale = 0.38 },
    } }
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
      UIBox_button { label = { 'Play a challenge' }, button = button .. '_challenge', colour = darken(info.colour, 0.35),
        minw = 4, minh = 0.55, scale = 0.38 },
    } }
  end
  return { n = G.UIT.C, config = cfg, nodes = nodes }
end

-- Deck art + description and stake chip + description, as in solo run setup.
local function deck_stake_panel(deck_key, stake)
  local center = G.P_CENTERS[deck_key] or G.P_CENTERS.b_red
  local deck_sprite
  if SMODS and SMODS.create_sprite then
    deck_sprite = SMODS.create_sprite(0, 0, G.CARD_W, G.CARD_H, center.atlas or 'centers', center.pos, center.sprite_args)
  else
    deck_sprite = Sprite(0, 0, G.CARD_W, G.CARD_H, G.ASSET_ATLAS[center.atlas or 'centers'], center.pos)
  end
  deck_sprite.states.drag.can = false
  local back = Back(center)

  local stake_nodes = {}
  local ok_sprite, stake_sprite = pcall(get_stake_sprite, stake)
  if ok_sprite and stake_sprite then
    stake_nodes[#stake_nodes + 1] = { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {
      { n = G.UIT.O, config = { object = stake_sprite, can_collide = false } },
    } }
  end
  local ok_desc, stake_desc = pcall(G.UIDEF.stake_description, stake)
  stake_nodes[#stake_nodes + 1] = ok_desc and stake_desc or
    { n = G.UIT.C, config = { align = 'cm' }, nodes = { text_row(stake_name(stake) .. ' Stake', 0.4) } }

  return { n = G.UIT.R, config = { align = 'cm', padding = 0.1, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
    { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {
      { n = G.UIT.O, config = { object = deck_sprite } },
    } },
    { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {
      { n = G.UIT.R, config = { align = 'cm', r = 0.1, padding = 0.08, colour = G.C.L_BLACK }, nodes = {
        { n = G.UIT.C, config = { align = 'cm' }, nodes = {
          text_row(deck_name(center.key), 0.45, G.C.WHITE),
          { n = G.UIT.R, config = { align = 'cm', colour = G.C.WHITE, r = 0.1, minh = 1.2, minw = 5.5 }, nodes = {
            { n = G.UIT.O, config = { object = UIBox { definition = back:generate_UI(), config = { offset = { x = 0, y = 0 } } } } },
          } },
        } },
      } },
      { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
        { n = G.UIT.C, config = { align = 'cm', colour = G.C.BLACK, r = 0.1 }, nodes = stake_nodes },
      } },
    } },
  } }
end

-- Lobby with a challenge: the challenge sets the deck, stake and rules.
local function challenge_panel(id)
  local ch = MP.find_challenge(id)
  local nodes = {
    text_row('CHALLENGE', 0.35, G.C.UI.TEXT_INACTIVE),
    text_row(MP.challenge_name(id), 0.6, G.C.WHITE),
  }
  if ch then
    local deck = ch.deck and ch.deck.type or 'Challenge Deck'
    nodes[#nodes + 1] = text_row(tostring(deck) .. '  |  ' .. stake_name(1) .. ' Stake  |  challenge rules apply', 0.32, G.C.UI.TEXT_LIGHT)
  else
    nodes[#nodes + 1] = text_row('This challenge is missing from your game (is a mod missing?)', 0.32, G.C.RED)
  end
  return { n = G.UIT.R, config = { align = 'cm', padding = 0.15, r = 0.1, colour = G.C.BLACK, emboss = 0.05, minw = 8 }, nodes = {
    { n = G.UIT.C, config = { align = 'cm' }, nodes = nodes },
  } }
end

-- Hosting status (in-game server reachable through Steam), shown wherever it matters.
local function hosting_panel()
  local text = MP.host and MP.host.status_text()
  -- All good (hosting through Steam): say nothing, it just clutters the screen.
  if not text or MP.host.public_address() ~= nil then return nil end
  local online = false
  local colour = online and G.C.GREEN or (MP.host.state == 'error' and G.C.RED or G.C.ORANGE)
  local nodes = { text_row(text, 0.32, G.C.WHITE) }
  if MP.host.state == 'error' then
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
      UIBox_button { label = { 'Retry' }, button = 'mp_host_retry', colour = G.C.ORANGE, minw = 2.6, minh = 0.45, scale = 0.32, col = true },
    } }
  end
  return { n = G.UIT.R, config = { align = 'cm', padding = 0.08, r = 0.1, colour = darken(colour, 0.35), emboss = 0.05 }, nodes = {
    { n = G.UIT.C, config = { align = 'cm' }, nodes = nodes },
  } }
end

local function invite_link()
  local server = MP.server_string()
  return MP.lobby and server and (tostring(MP.lobby.code) .. '@' .. server) or nil
end
UI.invite_link = invite_link

-- Shown from pressing Play (or Join) until the lobby exists, instead of flashing
-- the main multiplayer screen in between. The dots animate without rebuilding.
UI.loading_dots = { text = '' }
function UI.is_loading()
  return not MP.lobby and (UI.creating or MP.pending_join ~= nil) and true or false
end

function UI.loading_definition()
  local what = MP.pending_join and 'Joining lobby' or 'Setting up your lobby'
  return create_UIBox_generic_options { back_func = 'mp_cancel_loading', back_label = 'Cancel', contents = {
    { n = G.UIT.C, config = { align = 'cm', padding = 0.15, minw = 7, minh = 2.4 }, nodes = {
      text_row('MULTIPLAYER', 0.7, G.C.GOLD),
      { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
        { n = G.UIT.T, config = { text = what, scale = 0.5, colour = G.C.WHITE, shadow = true } },
        { n = G.UIT.C, config = { align = 'cl', minw = 0.6 }, nodes = {
          { n = G.UIT.T, config = { ref_table = UI.loading_dots, ref_value = 'text', scale = 0.5, colour = G.C.WHITE, shadow = true } },
        } },
      } },
    } },
  } }
end

function UI.definition()
  if UI.is_loading() then return UI.loading_definition() end
  local cfg = MP.config
  local nodes = {}
  nodes[#nodes + 1] = text_row('MULTIPLAYER', 0.7, G.C.GOLD)

  if not MP.lobby then
    nodes[#nodes + 1] = text_row('Playing as ' .. MP.display_name(), 0.32, G.C.UI.TEXT_INACTIVE)
    local inv = MP.pending_invite
    if inv then
      nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.1, r = 0.1, colour = G.C.GOLD, emboss = 0.05 }, nodes = {
        { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {
          { n = G.UIT.T, config = { text = tostring(inv.from) .. ' invited you to a ' .. (inv.mode == 'duel' and 'Duel' or 'Co-op') .. '!',
            scale = 0.45, colour = G.C.UI.TEXT_DARK } },
        } },
        UIBox_button { label = { 'Join' }, button = 'mp_accept_invite', colour = G.C.GREEN, minw = 1.8, minh = 0.6, scale = 0.45, col = true },
        UIBox_button { label = { 'Decline' }, button = 'mp_decline_invite', colour = G.C.RED, minw = 1.8, minh = 0.6, scale = 0.45, col = true },
      } }
    end
    local friend_lobbies = {}
    for _, f in ipairs(UI.friends_cache or {}) do
      if f.lobby then friend_lobbies[#friend_lobbies + 1] = f end
    end
    if #friend_lobbies > 0 then
      nodes[#nodes + 1] = text_row("Friends' lobbies", 0.45, G.C.WHITE)
      local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {} }
      for i, f in ipairs(friend_lobbies) do
        if i > 4 then break end
        UI.lobby_join_targets[i] = f
        row.nodes[#row.nodes + 1] = UIBox_button { label = { 'Join ' .. f.name, f.lobby.mode == 'duel' and 'Duel' or 'Co-op' },
          button = 'mp_join_friend_' .. i, colour = G.C.GREEN, minw = 2.6, minh = 0.8, scale = 0.38, col = true }
      end
      nodes[#nodes + 1] = row
    end
    nodes[#nodes + 1] = text_row('Host a game', 0.45, G.C.WHITE)
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.15 }, nodes = {
      mode_card('duel', 'mp_pick_duel'),
      mode_card('coop', 'mp_pick_coop'),
    } }
    nodes[#nodes + 1] = text_row('Have an invite code?', 0.45, G.C.WHITE)
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
      { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {
        create_text_input { id = 'mp_code', w = 5.5, max_length = 60, all_caps = false, extended_corpus = true,
          prompt_text = 'Paste invite code', ref_table = UI.state, ref_value = 'join_code' },
      } },
      UIBox_button { label = { 'Paste' }, button = 'mp_paste_invite', colour = G.C.BLUE, minw = 1.4, minh = 0.6, scale = 0.4, col = true },
      UIBox_button { label = { 'Join' }, button = 'mp_join', colour = G.C.GREEN, minw = 1.6, minh = 0.6, scale = 0.45, col = true },
    } }
    local hp = hosting_panel()
    if hp then nodes[#nodes + 1] = hp end
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
      UIBox_button { label = { 'Advanced' }, button = 'mp_open_advanced', colour = G.C.UI.BACKGROUND_INACTIVE, minw = 2.4, minh = 0.5, scale = 0.35, col = true },
      MP.host.state ~= 'off' and UIBox_button { label = { 'Stop hosting' }, button = 'mp_stop_hosting', colour = G.C.RED, minw = 2.4, minh = 0.5, scale = 0.35, col = true } or nil,
    } }
  else
    -- Compact layout: everything has to fit on a 16:9 screen along with the Back button.
    local l = MP.lobby
    local max = l.mode == 'duel' and 2 or 4
    nodes[1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
      { n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = { label('MULTIPLAYER', 0.5, G.C.GOLD) } },
      pill { label('LOBBY  ', 0.28, G.C.UI.TEXT_INACTIVE), label(tostring(l.code), 0.4) },
      pill { label('SEED  ', 0.28, G.C.UI.TEXT_INACTIVE),
        label(l.sameSeed == false and 'PER PLAYER' or tostring(l.seed), 0.4) },
    } }
    if tostring(l.hostId) == MP.my_id then
      -- Host only: everyone on one seed (same jokers, shops, packs...) or each on their own.
      local nodes1 = nodes[1].nodes
      nodes1[#nodes1 + 1] = UIBox_button { label = { l.sameSeed == false and 'Use same seed' or 'Use different seeds' },
        button = 'mp_toggle_seed', colour = G.C.BLUE, minw = 2.6, minh = 0.45, scale = 0.32, col = true }
    end

    local players = { text_row('Players (' .. #(l.players or {}) .. '/' .. max .. ')', 0.45, G.C.GOLD) }
    for _, p in ipairs(l.players or {}) do
      local entry = { label(tostring(p.name), 0.4) }
      if tostring(p.id) == tostring(l.hostId) then
        entry[#entry + 1] = { n = G.UIT.B, config = { w = 0.1, h = 0.1 } }
        entry[#entry + 1] = pill({ label('HOST', 0.24) }, G.C.ORANGE, 0.04)
      end
      if tostring(p.id) == MP.my_id then
        entry[#entry + 1] = { n = G.UIT.B, config = { w = 0.1, h = 0.1 } }
        entry[#entry + 1] = pill({ label('YOU', 0.24) }, G.C.BLUE, 0.04)
      end
      players[#players + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = entry }
    end
    if #(l.players or {}) < max then
      players[#players + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
        UIBox_button { label = { 'Invite Steam Friends' }, button = 'mp_open_invites', colour = G.C.PURPLE,
          minw = 3.4, minh = 0.6, scale = 0.42 },
      } }
      if invite_link() then
        players[#players + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
          UIBox_button { label = { 'Copy invite code' }, button = 'mp_copy_invite', colour = G.C.BLUE,
            minw = 3.4, minh = 0.45, scale = 0.33 },
        } }
      end
    end

    local ok, panel
    if l.challenge then
      ok, panel = pcall(challenge_panel, l.challenge)
    else
      ok, panel = pcall(deck_stake_panel, l.deck, tonumber(l.stake) or 1)
    end
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
      mode_card(l.mode, nil, true),
      { n = G.UIT.C, config = { align = 'tm', padding = 0.1, minw = 3.2, r = 0.1, colour = G.C.L_BLACK }, nodes = players },
    } }
    if ok then
      nodes[#nodes + 1] = panel
    else
      nodes[#nodes + 1] = text_row(l.challenge and ('Challenge: ' .. tostring(l.challenge)) or
        (deck_name(l.deck) .. '  |  ' .. stake_name(tonumber(l.stake) or 1) .. ' Stake'), 0.4)
    end

    if MP.target and MP.target.kind == 'host' then
      local hp = hosting_panel()
      if hp then nodes[#nodes + 1] = hp end
    end
    local is_host = tostring(l.hostId) == MP.my_id
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
      is_host and UIBox_button { label = { 'Start Game' }, button = 'mp_start', colour = G.C.GREEN, minw = 3.6, minh = 0.65, scale = 0.45, col = true }
        or { n = G.UIT.C, config = { align = 'cm', minw = 3.6 }, nodes = { text_row('Waiting for the host...', 0.35, G.C.UI.TEXT_INACTIVE) } },
      UIBox_button { label = { 'Leave Lobby' }, button = 'mp_leave', colour = G.C.RED, minw = 3, minh = 0.65, scale = 0.45, col = true },
    } }
  end
  if UI.last_error then nodes[#nodes + 1] = text_row(tostring(UI.last_error), 0.32, G.C.RED) end

  return create_UIBox_generic_options { padding = MP.lobby and 0.05 or nil, contents = {
    { n = G.UIT.C, config = { align = 'cm', padding = MP.lobby and 0.05 or 0.1, minw = 8 }, nodes = nodes },
  } }
end

-- Advanced: player name and an optional dedicated server (instead of hosting in-game).
function UI.advanced_definition()
  local cfg = MP.config
  cfg.server_port = tostring(cfg.server_port or '8788')
  local nodes = { text_row('ADVANCED', 0.6, G.C.GOLD) }
  nodes[#nodes + 1] = input_row('Name', cfg, 'player_name', 16, false, 'mp_name')
  nodes[#nodes + 1] = text_row('Leave the name empty to use your Steam name', 0.3, G.C.UI.TEXT_INACTIVE)
  nodes[#nodes + 1] = text_row('Dedicated server (optional). Leave empty to host games yourself.', 0.3, G.C.UI.TEXT_INACTIVE)
  nodes[#nodes + 1] = input_row('Server', cfg, 'server_host', 40, false, 'mp_host')
  nodes[#nodes + 1] = input_row('Port', cfg, 'server_port', 5, false, 'mp_port')
  local connected = MP.target and MP.target.kind == 'dedicated' and Net.status == 'connected'
  nodes[#nodes + 1] = text_row(connected and ('Connected to ' .. MP.target.host .. ':' .. MP.target.port) or
    (Net.status == 'connecting' and 'Connecting...' or 'Not connected to a dedicated server'), 0.32, connected and G.C.GREEN or G.C.UI.TEXT_INACTIVE)
  if Net.error then nodes[#nodes + 1] = text_row(tostring(Net.error), 0.3, G.C.RED) end
  nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
    UIBox_button { label = { 'Save & connect' }, button = 'mp_connect', colour = G.C.GREEN, minw = 3, minh = 0.6, scale = 0.4, col = true },
    UIBox_button { label = { 'Use in-game hosting' }, button = 'mp_clear_server', colour = G.C.BLUE, minw = 3.4, minh = 0.6, scale = 0.4, col = true },
  } }
  return create_UIBox_generic_options { back_func = 'mp_open', contents = {
    { n = G.UIT.C, config = { align = 'cm', padding = 0.08, minw = 8 }, nodes = nodes },
  } }
end

UI.lobby_join_targets = {}
UI.invite_targets = {}
UI.invited = {}

-- Friends list (Steam), refreshed when menus open. Rich presence (friends' lobbies)
-- arrives from Steam a moment after we request it, so we re-read once shortly after.
local function refresh_friends(request)
  local steam = MP.steam
  if not (steam and steam.init()) then UI.friends_cache = nil return end
  if request then
    pcall(steam.request_presence)
    UI.presence_reread_at = love.timer.getTime() + 2
  end
  local ok, list = pcall(steam.friends)
  UI.friends_cache = ok and list or nil
end

-- Everything the menus display, as one string. Menus are only rebuilt when this
-- changes; rebuilding replays the overlay's open animation, which looks like flicker.
local function state_signature()
  -- While loading only the loading screen shows: don't rebuild it as the server starts.
  if UI.screen == nil and UI.is_loading() then return 'loading|' .. tostring(MP.pending_join) end
  local parts = { tostring(UI.screen), Net.status, tostring(Net.error), tostring(UI.creating), tostring(UI.last_error),
    tostring(MP.pending_join), tostring(MP.host.state), tostring(MP.host.status_text()), tostring(MP.server_string()),
    MP.target and (MP.target.kind .. MP.target.host .. MP.target.port) or '-' }
  if MP.lobby then parts[#parts + 1] = MP.json.encode(MP.lobby) end
  local inv = MP.pending_invite
  if inv then parts[#parts + 1] = tostring(inv.code) .. tostring(inv.from) end
  for _, f in ipairs(UI.friends_cache or {}) do
    if UI.screen == 'invite' then
      parts[#parts + 1] = f.id .. f.status .. tostring(UI.invited[f.id]) .. tostring(UI.queued and UI.queued[f.id] ~= nil)
    elseif f.lobby then
      parts[#parts + 1] = f.id .. f.lobby.code
    end
  end
  return table.concat(parts, '|')
end

-- Swapping one of our menus for another: appear in place instead of sliding in
-- from below (Balatro's default), which reads as a flicker.
local function overlay(def, slide)
  G.FUNCS.overlay_menu { definition = def, config = (not slide) and { offset = { x = 0, y = 0 } } or nil }
end
UI.overlay = overlay

function UI.open(instant)
  local slide = not instant and not G.OVERLAY_MENU
  UI.is_open = true
  UI.picking = nil
  UI.screen = nil
  UI.last_error = nil
  refresh_friends(true)
  overlay(UI.definition(), slide)
  UI.shown_sig = state_signature()
end

function UI.refresh()
  if not (UI.is_open and not UI.picking and G.OVERLAY_MENU and G.STAGE == G.STAGES.MAIN_MENU) then return end
  if UI.screen == 'invite' and not MP.lobby then UI.screen = nil end
  local sig = state_signature()
  if sig == UI.shown_sig then return end
  UI.shown_sig = sig
  if UI.screen == 'invite' then
    overlay(UI.invite_definition())
  elseif UI.screen == 'advanced' then
    overlay(UI.advanced_definition())
  else
    overlay(UI.definition())
  end
end

UI.declined = {}

function UI.update()
  local now = love.timer.getTime()
  UI.loading_dots.text = string.rep('.', math.floor(now * 3) % 4)
  if UI.presence_reread_at and now >= UI.presence_reread_at then
    UI.presence_reread_at = nil
    refresh_friends(false)
    UI.refresh()
  end
  local ok, err = pcall(UI.update_hud)
  if not ok and not UI.hud_err then UI.hud_err = true; print('[BalatroDuelCoop] HUD error: ' .. tostring(err)) end
  -- Friends' invites arrive via their Steam rich presence: check every few seconds on the main menu.
  if G.STAGE == G.STAGES.MAIN_MENU and MP.steam and MP.steam.ok and now >= (UI.next_invite_poll or 0) then
    UI.next_invite_poll = now + 5
    refresh_friends(true)
    if not MP.lobby and not MP.pending_invite then
      for _, f in ipairs(UI.friends_cache or {}) do
        local key = f.lobby and (f.id .. f.lobby.code)
        if f.invited_me and not UI.declined[key] then
          MP.pending_invite = { code = f.lobby.code, mode = f.lobby.mode, from = f.name, server = f.lobby.server }
          UI.declined[key] = true -- only pop up once per lobby
          MP.toast(f.name .. ' invited you to a ' .. (f.lobby.mode == 'duel' and 'Duel' or 'Co-op') .. '!', G.C.GOLD)
          if not G.OVERLAY_MENU then UI.open() end
          break
        end
      end
    end
    UI.refresh()
  end
end

function UI.invited_ids()
  local t = {}
  for id in pairs(UI.invited) do t[#t + 1] = id end
  return t
end

-- Invite screen ------------------------------------------------------------------

function UI.invite_definition()
  local l = MP.lobby
  local nodes = { text_row('INVITE STEAM FRIENDS', 0.6, G.C.GOLD) }
  nodes[#nodes + 1] = text_row('Lobby ' .. tostring(l and l.code) .. '  |  ' .. (l and l.mode == 'duel' and 'Duel' or 'Co-op') ..
    (l and l.challenge and ('  |  Challenge: ' .. MP.challenge_name(l.challenge)) or ''), 0.35, G.C.WHITE)
  if MP.target and MP.target.kind == 'host' then
    local hp = hosting_panel()
    if hp then nodes[#nodes + 1] = hp end
  end
  local ready = invite_link() ~= nil
  if not ready then
    nodes[#nodes + 1] = text_row('Your game server is still starting - invites go out as soon as it is ready.', 0.32, G.C.ORANGE)
  end
  if not (MP.steam and MP.steam.ok) then
    nodes[#nodes + 1] = text_row('Steam friends are unavailable (is Steam running?)', 0.38, G.C.RED)
    nodes[#nodes + 1] = text_row('Friends join through Steam, so Steam needs to be running.', 0.38, G.C.WHITE)
  else
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
      UIBox_button { label = { 'Open Steam Invite Dialog' }, button = ready and 'mp_invite_dialog' or 'nil',
        colour = ready and G.C.BLUE or G.C.UI.BACKGROUND_INACTIVE, minw = 5, minh = 0.6, scale = 0.42 },
    } }
    nodes[#nodes + 1] = text_row('or invite directly:', 0.32, G.C.UI.TEXT_INACTIVE)
    local shown = 0
    for _, f in ipairs(UI.friends_cache or {}) do
      if shown >= 10 then break end
      shown = shown + 1
      UI.invite_targets[shown] = f
      local invited = UI.invited[f.id]
      nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
        { n = G.UIT.C, config = { align = 'cl', minw = 3.6, maxw = 3.6 }, nodes = {
          { n = G.UIT.T, config = { text = f.name, scale = 0.38, colour = G.C.WHITE } } } },
        { n = G.UIT.C, config = { align = 'cl', minw = 2.6, maxw = 2.6 }, nodes = {
          { n = G.UIT.T, config = { text = f.status, scale = 0.3, colour = f.in_balatro and G.C.GREEN or G.C.UI.TEXT_INACTIVE } } } },
        UIBox_button { label = { invited and (UI.queued[f.id] and 'Queued' or 'Invited') or 'Invite' }, button = invited and 'nil' or ('mp_invite_' .. shown),
          colour = invited and G.C.UI.BACKGROUND_INACTIVE or G.C.GREEN, minw = 1.6, minh = 0.5, scale = 0.35, col = true },
      } }
    end
    if shown == 0 then nodes[#nodes + 1] = text_row('No friends online right now', 0.35, G.C.UI.TEXT_INACTIVE) end
    nodes[#nodes + 1] = text_row('Friends need Balatro + Steamodded + this mod installed.', 0.28, G.C.UI.TEXT_INACTIVE)
  end
  return create_UIBox_generic_options { back_func = 'mp_open', contents = {
    { n = G.UIT.C, config = { align = 'cm', padding = 0.08, minw = 8 }, nodes = nodes },
  } }
end

function UI.open_invites()
  UI.screen = 'invite'
  refresh_friends(true)
  overlay(UI.invite_definition())
  UI.shown_sig = state_signature()
end

UI.queued = {}

local function send_invite(f)
  if not (f and MP.lobby) then return end
  UI.invited[f.id] = true
  if not MP.server_string() then
    UI.queued[f.id] = f
    MP.toast('Invite to ' .. f.name .. ' will be sent once your server is ready', G.C.ORANGE)
    UI.refresh()
    return
  end
  UI.queued[f.id] = nil
  if MP.target and MP.target.kind == 'host' and MP.p2p then MP.p2p.greet(f.id) end -- opens the Steam connection early
  MP.send { type = 'invite', steamId = f.id } -- in-game popup if they're online with the mod
  pcall(MP.steam.invite, f.id, MP.steam.connect_string(MP.lobby.code, MP.server_string())) -- Steam chat invite
  if MP.update_presence then MP.update_presence() end -- their running game picks the invite up
  MP.toast('Invited ' .. f.name, G.C.GREEN)
  UI.refresh()
end

for i = 1, 10 do
  G.FUNCS['mp_invite_' .. i] = function() send_invite(UI.invite_targets[i]) end
end

-- Called when our game server is up.
function UI.flush_invites()
  local q = UI.queued
  UI.queued = {}
  for _, f in pairs(q) do send_invite(f) end
end
for i = 1, 4 do
  G.FUNCS['mp_join_friend_' .. i] = function()
    local f = UI.lobby_join_targets[i]
    if f and f.lobby then MP.join_lobby(f.lobby.code, f.lobby.server) end
  end
end
G.FUNCS.mp_open_invites = function() UI.open_invites() end
G.FUNCS.mp_invite_dialog = function()
  if MP.lobby then pcall(MP.steam.open_invite_dialog, MP.steam.connect_string(MP.lobby.code, MP.server_string())) end
end
G.FUNCS.mp_accept_invite = function()
  local inv = MP.pending_invite
  if inv then MP.join_lobby(inv.code, inv.server) end
end
G.FUNCS.mp_decline_invite = function() MP.pending_invite = nil; UI.refresh() end
G.FUNCS.mp_cancel_loading = function()
  UI.creating, MP.pending_join, MP.pending_create = false, nil, nil
  if MP.target and MP.target.kind == 'joined' then MP.net.disconnect(); MP.target = nil end
  UI.refresh()
end

local function show(screen, def)
  UI.screen = screen
  overlay(def())
  UI.shown_sig = state_signature()
end
G.FUNCS.mp_open_advanced = function() show('advanced', UI.advanced_definition) end
G.FUNCS.mp_copy_invite = function()
  local link = invite_link()
  if link then love.system.setClipboardText(link); MP.toast('Invite code copied (works for your Steam friends)', G.C.GREEN) end
end
G.FUNCS.mp_paste_invite = function()
  local clip = (love.system.getClipboardText() or ''):gsub('%s', '')
  UI.state.join_code = clip:sub(1, 60)
  overlay(UI.definition())
  UI.shown_sig = state_signature()
end
G.FUNCS.mp_stop_hosting = function()
  if MP.target and MP.target.kind == 'host' then MP.net.disconnect(); MP.target = nil end
  MP.host.stop()
  UI.refresh()
end
G.FUNCS.mp_clear_server = function()
  MP.config.server_host = ''
  MP.save_config()
  if MP.target and MP.target.kind == 'dedicated' then MP.net.disconnect(); MP.target = nil end
  UI.refresh()
end
G.FUNCS.mp_host_retry = function()
  MP.host.stop()
  MP.host.start()
  UI.refresh()
end

-- Deck & stake picker: reuses the exact solo "New Run" screen ------------------

local function use_smods_run_select()
  return SMODS and SMODS.RunSelect and G.UIDEF.run_select_galdur
    and not (SMODS.config and SMODS.config.vanilla_run_select and #SMODS.RunSelect.Internals.pages == 2)
end

function UI.open_picker(mode)
  UI.picking = mode
  local info = UI.MODE_INFO[mode]
  local setup = use_smods_run_select() and G.UIDEF.run_select_galdur('New Run') or G.UIDEF.run_setup_option('New Run')
  G.FUNCS.overlay_menu { definition = create_UIBox_generic_options {
    back_func = 'mp_picker_back',
    contents = {
      { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
        { n = G.UIT.T, config = { text = info.title .. ' LOBBY', scale = 0.55, colour = info.colour, shadow = true } },
        { n = G.UIT.T, config = { text = '  -  pick a deck and stake, then press Play to create the lobby', scale = 0.35, colour = G.C.WHITE, shadow = true } },
      } },
      { n = G.UIT.R, config = { align = 'cm' }, nodes = {
        { n = G.UIT.O, config = { id = 'mp_picker', object = UIBox { definition = setup, config = { offset = { x = 0, y = 0 } } } } },
      } },
    },
  }, config = { offset = { x = 0, y = 0 } } }
end

-- Challenge picker: the solo challenge list, whose Play button creates the lobby instead.
local function replace_button(node, from, to)
  if type(node) ~= 'table' then return end
  if node.config and node.config.button == from then node.config.button = to end
  for _, c in ipairs(node.nodes or {}) do replace_button(c, from, to) end
end

function UI.open_challenge_picker(mode)
  UI.picking = mode
  local def = G.UIDEF.challenge_list(false)
  replace_button(def, 'setup_run', 'mp_picker_back') -- Back returns to the multiplayer menu
  G.FUNCS.overlay_menu { definition = def, config = { offset = { x = 0, y = 0 } } }
  MP.toast('Pick a challenge for your ' .. UI.MODE_INFO[mode].title .. ' lobby', UI.MODE_INFO[mode].colour)
end

local function clean_up_picker()
  if use_smods_run_select() then pcall(SMODS.RunSelect.Functions.clean_up) end
end

-- Called instead of starting a solo run while the picker is open.
local function create_lobby_from_picker(deck_key, stake, seed, challenge)
  local mode = UI.picking
  clean_up_picker()
  MP.create_lobby { type = 'create', mode = mode, deck = deck_key, stake = stake, seed = (seed and seed ~= '') and seed or nil,
    challenge = challenge }
  UI.open(true) -- loading screen in place of the picker, then the lobby in place of that
end

-- Button callbacks ------------------------------------------------------------

G.FUNCS.mp_open = function() UI.open() end
G.FUNCS.mp_connect = function()
  UI.last_error = nil
  MP.save_config()
  MP.connect()
  UI.refresh()
end
G.FUNCS.mp_disconnect = function() MP.net.disconnect(); MP.target = nil; MP.lobby = nil; UI.refresh() end
G.FUNCS.mp_pick_duel = function() UI.open_picker('duel') end
G.FUNCS.mp_pick_coop = function() UI.open_picker('coop') end
G.FUNCS.mp_pick_duel_challenge = function() UI.open_challenge_picker('duel') end
G.FUNCS.mp_pick_coop_challenge = function() UI.open_challenge_picker('coop') end
G.FUNCS.mp_picker_back = function() clean_up_picker(); UI.open() end
G.FUNCS.mp_join = function()
  UI.last_error = nil
  local text = tostring(UI.state.join_code or ''):gsub('%s', '')
  local code, server = text:match('^(%w+)@(.+)$') -- CODE@steam:<id> or CODE@host:port
  MP.join_lobby(code or text, server)
end
G.FUNCS.mp_leave = function()
  MP.send { type = 'leave' }
  MP.lobby = nil
  UI.invited = {}
  if MP.update_presence then MP.update_presence() end
  UI.refresh()
end
G.FUNCS.mp_start = function() UI.last_error = nil; MP.send { type = 'start' } end
G.FUNCS.mp_toggle_seed = function()
  if not MP.lobby then return end
  UI.last_error = nil
  MP.send { type = 'lobby_options', sameSeed = MP.lobby.sameSeed == false }
end

function UI.install_picker_hooks()
  -- Steamodded's paged run select: Play, double-click and Quick Start all end here.
  if SMODS and SMODS.RunSelect and SMODS.RunSelect.Functions.start_run then
    local orig = SMODS.RunSelect.Functions.start_run
    SMODS.RunSelect.Functions.start_run = function(...)
      if not UI.picking then return orig(...) end
      local c = SMODS.RunSelect.Setup.choices
      local stake = G.P_STAKES[c.stake_choice or 'stake_white']
      return create_lobby_from_picker(c.deck_choice or 'b_red', stake and stake.order or 1, c.enable_seed and c.seed or nil)
    end
  end
  -- Challenge list: its Play button.
  local orig_challenge = G.FUNCS.start_challenge_run
  G.FUNCS.start_challenge_run = function(e)
    local ch = UI.picking and e and e.config and G.CHALLENGES[e.config.id]
    if not ch then return orig_challenge(e) end
    return create_lobby_from_picker('b_challenge', 1, nil, ch.id)
  end
  -- Vanilla run setup screen (if Steamodded's is disabled).
  local orig_setup = G.FUNCS.start_setup_run
  G.FUNCS.start_setup_run = function(e)
    if not UI.picking then return orig_setup(e) end
    local key = G.GAME.viewed_back and G.GAME.viewed_back.effect.center.key or 'b_red'
    return create_lobby_from_picker(key, G.viewed_stake or 1, G.run_setup_seed and G.setup_seed or nil)
  end
end

-- Main menu button --------------------------------------------------------------

local function find_parent(node, id)
  if type(node) ~= 'table' or type(node.nodes) ~= 'table' then return nil end
  for i, child in ipairs(node.nodes) do
    if type(child) == 'table' then
      if child.config and child.config.id == id then return node, i end
      if child.nodes and child.nodes[1] and child.nodes[1].config and child.nodes[1].config.id == id then return node, i end
      local p, j = find_parent(child, id)
      if p then return p, j end
    end
  end
end

function UI.install_hooks()
  local orig_main_menu = create_UIBox_main_menu_buttons
  create_UIBox_main_menu_buttons = function(...)
    local t = orig_main_menu(...)
    local ok = pcall(function()
      -- Stack MULTIPLAYER under PLAY in the same slot so the menu row doesn't get
      -- wider (Steamodded already adds a MODS button to it).
      local parent, idx = find_parent(t, 'main_menu_play')
      if parent then
        local play = parent.nodes[idx]
        local play_inner = play.nodes and play.nodes[1]
        if play_inner and play_inner.config then play_inner.config.minh = 1.0 end
        parent.nodes[idx] = { n = G.UIT.C, config = { align = 'cm' }, nodes = {
          { n = G.UIT.R, config = { align = 'cm' }, nodes = { play } },
          { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} },
          UIBox_button {
            id = 'mp_main_menu', button = 'mp_open', colour = G.C.PURPLE, minw = 3.65, minh = 0.45,
            label = { 'MULTIPLAYER' }, scale = 0.4,
          },
        } }
      end
    end)
    if not ok then print('[BalatroDuelCoop] could not add main menu button; press F8 to open') end
    return t
  end

  local orig_exit = G.FUNCS.exit_overlay_menu
  G.FUNCS.exit_overlay_menu = function(...)
    UI.is_open = false
    UI.picking = nil
    if MP.viewer then MP.viewer.is_open = false end
    return orig_exit(...)
  end

  local orig_key = love.keypressed
  love.keypressed = function(key, ...)
    if key == 'f8' and G.STAGE == G.STAGES.MAIN_MENU and not G.OVERLAY_MENU then UI.open() return end
    if key == 'f7' then UI.hud_hidden = not UI.hud_hidden return end
    if key == 'tab' and MP.run and G.STAGE == G.STAGES.RUN and MP.viewer then MP.viewer.toggle() return end
    return orig_key(key, ...)
  end
end

-- HUD -----------------------------------------------------------------------------
--
-- Everything shown during a run (status bar, waiting / result notices, toasts) is a
-- regular Balatro UIBox, so it gets the game's font, shadows, CRT filter and screen
-- shake. Boxes are only rebuilt when what they display changes.
--
-- Draw order (Game:draw): G.I.UIBOX sits under overlay menus, G.I.POPUP above them.
-- Toasts and end-of-run notices use POPUP so they stay visible over a menu.
--
-- While the game is paused (Options, game over...; not every overlay menu pauses)
-- Balatro freezes anything created unpaused, and it only lets you click things created
-- in the current pause state. So the clickable status bar is never rebuilt while
-- paused, and the POPUP boxes are flagged to always move.

local slots = {}        -- name -> { box = UIBox, sig = string }
UI.toast_boxes = {}     -- toast entry (from MP.toasts) -> UIBox

-- Clicks and hovers pass straight through to the cards underneath.
local function passive(node)
  node.config = node.config or {}
  node.config.can_collide = false
  for _, c in ipairs(node.nodes or {}) do passive(c) end
  return node
end

local function keep_moving(node)
  node.created_on_pause = true
  if node.config and node.config.object then node.config.object.created_on_pause = true end
  for _, c in pairs(node.children or {}) do keep_moving(c) end
end

local function drop(box)
  if box and not box.REMOVED then box:remove() end
end

-- Show `build()`'s box in `name` while `sig` is unchanged; nil `sig` removes it.
local function sync(name, sig, build)
  local cur = slots[name]
  if cur and cur.box and cur.box.REMOVED then cur = nil end -- e.g. cleared with the run
  if not sig then
    if cur then drop(cur.box) end
    slots[name] = nil
    return
  end
  if cur and cur.sig == sig then slots[name] = cur return end
  if cur then drop(cur.box) end
  local ok, box = pcall(build)
  if not ok then
    print('[BalatroDuelCoop] HUD error (' .. name .. '): ' .. tostring(box))
    box = nil
  end
  slots[name] = { box = box, sig = sig } -- a failed build is not retried until the content changes
end

-- Status bar ----------------------------------------------------------------------

-- A list of pills, each { bg = colour, { text, colour }, ... }.
local function bar_pills(run)
  local LIGHT, DIM = G.C.UI.TEXT_LIGHT, G.C.UI.TEXT_INACTIVE
  local pills = {}
  if run.mode == 'duel' then
    local mine, theirs = 0, 0
    for id, p in pairs(run.points or {}) do if tostring(id) == MP.my_id then mine = p else theirs = p end end
    local opp_name = 'Opponent'
    for _, p in ipairs(run.players) do if tostring(p.id) ~= MP.my_id then opp_name = p.name end end
    local opp = run.opp or {}
    pills[#pills + 1] = { bg = G.C.RED, { 'DUEL', LIGHT } }
    pills[#pills + 1] = { bg = G.C.BLACK, { 'You  ', LIGHT }, { mine .. ' pts', G.C.GOLD } }
    pills[#pills + 1] = { bg = G.C.BLACK, { tostring(opp_name) .. '  ', LIGHT }, { theirs .. ' pts', G.C.GOLD },
      { '    Last hand ', DIM }, { opp.last and MP.fmt(opp.last) or '-', LIGHT },
      { '    Best ', DIM }, { MP.fmt(opp.best or 0), LIGHT },
      { '    Hands ', DIM }, { tostring(opp.hands or 0), LIGHT } }
  else
    local S = G.STATES
    local in_blind = (G.STATE == S.SELECTING_HAND or G.STATE == S.HAND_PLAYED
      or G.STATE == S.DRAW_TO_HAND or G.STATE == S.NEW_ROUND or run.coop_waiting)
      and G.GAME and G.GAME.blind and G.GAME.blind.in_blind
    pills[#pills + 1] = { bg = G.C.BLUE, { 'CO-OP x' .. tostring(MP.coop_scale()), LIGHT } }
    if in_blind then
      pills[#pills + 1] = { bg = G.C.BLACK, { 'Teammates  ', DIM }, { '+' .. MP.fmt(run.team_total or 0), G.C.GOLD } }
    end
    for _, p in ipairs(run.players) do
      if tostring(p.id) ~= MP.my_id then
        local pill = { bg = G.C.BLACK, { tostring(p.name), LIGHT } }
        if in_blind then
          local t = run.team[tostring(p.id)]
          pill[#pill + 1] = { '  ' .. (t and t.last and MP.fmt(t.last) or '-'), DIM }
        end
        pills[#pills + 1] = pill
      end
    end
  end
  if run.disconnected then pills[#pills + 1] = { bg = G.C.RED, { 'DISCONNECTED', LIGHT } } end
  pills[#pills + 1] = { bg = G.C.UI.BACKGROUND_INACTIVE, { 'TAB: players', LIGHT } }
  return pills
end

local function pills_sig(pills)
  local parts = {}
  for _, pill in ipairs(pills) do
    for _, seg in ipairs(pill) do parts[#parts + 1] = seg[1] end
    parts[#parts + 1] = '|'
  end
  return table.concat(parts)
end

local function build_bar(pills)
  local nodes = {}
  for _, pill in ipairs(pills) do
    local segs = {}
    for _, seg in ipairs(pill) do
      segs[#segs + 1] = { n = G.UIT.T, config = { text = seg[1], scale = 0.28, colour = seg[2], shadow = true } }
    end
    nodes[#nodes + 1] = { n = G.UIT.C, config = { align = 'cm', padding = 0.05, r = 0.08, colour = pill.bg }, nodes = segs }
  end
  -- Sits in the margin above the joker row. Clicking it opens the player viewer.
  return UIBox {
    definition = { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR }, nodes = {
      { n = G.UIT.R, config = { align = 'cm', padding = 0.04, r = 0.1, colour = G.C.L_BLACK, emboss = 0.05,
        hover = true, shadow = true, button = 'mp_open_viewer' }, nodes = nodes },
    } },
    config = { align = 'tmi', offset = { x = 0, y = -0.62 }, major = G.ROOM_ATTACH, bond = 'Weak' },
  }
end

-- Notices (waiting for players, end of run) -----------------------------------------

-- A notice is { title, colour, scale, bump, lines = { { text, colour } }, points = { { name, n } }, top, button }.
local function result_notice(run)
  local r = run.result
  local n = { lines = {}, scale = 0.9 }
  if r.mode == 'duel' then
    if r.winnerId == nil then n.title, n.colour = 'DRAW', G.C.GOLD
    elseif tostring(r.winnerId) == MP.my_id then n.title, n.colour = 'YOU WIN!', G.C.GREEN
    else n.title, n.colour = 'YOU LOSE', G.C.RED end
    local reasons = {
      both_won = 'Both beat the final boss - most points wins',
      both_lost_same_round = 'Both runs ended on the same blind - most points wins',
      outlasted = 'One run ended first',
      opponent_left = 'Opponent left the game',
    }
    n.lines[1] = { reasons[r.reason] or tostring(r.reason), G.C.UI.TEXT_LIGHT }
    local mine, theirs = 0, 0
    for id, p in pairs(r.points or {}) do if tostring(id) == MP.my_id then mine = p else theirs = p end end
    local opp_name = 'Opponent'
    for _, p in ipairs(run.players or {}) do if tostring(p.id) ~= MP.my_id then opp_name = tostring(p.name) end end
    n.points = { { 'You', mine }, { opp_name, theirs } }
  elseif r.reason == 'endless_over' then
    n.title, n.colour = 'ENDLESS RUN OVER', G.C.GOLD
    n.lines[1] = { 'The team beat the final boss and made it to ante ' .. tostring(G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or '?'), G.C.UI.TEXT_LIGHT }
  else
    local won = r.result == 'won'
    n.title, n.colour = won and 'TEAM VICTORY!' or 'TEAM DEFEATED', won and G.C.GREEN or G.C.RED
  end
  return n
end

local function notice_sig(n)
  local parts = { n.title, tostring(n.top), tostring(n.button), tostring(n.button and n.paused) }
  for _, l in ipairs(n.lines or {}) do parts[#parts + 1] = l[1] end
  for _, p in ipairs(n.points or {}) do parts[#parts + 1] = p[1] .. '=' .. tostring(p[2]) end
  return table.concat(parts, '|')
end

local function build_notice(n)
  local scale = (n.scale or 0.5) * (n.top and 0.8 or 1)
  local title = { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
    { n = G.UIT.O, config = { object = DynaText { string = { n.title }, colours = { n.colour or G.C.WHITE },
      shadow = true, silent = true, bump = n.bump, float = not n.bump, scale = scale, pop_in = 0.1, maxw = 9 } } },
  } }
  local body = {}
  for _, l in ipairs(n.lines or {}) do
    body[#body + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
      { n = G.UIT.T, config = { text = l[1], scale = l[3] or 0.34, colour = l[2] or G.C.UI.TEXT_LIGHT, shadow = true } },
    } }
  end
  if n.points then
    local row = {}
    for _, p in ipairs(n.points) do
      row[#row + 1] = { n = G.UIT.C, config = { align = 'cm', padding = 0.07, r = 0.08, colour = G.C.L_BLACK }, nodes = {
        { n = G.UIT.T, config = { text = p[1] .. '  ', scale = 0.32, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
        { n = G.UIT.T, config = { text = tostring(p[2]) .. ' pts', scale = 0.32, colour = G.C.GOLD, shadow = true } },
      } }
    end
    body[#body + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = row }
  end

  local contents
  if n.top then -- one compact strip, clear of the game over / win screen below it
    contents = { { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = { title } } }
    if #body > 0 then contents[2] = { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = body } end
  else
    local rows = { title }
    for _, b in ipairs(body) do rows[#rows + 1] = b end
    contents = { { n = G.UIT.C, config = { align = 'cm' }, nodes = rows } }
  end
  local def = passive({ n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.05 }, nodes = {
    { n = G.UIT.R, config = { align = 'cm', padding = 0.15, r = 0.1, colour = G.C.BLACK, emboss = 0.05,
      outline = 1, outline_colour = n.colour or G.C.JOKER_GREY }, nodes = contents },
  } })
  if n.button then -- added after passive(): this one is meant to be clicked
    local rows = contents[1].nodes
    rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.08 }, nodes = {
      UIBox_button { button = 'go_to_menu', label = { localize('b_main_menu') }, colour = G.C.RED, minw = 3, minh = 0.6, scale = 0.4 },
    } }
  end

  if n.top then
    local box = UIBox { definition = def, config = { align = 'tmi', offset = { x = 0, y = 0.2 }, major = G.ROOM_ATTACH,
      bond = 'Weak', instance_type = 'POPUP', can_collide = false } }
    keep_moving(box)
    keep_moving(box.UIRoot)
    return box
  end
  -- Centred on the play area (the room's centre is further left, under the sidebar's edge).
  return UIBox { definition = def, config = { align = 'cm', offset = { x = 1, y = -1 }, major = G.ROOM_ATTACH, bond = 'Weak' } }
end

local function current_notice(run, in_run, paused)
  local menu_open = G.OVERLAY_MENU and true or false
  local r = run and run.result
  if r and in_run and G.GAME and G.GAME.won and G.STATE ~= G.STATES.GAME_OVER then
    -- This player beat the final boss and may play on in Endless mode. The result shows over
    -- the win screen (or another menu) and goes away once they close it to keep playing.
    if menu_open then
      run.result_seen = true
    elseif run.result_seen or r.endless then
      if run.result_seen and r.endless then run.result = nil end -- Co-op: the team plays on
      return nil
    else
      local n = result_notice(run)
      n.top = true -- out of the way of the endless run, no button (the pause menu has one)
      return n
    end
  end
  if run and run.result then
    local n = result_notice(run)
    -- With a menu open (the game over / win screen has its own Main Menu button) show a
    -- strip above it; otherwise a panel with the button, rebuilt if the pause state
    -- changes so the button stays clickable.
    n.top, n.button, n.paused = menu_open, not menu_open, paused
    return n
  end
  if not in_run or run.finished or UI.hud_hidden then return nil end
  if run.gate and run.gate.released then
    -- Everyone is ready, but the next step waits for this player to close their menu.
    -- (Without a menu it runs within a frame or two: keep what's on screen.)
    if not menu_open then return 'hold' end
    return { title = 'Everyone is ready! Close the menu to continue', colour = G.C.GREEN,
      scale = 0.45, bump = true, top = true }
  end
  if run.gate or (run.coop_waiting and run.coop_waiting == run.slot) then
    if paused then return 'hold' end -- frozen under the menu anyway
    if run.gate then
      local who = run.gate_waiting_for
      who = (type(who) == 'table' and #who > 0) and table.concat(who, ', ')
        or (run.mode == 'duel' and 'your opponent' or 'your teammates')
      return { title = 'Waiting for ' .. who, bump = true, lines = {
        { run.gate.kind == 'shop' and 'to finish the blind before the shop opens...' or 'to be ready for the next blind...' },
        { 'TAB: view players', G.C.UI.TEXT_INACTIVE, 0.28 },
      } }
    end
    return { title = 'Out of hands', colour = G.C.RED, scale = 0.6, lines = {
      { 'Waiting for teammates to finish the blind...' },
    } }
  end
  local viewer_open = MP.viewer and MP.viewer.is_open and G.OVERLAY_MENU
  if run.reported_end and run.mode == 'duel' and not viewer_open then
    return { title = 'Waiting for your opponent to finish...', scale = 0.45, bump = true, top = menu_open }
  end
  return nil
end

-- Toasts ----------------------------------------------------------------------------

local TOAST_Y, TOAST_GAP, TOAST_OFFSCREEN = 3.3, 0.06, 12

local function build_toast(t, y, fresh)
  local accent = t.colour or G.C.UI.TEXT_INACTIVE
  local box = UIBox {
    definition = passive({ n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.02 }, nodes = {
      { n = G.UIT.R, config = { align = 'cl', padding = 0.08, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
        { n = G.UIT.C, config = { align = 'cm', minw = 0.1, minh = 0.34, r = 0.05, colour = accent }, nodes = {} },
        { n = G.UIT.C, config = { align = 'cl', padding = 0.03, maxw = 8 }, nodes = {
          { n = G.UIT.T, config = { text = tostring(t.text), scale = 0.32, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
        } },
      } },
    } }),
    -- A new toast starts off the right edge and slides in when its offset is set to 0.
    config = { align = 'tri', offset = { x = fresh and TOAST_OFFSCREEN or 0, y = y }, major = G.ROOM_ATTACH,
      bond = 'Weak', instance_type = 'POPUP', can_collide = false },
  }
  keep_moving(box)
  keep_moving(box.UIRoot)
  return box
end

local function sync_toasts()
  local live, y = {}, TOAST_Y
  for _, t in ipairs(MP.toasts) do
    live[t] = true
    local box = UI.toast_boxes[t]
    if box and box.REMOVED then box = nil end
    if not box and not t.failed then
      local ok, res = pcall(build_toast, t, y, t.t < 0.3)
      if ok then box = res else t.failed = true; print('[BalatroDuelCoop] toast error: ' .. tostring(res)) end
      UI.toast_boxes[t] = box
    end
    if box then
      box.alignment.offset.x = t.t > 4.6 and TOAST_OFFSCREEN or 0 -- slides out just before it expires
      box.alignment.offset.y = y
      y = y + box.T.h + TOAST_GAP
    end
  end
  for t, box in pairs(UI.toast_boxes) do
    if not live[t] then drop(box); UI.toast_boxes[t] = nil end
  end
end

-- Called every frame (from UI.update).
function UI.update_hud()
  if not G.ROOM_ATTACH then return end
  local paused = G.SETTINGS.paused and true or false
  local run = MP.run
  local in_run = run ~= nil and G.STAGE == G.STAGES.RUN

  if not (in_run and not UI.hud_hidden) then
    sync('bar', nil)
  elseif not paused then
    local pills = bar_pills(run)
    sync('bar', pills_sig(pills), function() return build_bar(pills) end)
  end

  local notice = current_notice(run, in_run, paused)
  if notice ~= 'hold' then
    sync('notice', notice and notice_sig(notice), function() return build_notice(notice) end)
  end

  sync_toasts()
end

return UI
