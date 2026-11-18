-- In-run player viewer (TAB, or click the status bar): compare your board, full deck,
-- poker hand levels, vouchers and score history with the other players.
--
-- Other players' cards are rebuilt locally as real Card objects from their snapshot,
-- so hovering shows the normal tooltips. Card creation can touch the seeded RNG
-- (e.g. To Do List), so every build runs inside `protected()`, which restores
-- G.GAME.pseudorandom afterwards - viewing must never change your own run's odds.

local V = { is_open = false, target = nil, pending_open = false }
MP.viewer = V

local fmt = function(n) return MP.fmt(n) end

-- ---------------------------------------------------------------------------
-- Data

local function others()
  local list = {}
  for _, p in ipairs(MP.run and MP.run.players or {}) do
    if tostring(p.id) ~= MP.my_id then list[#list + 1] = p end
  end
  return list
end

local function target_player()
  local list = others()
  for _, p in ipairs(list) do
    if tostring(p.id) == V.target then return p end
  end
  V.target = list[1] and tostring(list[1].id) or nil
  return list[1]
end

local function protected(fn)
  local saved = G.GAME and G.GAME.pseudorandom and copy_table(G.GAME.pseudorandom)
  local ok, res = pcall(fn)
  if saved then G.GAME.pseudorandom = saved end
  if not ok then
    print('[BalatroDuelCoop] viewer error: ' .. tostring(res))
    return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.2 }, nodes = {
      { n = G.UIT.T, config = { text = 'Could not display this view', scale = 0.4, colour = G.C.RED } },
    } }
  end
  return res
end

-- ---------------------------------------------------------------------------
-- UI helpers

local function T(text, scale, colour)
  return { n = G.UIT.T, config = { text = tostring(text), scale = scale or 0.35, colour = colour or G.C.WHITE } }
end

local function row(nodes, cfg)
  cfg = cfg or {}
  cfg.align = cfg.align or 'cm'
  return { n = G.UIT.R, config = cfg, nodes = nodes }
end

local function cell(text, w, colour, scale)
  return { n = G.UIT.C, config = { align = 'cm', minw = w, maxw = w }, nodes = { T(text, scale or 0.32, colour) } }
end

local function panel(nodes, colour)
  return { n = G.UIT.R, config = { align = 'cm', padding = 0.08, r = 0.1, colour = colour or G.C.BLACK, emboss = 0.05 }, nodes = {
    { n = G.UIT.C, config = { align = 'cm' }, nodes = nodes },
  } }
end

local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then merge(dst[k], v) else dst[k] = v end
  end
end

local function make_card(d, playing, area, w, h)
  local params = { bypass_discovery_center = true, bypass_discovery_ui = true, bypass_lock = true }
  local card
  if playing then
    if d.hidden then
      card = Card(area.T.x, area.T.y, w, h, G.P_CARDS.S_A, G.P_CENTERS.c_base, params)
      card.facing, card.sprite_facing = 'back', 'back'
      return card
    end
    local front = G.P_CARDS[d.c or '']
    if not front then return nil end
    card = Card(area.T.x, area.T.y, w, h, front, G.P_CENTERS[d.e or ''] or G.P_CENTERS.c_base, params)
  else
    local center = G.P_CENTERS[d.k or '']
    if not center then return nil end -- e.g. a modded joker this player doesn't have
    card = Card(area.T.x, area.T.y, w, h, nil, center, params)
  end
  if d.ab then pcall(merge, card.ability, d.ab) end
  if d.ed then pcall(card.set_edition, card, d.ed, true, true) end
  if d.s then pcall(card.set_seal, card, d.s, true, true) end
  if d.ab then
    -- Some jokers recompute values from the *local* run each frame (Steel Joker etc.);
    -- keep showing the owner's numbers.
    local ab = d.ab
    card.update = function(self, dt)
      Card.update(self, dt)
      merge(self.ability, ab)
    end
  end
  return card
end

