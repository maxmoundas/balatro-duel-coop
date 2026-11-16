-- In-run player viewer (TAB, or click the status bar): compare your board, cards and
-- score history with the players you're dueling / co-oping with.
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
    print('[BalatroMultiplayer] viewer error: ' .. tostring(res))
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

local function most_played(s)
  local h = s.poker_hands and s.poker_hands[1]
  if not h then return '-' end
  return hand_name(h.n) .. ' (Lv ' .. tostring(h.l or 1) .. ')'
end

local function points_of(id)
  return MP.run and MP.run.points and tonumber(MP.run.points[id] or MP.run.points[tonumber(id) or id]) or 0
end

-- ---------------------------------------------------------------------------
-- Tabs

local function compare_row(label, mine, theirs, better, mine_v, theirs_v)
  local cm, ct = G.C.WHITE, G.C.WHITE
  if better and type(mine_v) == 'number' and type(theirs_v) == 'number' and mine_v ~= theirs_v then
    local mine_better = (better == 'high') == (mine_v > theirs_v)
    if mine_better then cm = G.C.GREEN else ct = G.C.GREEN end
  end
  return row({ cell(label, 2.6, G.C.UI.TEXT_INACTIVE), cell(mine, 3.6, cm), cell(theirs, 3.6, ct) }, { padding = 0.015 })
end

