-- In-game host server: runs relay.lua on a LÖVE thread.
-- The host's own game connects over loopback TCP; friends arrive over Steam P2P,
-- which the main thread (p2p.lua) bridges in as "virtual" connections.
--
-- Thread args: relay_src, json_src, port, cmd_channel, event_channel
--   cmd:   "stop", "P|open|<steamid>", "P|line|<steamid>|<json>", "P|close|<steamid>"
--   event: "listening", "error|<msg>", "log|<msg>", "stopped",
--          "P|<steamid>|<json>" (line for that peer), "X|<steamid>" (relay dropped the peer)

local relay_src, json_src, port, cmd_ch, evt_ch = ...
local socket = require('socket')

local function load_chunk(src, name)
  local f, err = (loadstring or load)(src, '=' .. name)
  if not f then error(err) end
  return f()
end

local json = load_chunk(json_src, 'json.lua')
local Relay = load_chunk(relay_src, 'relay.lua')
math.randomseed(os.time() + math.floor((socket.gettime() % 1) * 1000000))

local MAX_LINE = 512 * 1024
local IDLE_TIMEOUT = 90

-- Loopback only: no firewall prompt, and nothing else on the network can reach it.
-- Remote players come in through Steam instead.
local server, bind_err = socket.bind('127.0.0.1', port)
if not server then
  evt_ch:push('error|' .. tostring(bind_err))
  return
end
server:settimeout(0)
evt_ch:push('listening')

local relay = Relay.new({ json = json, min_players = 2, log = function(s) evt_ch:push('log|' .. s) end })
local clients = {}

local function drop(c)
  if c.closed then return end
  c.closed = true
  clients[c.key] = nil
  if c.sock then pcall(function() c.sock:close() end) end
  if c.peer then evt_ch:push('X|' .. c.peer) end
  local ok, err = pcall(relay.disconnect, relay, c.player)
  if not ok then evt_ch:push('log|disconnect error: ' .. tostring(err)) end
end

local function open_peer(id, now)
  local key = 'p:' .. id
  if clients[key] then return clients[key] end
  local c = { key = key, peer = id, last = now }
  c.player = relay:connect(function(line) evt_ch:push('P|' .. id .. '|' .. line) end)
  clients[key] = c
  return c
end

while true do
  local now = socket.gettime()
  local cmd = cmd_ch:pop()
  while cmd do
    if cmd == 'stop' then
      for _, c in pairs(clients) do if c.sock then pcall(function() c.sock:close() end) end end
      server:close()
      evt_ch:push('stopped')
      return
    end
    local op, id, rest = cmd:match('^P|(%a+)|(%d+)|?(.*)$')
    if op == 'open' then
      open_peer(id, now)
    elseif op == 'line' then
      local c = open_peer(id, now)
      c.last = now
      if #rest <= MAX_LINE then
        local ok, rerr = pcall(relay.receive, relay, c.player, rest)
        if not ok then evt_ch:push('log|relay error: ' .. tostring(rerr)) end
      end
    elseif op == 'close' then
      local c = clients['p:' .. id]
      if c then c.peer = nil; drop(c) end -- they said bye: no need to tell them
    end
    cmd = cmd_ch:pop()
  end

  -- Accept
  while true do
    local s = server:accept()
    if not s then break end
    s:settimeout(0)
    pcall(function() s:setoption('tcp-nodelay', true) end)
    local c = { key = s, sock = s, buf = '', out = {}, last = now }
    c.player = relay:connect(function(line) c.out[#c.out + 1] = line .. '\n' end)
    clients[s] = c
  end

  -- Read
  local dead = {}
  for _, c in pairs(clients) do
    while c.sock do
      local line, err, partial = c.sock:receive('*l', c.buf)
      if line then
        c.buf = ''
        c.last = now
        local ok, rerr = pcall(relay.receive, relay, c.player, line)
        if not ok then evt_ch:push('log|relay error: ' .. tostring(rerr)) end
      elseif err == 'timeout' then
        c.buf = partial or ''
        if #c.buf > MAX_LINE then dead[#dead + 1] = c end
        break
      else
        dead[#dead + 1] = c
        break
      end
    end
    if now - c.last > IDLE_TIMEOUT then dead[#dead + 1] = c end
  end
  for _, c in ipairs(dead) do drop(c) end

  -- Write (handles partial sends)
  dead = {}
  for _, c in pairs(clients) do
    if c.sock and #c.out > 0 then
      local data = table.concat(c.out)
      c.out = {}
      local sent, err, last = c.sock:send(data)
      local n = sent or last or 0
      if n < #data then c.out[1] = data:sub(n + 1) end
      if err and err ~= 'timeout' then dead[#dead + 1] = c end
    end
  end
  for _, c in ipairs(dead) do drop(c) end

  socket.sleep(0.005)
end