local function card_row(list, playing, scale, max_w)
  list = list or {}
  if #list == 0 then
    return { n = G.UIT.C, config = { align = 'cm', minh = G.CARD_H * scale * 0.6 }, nodes = { T('None', 0.32, G.C.UI.TEXT_INACTIVE) } }
  end
  local cw, ch = G.CARD_W * scale, G.CARD_H * scale
  local w = math.min(#list * cw * 1.05, max_w or 9)
  local area = CardArea(G.ROOM.T.x, G.ROOM.T.h, w, ch,
    { card_limit = #list, type = 'title', highlight_limit = 0, collection = true })
  for _, d in ipairs(list) do
    local ok, card = pcall(make_card, d, playing, area, cw, ch)
    if ok and card then area:emplace(card) end
  end
  return { n = G.UIT.O, config = { object = area } }
end

local function labelled_cards(label, list, playing, scale, max_w)
  return row({
    { n = G.UIT.C, config = { align = 'cm', minw = 1.9, maxw = 1.9 }, nodes = { T(label, 0.3, G.C.UI.TEXT_INACTIVE) } },
    card_row(list, playing, scale, max_w),
  }, { padding = 0.04 })
end

local function hand_name(name)
  local ok, loc = pcall(localize, name, 'poker_hands')
  return (ok and loc and loc ~= 'ERROR') and loc or name
end

-- Counts of upgraded cards in a full deck.
local function deck_stats(s)
  local st = { total = 0, enh = 0, seal = 0, ed = 0 }
  for _, d in ipairs(s.full_deck or {}) do
    st.total = st.total + 1
    if d.e and d.e ~= 'c_base' then st.enh = st.enh + 1 end
    if d.s then st.seal = st.seal + 1 end
    if d.ed then st.ed = st.ed + 1 end
  end
  return st
end

local function deck_summary(s)
  local st = deck_stats(s)
  return st.total .. ' cards: ' .. st.enh .. ' enh, ' .. st.seal .. ' seal, ' .. st.ed .. ' ed'
end

local function center_name(set, key)
  local ok, name = pcall(localize, { type = 'name_text', set = set, key = key })
  if ok and name and name ~= 'ERROR' then return name end
  local c = (set == 'Tag' and G.P_TAGS or G.P_CENTERS)[key]
  return c and c.name or key
end

local function points_of(id)
  return MP.run and MP.run.points and tonumber(MP.run.points[id] or MP.run.points[tonumber(id) or id]) or 0
end

-- ---------------------------------------------------------------------------
-- Tabs

-- A "stat | you | them" table. Each stat is { label, mine, theirs, better = 'high'|'low',
-- mv = number, tv = number }; when `better` is set, the better number is green.
-- `sub` (optional) puts a small line under each name in the header (e.g. status).
local STAT_LW, STAT_VW = 3, 3.4

local function stat_table(name, stats, sub)
  local function head(text, small)
    local nodes = { row({ T(text, 0.42, G.C.GOLD) }) }
    if small then nodes[2] = row({ T(small, 0.27, G.C.UI.TEXT_INACTIVE) }) end
    return { n = G.UIT.C, config = { align = 'cm', minw = STAT_VW, maxw = STAT_VW }, nodes = nodes }
  end
  local rows = { row({ cell('', STAT_LW), head('You', sub and sub[1]), head(name, sub and sub[2]) }, { padding = 0.04 }) }
  for i, s in ipairs(stats) do
    local cm, ct = G.C.WHITE, G.C.WHITE
    if s.better and type(s.mv) == 'number' and type(s.tv) == 'number' and s.mv ~= s.tv then
      if (s.better == 'high') == (s.mv > s.tv) then cm = G.C.GREEN else ct = G.C.GREEN end
    end
    rows[#rows + 1] = row({
      { n = G.UIT.C, config = { align = 'cl', minw = STAT_LW, maxw = STAT_LW, padding = 0.02 }, nodes = { T(s[1], 0.32, G.C.UI.TEXT_INACTIVE) } },
      cell(s[2], STAT_VW, cm, 0.4), cell(s[3], STAT_VW, ct, 0.4),
    }, { padding = 0.06, r = 0.08, minh = 0.5, colour = i % 2 == 1 and G.C.L_BLACK or G.C.CLEAR })
  end
  return rows
end

local function status_text(s)
  if s.status == 'won' then return 'Beat the final boss' elseif s.status == 'lost' then return 'Run over' end
  return s.state or ''
end

local function compare_tab()
  local c = V.ctx
  local me, them = c.me, c.them
  local stats = {
    { 'Money', '$' .. tostring(me.money or 0), '$' .. tostring(them.money or 0), better = 'high', mv = me.money, tv = them.money },
    { 'Hands left', tostring(me.hands_left or '-'), tostring(them.hands_left or '-'),
      better = 'high', mv = me.hands_left, tv = them.hands_left },
    { 'Discards left', tostring(me.discards_left or '-'), tostring(them.discards_left or '-'),
      better = 'high', mv = me.discards_left, tv = them.discards_left },
    { 'Hand size', tostring(me.hand_size or '-'), tostring(them.hand_size or '-'),
      better = 'high', mv = me.hand_size, tv = them.hand_size },
    { 'Draw pile', tostring(me.deck_count or 0) .. ' of ' .. tostring(me.deck_total or 0),
      tostring(them.deck_count or 0) .. ' of ' .. tostring(them.deck_total or 0) },
    { 'Best hand', fmt(me.best or 0), fmt(them.best or 0), better = 'high', mv = me.best, tv = them.best },
  }
  if MP.run.mode == 'duel' then
    local mp, tp = points_of(MP.my_id), points_of(c.id)
    stats[#stats + 1] = { 'Points', tostring(mp), tostring(tp), better = 'high', mv = mp, tv = tp }
  end

  return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.08 }, nodes = {
    panel(stat_table(c.name, stats, { status_text(me), status_text(them) })),
    panel({
      labelled_cards(c.name .. "'s jokers", them.jokers, false, 0.5, 8.5),
      labelled_cards('Your jokers', me.jokers, false, 0.5, 8.5),
    }, G.C.L_BLACK),
  } }
end

local function cards_tab()
  local c = V.ctx
  local them = c.them
  local vouchers = {}
  for _, k in ipairs(them.vouchers or {}) do vouchers[#vouchers + 1] = { k = k } end
  local tags = {}
  for _, k in ipairs(them.tags or {}) do tags[#tags + 1] = center_name('Tag', k) end
  return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.06 }, nodes = {
    panel({
      labelled_cards('Jokers ' .. #(them.jokers or {}) .. '/' .. tostring(them.joker_slots or '-'), them.jokers, false, 0.6, 9),
      labelled_cards('Consumables ' .. #(them.cons or {}) .. '/' .. tostring(them.cons_slots or '-'), them.cons, false, 0.5, 9),
      labelled_cards('Vouchers ' .. #vouchers, vouchers, false, 0.5, 9),
      labelled_cards('Hand ' .. #(them.hand or {}) .. '/' .. tostring(them.hand_size or '-'), them.hand, true, 0.5, 9),
    }, G.C.L_BLACK),
    row({ T('Tags: ' .. (#tags > 0 and table.concat(tags, ', ') or 'none'), 0.3, G.C.WHITE) }),
    row({ T('Hover a card to read it. Face-down cards stay hidden.', 0.28, G.C.UI.TEXT_INACTIVE) }),
  } }
end

-- Full deck, one row per suit, high ranks first (like the game's deck view).
local SUIT_ORDER = { Spades = 1, Hearts = 2, Clubs = 3, Diamonds = 4 }

local function rank_sort_value(card_key)
  local pc = G.P_CARDS[card_key or '']
  local r = pc and SMODS and SMODS.Ranks and SMODS.Ranks[pc.value]
  return r and (r.sort_nominal or r.id or r.nominal) or 0
end

local function deck_tab()
  local c = V.ctx
  local owner = V.deck_owner == 'me' and 'me' or 'them'
  local deck = c[owner].full_deck or {}
  local groups, names = {}, {}
  for _, d in ipairs(deck) do
    local pc = G.P_CARDS[d.c or '']
    local suit = pc and pc.suit or '?'
    if not groups[suit] then groups[suit] = {}; names[#names + 1] = suit end
    groups[suit][#groups[suit] + 1] = d
  end
  table.sort(names, function(a, b)
    local oa, ob = SUIT_ORDER[a] or 99, SUIT_ORDER[b] or 99
    if oa ~= ob then return oa < ob end
    return a < b
  end)
  local rows = {}
  for _, suit in ipairs(names) do
    local list = groups[suit]
    table.sort(list, function(a, b) return rank_sort_value(a.c) > rank_sort_value(b.c) end)
    local ok, loc = pcall(localize, suit, 'suits_plural')
    local label = ((ok and loc and loc ~= 'ERROR') and loc or suit) .. ' (' .. #list .. ')'
    rows[#rows + 1] = labelled_cards(label, list, true, 0.42, 10)
  end
  if #rows == 0 then rows[1] = row({ T('No deck data yet', 0.35, G.C.UI.TEXT_INACTIVE) }) end

  local whose = owner == 'me' and 'Your deck' or (c.name .. "'s deck")
  return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.06 }, nodes = {
    row({
      T(whose .. '  -  ' .. deck_summary(c[owner]), 0.32, G.C.WHITE),
      { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {
        UIBox_button { label = { owner == 'me' and ('Show ' .. c.name) or 'Show mine' }, button = 'mp_viewer_deck_owner',
          colour = G.C.BLUE, minw = 2.2, minh = 0.4, scale = 0.3 },
      } },
    }),
    panel(rows, G.C.L_BLACK),
    row({ T('Every card in the deck, wherever it is right now. Hover a card to read it.', 0.26, G.C.UI.TEXT_INACTIVE) }),
  } }
end

-- Poker hand levels side by side.
local function hands_tab()
  local c = V.ctx
  local mine, theirs, order = {}, {}, {}
  for _, h in ipairs(c.me.poker_hands or {}) do mine[h.n] = h; order[#order + 1] = h end
  for _, h in ipairs(c.them.poker_hands or {}) do
    theirs[h.n] = h
    if not mine[h.n] then order[#order + 1] = h end
  end
  table.sort(order, function(a, b) return (a.o or 99) < (b.o or 99) end)
  local function desc(h)
    if not h then return '-', '-' end
    return 'Lv ' .. tostring(h.l or 1), fmt(h.c or 0) .. ' x ' .. fmt(h.m or 0)
  end
  local rows = { row({ cell('Hand', 2.8, G.C.GOLD), cell('You', 1, G.C.GOLD), cell('', 1.9), cell('Played', 1, G.C.GOLD),
    cell(c.name, 1, G.C.GOLD), cell('', 1.9), cell('Played', 1, G.C.GOLD) }) }
  for _, h in ipairs(order) do
    local m, t = mine[h.n], theirs[h.n]
    local ml, mv = desc(m)
    local tl, tv = desc(t)
    local mlv, tlv = m and m.l or 0, t and t.l or 0
    local cm = mlv > tlv and G.C.GREEN or G.C.WHITE
    local ct = tlv > mlv and G.C.GREEN or G.C.WHITE
    rows[#rows + 1] = row({ cell(hand_name(h.n), 2.8), cell(ml, 1, cm), cell(mv, 1.9, G.C.UI.TEXT_INACTIVE, 0.28),
      cell(tostring(m and m.p or 0), 1), cell(tl, 1, ct), cell(tv, 1.9, G.C.UI.TEXT_INACTIVE, 0.28),
      cell(tostring(t and t.p or 0), 1) }, { padding = 0.008 })
  end
  return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.08 }, nodes = {
    panel(rows),
    row({ T('Higher level in green. Chips x Mult is the base value at that level.', 0.26, G.C.UI.TEXT_INACTIVE) }),
  } }
end

local function by_slot(history)
  local m = {}
  for _, rec in ipairs(history or {}) do
    if type(rec) == 'table' and rec.slot then m[tonumber(rec.slot)] = rec end
  end
  return m
end

-- Whole-run totals from a player's blind history.
local function run_totals(hist)
  local t = { beaten = 0, skipped = 0, score = 0, hands = 0, best = 0 }
  for _, rec in pairs(hist) do
    if rec.skipped then
      t.skipped = t.skipped + 1
    else
      if rec.won == true then t.beaten = t.beaten + 1 end
      t.score = t.score + (rec.total or 0)
      t.hands = t.hands + #(rec.hands or {})
      t.best = math.max(t.best, rec.best or 0)
    end
  end
  t.avg = t.hands > 0 and math.floor(t.score / t.hands) or 0
  return t
end

-- A value with a small detail line under it.
local function cell2(top, bottom, w, colour)
  local nodes = { row({ T(top, 0.36, colour) }) }
  if bottom and bottom ~= '' then nodes[2] = row({ T(bottom, 0.26, G.C.UI.TEXT_INACTIVE) }) end
  return { n = G.UIT.C, config = { align = 'cm', minw = w, maxw = w }, nodes = nodes }
end

-- One player's part in one blind: what they scored (green = blind beaten, red = failed)
-- and how - hands used, best hand and, in Co-op, their share of the target.
local function blind_cell(rec, w, coop)
  if not rec then return cell2('-', nil, w, G.C.UI.TEXT_INACTIVE) end
  if rec.skipped then return cell2('Skipped', nil, w, G.C.UI.TEXT_INACTIVE) end
  local n = #(rec.hands or {})
  local colour = rec.won == true and G.C.GREEN or rec.won == false and G.C.RED or G.C.WHITE
  local detail
  if n == 0 then
    detail = rec.won == nil and 'playing' or 'no hands played'
  else
    detail = n .. (n == 1 and ' hand' or ' hands') .. ', best ' .. fmt(rec.best or 0)
    if coop and (rec.target or 0) > 0 then
      detail = detail .. ', ' .. math.floor((rec.total or 0) / rec.target * 100 + 0.5) .. '%'
    end
    if rec.won == nil then detail = detail .. ' (playing)' end
  end
  return cell2(fmt(rec.total or 0), detail, w, colour)
end

local HIST_BLINDS = 4 -- keeps the tab within the overlay's height

local function history_tab()
  local c = V.ctx
  local coop = MP.run.mode == 'coop'
  local mine, theirs = by_slot(c.me.history), by_slot(c.them.history)
  local max_slot = 0
  for s in pairs(mine) do max_slot = math.max(max_slot, s) end
  for s in pairs(theirs) do max_slot = math.max(max_slot, s) end

  -- Whole run at a glance.
  local a, b = run_totals(mine), run_totals(theirs)
  local function num(label, x, y, f) return { label, (f or fmt)(x), (f or fmt)(y), better = 'high', mv = x, tv = y } end
  local stats = {}
  if not coop then stats[#stats + 1] = num('Blinds beaten', a.beaten, b.beaten, tostring) end
  stats[#stats + 1] = num(coop and 'Score contributed' or 'Total score', a.score, b.score)
  stats[#stats + 1] = num('Average hand', a.avg, b.avg)
  stats[#stats + 1] = num('Best hand', a.best, b.best)
  stats[#stats + 1] = { 'Hands played / skips', a.hands .. ' / ' .. a.skipped, b.hands .. ' / ' .. b.skipped }

  -- Recent blinds, newest first.
  local BW, TW, PW = 2.9, 1.8, 3.6
  local blind_rows = { row({ cell('Blind', BW, G.C.GOLD), cell('Target', TW, G.C.GOLD), cell('You', PW, G.C.GOLD),
    cell(c.name, PW, G.C.GOLD) }, { padding = 0.03 }) }
  for s = max_slot, math.max(1, max_slot - HIST_BLINDS + 1), -1 do
    local m, t = mine[s], theirs[s]
    local any = m or t
    if any then
      local played = (m and not m.skipped and m) or (t and not t.skipped and t) or any
      local target = (m and m.target) or (t and t.target)
      blind_rows[#blind_rows + 1] = row({
        cell2(tostring(played and played.blind or any.blind or '?'), 'Ante ' .. tostring(any.ante or '?'), BW, G.C.WHITE),
        cell(target and fmt(target) or '-', TW, G.C.UI.TEXT_LIGHT, 0.34),
        blind_cell(m, PW, coop), blind_cell(t, PW, coop),
      }, { padding = 0.05, r = 0.08, colour = (max_slot - s) % 2 == 0 and G.C.L_BLACK or G.C.CLEAR })
    end
  end
  if max_slot == 0 then blind_rows[#blind_rows + 1] = row({ T('No blinds played yet', 0.3, G.C.UI.TEXT_INACTIVE) }, { padding = 0.1 }) end

  return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.06 }, nodes = {
    panel(stat_table(c.name, stats)),
    row({ T('Recent blinds', 0.36, G.C.WHITE) }, { padding = 0.02 }),
    panel(blind_rows),
    row({ T(coop and 'Score each player put in (green = blind beaten).  % = share of the target.'
      or 'Score in each blind (green = beaten, red = failed).', 0.26, G.C.UI.TEXT_INACTIVE) }),
  } }
end

-- ---------------------------------------------------------------------------
-- Overlay

function V.definition()
  local run = MP.run
  local tp = target_player()
  local contents = { row({ T('PLAYERS', 0.6, G.C.GOLD) }) }

  local list = others()
  if #list > 1 then
    local names, current = {}, 1
    for i, p in ipairs(list) do
      names[i] = p.name
      if tostring(p.id) == V.target then current = i end
    end
    contents[#contents + 1] = row({ create_option_cycle { options = names, current_option = current,
      opt_callback = 'mp_viewer_target', w = 4, scale = 0.8, colour = G.C.RED } })
  end

  local snap = tp and run.snapshots[tostring(tp.id)]
  if not tp then
    contents[#contents + 1] = row({ T('No other players in this game', 0.4) }, { padding = 0.3 })
  elseif not snap then
    contents[#contents + 1] = row({ T('Waiting for ' .. tostring(tp.name) .. "'s board...", 0.4) }, { padding = 0.3 })
  else
    local ok, me = pcall(MP.build_snapshot)
    V.ctx = { id = tostring(tp.id), name = tostring(tp.name), them = snap.data, me = ok and me or {} }
    local age = math.floor(love.timer.getTime() - snap.t)
    contents[#contents + 1] = row({ T('Updated ' .. (age <= 1 and 'just now' or (age .. 's ago')) .. '  |  TAB to close', 0.28, G.C.UI.TEXT_INACTIVE) })
    -- Balatro builds a tab when it is selected, so each builder records itself as the
    -- current tab; switching player or deck then reopens on the tab you were looking at.
    local specs = {
      { 'compare', 'Compare', compare_tab }, { 'cards', 'Their cards', cards_tab }, { 'deck', 'Deck', deck_tab },
      { 'hands', 'Poker hands', hands_tab }, { 'history', 'History', history_tab },
    }
    local current = 'compare'
    for _, spec in ipairs(specs) do if spec[1] == V.tab then current = V.tab end end
    local tabs = {}
    for i, spec in ipairs(specs) do
      tabs[i] = { label = spec[2], chosen = spec[1] == current, tab_definition_function = function()
        V.tab = spec[1]
        return protected(spec[3])
      end }
    end
    contents[#contents + 1] = create_tabs { tabs = tabs, tab_h = 7.6, snap_to_nav = true }
  end
  return create_UIBox_generic_options { contents = contents }
end

-- `reopen`: rebuilding the viewer that is already on screen (another player, the other
-- deck). It keeps its tab and appears in place instead of sliding in again.
function V.open(reopen)
  if not MP.run or G.STAGE ~= G.STAGES.RUN then return end
  V.is_open = true
  if not reopen then V.tab = nil end -- a fresh open starts on Compare
  -- Pause like Balatro's own Run Info / deck overlays, freezing the run underneath. It must
  -- happen BEFORE building: anything created unpaused doesn't move while paused, so the
  -- first tab would never slide into place.
  local was_paused = G.SETTINGS.paused
  G.SETTINGS.paused = true
  local saved = G.GAME and G.GAME.pseudorandom and copy_table(G.GAME.pseudorandom)
  local ok, def = pcall(V.definition)
  if saved then G.GAME.pseudorandom = saved end
  if not ok then
    print('[BalatroDuelCoop] viewer error: ' .. tostring(def))
    MP.toast('Could not open the player viewer', G.C.RED)
    V.is_open = false
    G.SETTINGS.paused = was_paused
    return
  end
  G.FUNCS.overlay_menu { definition = def, config = reopen and { offset = { x = 0, y = 0 } } or nil }
end

function V.toggle()
  if V.is_open and G.OVERLAY_MENU then
    G.FUNCS.exit_overlay_menu()
  elseif not G.OVERLAY_MENU then
    V.open()
  end
end

-- Re-open outside the option-cycle callback (its UI is replaced by the reopen).
function V.update()
  if V.pending_open then
    V.pending_open = false
    if V.is_open and G.OVERLAY_MENU then V.open(true) end
  end
end

G.FUNCS.mp_viewer_target = function(args)
  local list = others()
  local p = list[args.to_key]
  if p then V.target = tostring(p.id) end
  V.pending_open = true
end

-- Deck tab: switch between their deck and yours.
G.FUNCS.mp_viewer_deck_owner = function()
  V.deck_owner = V.deck_owner ~= 'me' and 'me' or 'them'
  V.pending_open = true
end

G.FUNCS.mp_open_viewer = function() V.open() end

return V