local function compare_tab()
  local c = V.ctx
  local me, them = c.me, c.them
  local blind = function(s)
    if not s.blind then return '-' end
    return s.blind .. ' (' .. fmt(s.chips or 0) .. ' / ' .. fmt(s.target or 0) .. ')'
  end
  local status = function(s)
    if s.status == 'won' then return 'Beat the final boss' elseif s.status == 'lost' then return 'Run over' end
    return s.state or '-'
  end
  local rows = {
    row({ cell('', 2.6), cell('You', 3.6, G.C.GOLD, 0.4), cell(c.name, 3.6, G.C.GOLD, 0.4) }),
    compare_row('Status', status(me), status(them)),
    compare_row('Ante / Round', 'Ante ' .. tostring(me.ante or '-') .. '  Round ' .. tostring(me.round or '-'),
      'Ante ' .. tostring(them.ante or '-') .. '  Round ' .. tostring(them.round or '-'), 'high', me.slot, them.slot),
    compare_row('Current blind', blind(me), blind(them)),
    compare_row('Money', '$' .. tostring(me.money or 0), '$' .. tostring(them.money or 0), 'high', me.money, them.money),
    compare_row('Hands / Discards', tostring(me.hands_left or '-') .. ' / ' .. tostring(me.discards_left or '-'),
      tostring(them.hands_left or '-') .. ' / ' .. tostring(them.discards_left or '-')),
    compare_row('Best hand', fmt(me.best or 0), fmt(them.best or 0), 'high', me.best, them.best),
  }
  if MP.run.mode == 'duel' then
    local mp, tp = points_of(MP.my_id), points_of(c.id)
    rows[#rows + 1] = compare_row('Points', tostring(mp), tostring(tp), 'high', mp, tp)
  end
  rows[#rows + 1] = compare_row('Jokers', #(me.jokers or {}) .. ' / ' .. tostring(me.joker_slots or '-'),
    #(them.jokers or {}) .. ' / ' .. tostring(them.joker_slots or '-'))
  rows[#rows + 1] = compare_row('Cards in deck', tostring(me.deck_count or 0) .. ' / ' .. tostring(me.deck_total or 0),
    tostring(them.deck_count or 0) .. ' / ' .. tostring(them.deck_total or 0))
  rows[#rows + 1] = compare_row('Most played', most_played(me), most_played(them))

  return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.08 }, nodes = {
    panel(rows),
    panel({
      labelled_cards(c.name .. "'s jokers", them.jokers, false, 0.5, 8.5),
      labelled_cards('Your jokers', me.jokers, false, 0.5, 8.5),
    }, G.C.L_BLACK),
  } }
end

local function cards_tab()
  local c = V.ctx
  local them = c.them
  return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.08 }, nodes = {
    panel({
      labelled_cards('Jokers ' .. #(them.jokers or {}) .. '/' .. tostring(them.joker_slots or '-'), them.jokers, false, 0.7, 9),
      labelled_cards('Consumables ' .. #(them.cons or {}) .. '/' .. tostring(them.cons_slots or '-'), them.cons, false, 0.6, 9),
      labelled_cards('Hand', them.hand, true, 0.6, 9),
    }, G.C.L_BLACK),
    row({ T('Hover a card to read it. Face-down cards stay hidden.', 0.28, G.C.UI.TEXT_INACTIVE) }),
  } }
end

local function by_slot(history)
  local m = {}
  for _, rec in ipairs(history or {}) do
    if type(rec) == 'table' and rec.slot then m[tonumber(rec.slot)] = rec end
  end
  return m
end

local function result_text(rec)
  if not rec then return '-', G.C.UI.TEXT_INACTIVE end
  if rec.skipped then return 'Skipped', G.C.UI.TEXT_INACTIVE end
  if rec.won == true then return 'Beat', G.C.GREEN end
  if rec.won == false then return 'Failed', G.C.RED end
  return 'Playing', G.C.UI.TEXT_INACTIVE
end

local function hands_text(rec)
  if not rec or rec.skipped then return '-' end
  local parts = {}
  for _, s in ipairs(rec.hands or {}) do parts[#parts + 1] = fmt(s) end
  return #parts > 0 and table.concat(parts, ' / ') or '-'
end

local function history_tab()
  local c = V.ctx
  local mine, theirs = by_slot(c.me.history), by_slot(c.them.history)
  local max_slot = 0
  for s in pairs(mine) do max_slot = math.max(max_slot, s) end
  for s in pairs(theirs) do max_slot = math.max(max_slot, s) end

  -- Per-ante totals
  local antes, ante_rows = {}, {}
  local function add(rec, who)
    if rec.skipped then return end
    local a = tonumber(rec.ante) or 0
    antes[a] = antes[a] or { me_total = 0, me_best = 0, them_total = 0, them_best = 0 }
    antes[a][who .. '_total'] = antes[a][who .. '_total'] + (rec.total or 0)
    antes[a][who .. '_best'] = math.max(antes[a][who .. '_best'], rec.best or 0)
  end
  for _, r in pairs(mine) do add(r, 'me') end
  for _, r in pairs(theirs) do add(r, 'them') end
  local ante_keys = {}
  for a in pairs(antes) do ante_keys[#ante_keys + 1] = a end
  table.sort(ante_keys)
  ante_rows[1] = row({ cell('Ante', 1.2, G.C.GOLD), cell('Your total', 2.2, G.C.GOLD), cell(c.name .. ' total', 2.2, G.C.GOLD),
    cell('Your best', 2, G.C.GOLD), cell(c.name .. ' best', 2, G.C.GOLD) })
  for _, a in ipairs(ante_keys) do
    local d = antes[a]
    local function col(x, y) if x == y then return G.C.WHITE, G.C.WHITE end return (x > y and G.C.GREEN or G.C.WHITE), (y > x and G.C.GREEN or G.C.WHITE) end
    local t1, t2 = col(d.me_total, d.them_total)
    local b1, b2 = col(d.me_best, d.them_best)
    ante_rows[#ante_rows + 1] = row({ cell(a, 1.2), cell(fmt(d.me_total), 2.2, t1), cell(fmt(d.them_total), 2.2, t2),
      cell(fmt(d.me_best), 2, b1), cell(fmt(d.them_best), 2, b2) }, { padding = 0.01 })
  end
  if #ante_keys == 0 then ante_rows[#ante_rows + 1] = row({ T('No blinds played yet', 0.3, G.C.UI.TEXT_INACTIVE) }) end

  -- Last 8 blinds
  local blind_rows = { row({ cell('#', 0.6, G.C.GOLD), cell('Blind', 2.4, G.C.GOLD), cell('Your hands', 2.9, G.C.GOLD),
    cell('', 0.9), cell(c.name .. "'s hands", 2.9, G.C.GOLD), cell('', 0.9) }) }
  for s = math.max(1, max_slot - 7), max_slot do
    local m, t = mine[s], theirs[s]
    local any = m or t
    local name = any and ('A' .. tostring(any.ante or '?') .. ' ' .. tostring(any.blind or '')) or '-'
    local mr, mc = result_text(m)
    local tr, tc = result_text(t)
    blind_rows[#blind_rows + 1] = row({ cell(s, 0.6), cell(name, 2.4), cell(hands_text(m), 2.9), cell(mr, 0.9, mc, 0.28),
      cell(hands_text(t), 2.9), cell(tr, 0.9, tc, 0.28) }, { padding = 0.01 })
  end
  if max_slot == 0 then blind_rows[#blind_rows + 1] = row({ T('No blinds played yet', 0.3, G.C.UI.TEXT_INACTIVE) }) end

  return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR, padding = 0.08 }, nodes = {
    row({ T('Score by ante', 0.4, G.C.WHITE) }),
    panel(ante_rows),
    row({ T('Recent blinds (score of every hand)', 0.4, G.C.WHITE) }),
    panel(blind_rows),
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
    contents[#contents + 1] = create_tabs {
      tabs = {
        { label = 'Compare', chosen = true, tab_definition_function = function() return protected(compare_tab) end },
        { label = 'Their cards', tab_definition_function = function() return protected(cards_tab) end },
        { label = 'History', tab_definition_function = function() return protected(history_tab) end },
      },
      tab_h = 7.4, snap_to_nav = true,
    }
  end
  return create_UIBox_generic_options { contents = contents }
end

function V.open()
  if not MP.run or G.STAGE ~= G.STAGES.RUN then return end
  V.is_open = true
  local saved = G.GAME and G.GAME.pseudorandom and copy_table(G.GAME.pseudorandom)
  local ok, def = pcall(V.definition)
  if saved then G.GAME.pseudorandom = saved end
  if not ok then
    print('[BalatroMultiplayer] viewer error: ' .. tostring(def))
    MP.toast('Could not open the player viewer', G.C.RED)
    V.is_open = false
    return
  end
  G.FUNCS.overlay_menu { definition = def }
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
    if V.is_open and G.OVERLAY_MENU then V.open() end
  end
end

G.FUNCS.mp_viewer_target = function(args)
  local list = others()
  local p = list[args.to_key]
  if p then V.target = tostring(p.id) end
  V.pending_open = true
end

G.FUNCS.mp_open_viewer = function() V.open() end

return V
