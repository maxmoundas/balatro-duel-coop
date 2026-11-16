-- Networking to the server we play on. Two transports:
--   * TCP (our own in-game server on 127.0.0.1, or a dedicated server): a LÖVE thread
--     owns the socket so the game never blocks.
--   * Steam P2P (a friend's in-game server): packets via p2p.lua on the main thread.
-- Main thread <-> worker communicate through two channels using short string commands.
--   to worker:   "C|host|port", "S|<json line>", "D" (disconnect)
--   from worker: "connected", "error|<msg>", "closed", "M|<json line>"

local json = MP.json
local Net = { status = 'disconnected', error = nil, ping_timer = 0, mode = 'tcp' }
local HANDSHAKE_TIMEOUT = 30   -- seconds to wait for a friend's game to answer over Steam
local STEAM_IDLE_TIMEOUT = 45  -- the server answers our 15 s pings, so silence means gone

local THREAD_CODE = [[
local socket = require('socket')
local to_worker, from_worker = ...
local sock, buf = nil, ''

local function close(reason)
  if sock then pcall(function() sock:close() end) end
  sock, buf = nil, ''
  if reason then from_worker:push(reason) end
end

while true do
  local cmd = sock and to_worker:pop() or to_worker:demand(0.5)
  while cmd do
    local op = cmd:sub(1, 1)
    if op == 'C' then
      close()
      local host, port = cmd:match('^C|([^|]+)|(%d+)$')
      local s = socket.tcp()
      s:settimeout(6)
      local ok, err = s:connect(host or '127.0.0.1', tonumber(port) or 8788)
      if ok then
        s:settimeout(0)
        pcall(function() s:setoption('tcp-nodelay', true) end)
        sock = s
        from_worker:push('connected')
      else
        pcall(function() s:close() end)
        from_worker:push('error|' .. tostring(err))
      end
    elseif op == 'S' and sock then
      local data = cmd:sub(3) .. '\n'
      sock:settimeout(3)
      local ok, err = sock:send(data)
      sock:settimeout(0)
      if not ok then close('closed') end
    elseif op == 'D' then
      close()
    end
    cmd = to_worker:pop()
  end

  if sock then
    while true do
      local line, err, partial = sock:receive('*l', buf)
      if line then
        buf = ''
        from_worker:push('M|' .. line)
      elseif err == 'timeout' then
        buf = partial or ''
        break
      else
        close('closed')
        break
      end
    end
    socket.sleep(0.01)
  end
end
]]

function Net.init()
  if Net.thread then return end
  Net.to_worker = love.thread.newChannel()
  Net.from_worker = love.thread.newChannel()
  Net.thread = love.thread.newThread(THREAD_CODE)
  Net.thread:start(Net.to_worker, Net.from_worker)
end

function Net.connect(host, port)
  Net.disconnect()
  Net.init()
  Net.mode = 'tcp'
  Net.status = 'connecting'
  Net.error = nil
  Net.to_worker:push('C|' .. tostring(host) .. '|' .. tostring(port))
end

-- Connect to a friend's in-game server through Steam.
function Net.connect_steam(host_id)
  Net.disconnect()
  local P2P = MP.p2p
  if not (P2P and P2P.available()) then
    Net.status, Net.error = 'disconnected', 'Steam networking is unavailable (is Steam running?)'
    Net.pending_status = true
    return
  end
  Net.mode = 'steam'
  Net.status, Net.error = 'connecting', nil
  Net.steam_host = host_id
  Net.hello_timer, Net.waited, Net.last_recv = 0, 0, 0
  P2P.inbox = {}
  P2P.join_host = host_id
  MP.steam.p2p_accept(host_id)
  pcall(MP.steam.set_joining, host_id) -- tells their game to open the session with us
  P2P.join_send('H')
end

function Net.disconnect()
  if Net.mode == 'steam' then
    if Net.steam_host and MP.p2p then
      if Net.status ~= 'disconnected' then MP.p2p.join_send('B') end
      MP.steam.p2p_close(Net.steam_host)
      MP.p2p.join_host = nil
      pcall(MP.steam.set_joining, nil)
    end
    Net.steam_host = nil
    Net.mode = 'tcp'
  elseif Net.to_worker then
    Net.to_worker:push('D')
  end
  Net.status = 'disconnected'
end

function Net.send(msg)
  if Net.status ~= 'connected' then return false end
  if Net.mode == 'steam' then return MP.p2p.join_send('M' .. json.encode(msg)) end
  Net.to_worker:push('S|' .. json.encode(msg))
  return true
end

local function steam_lost(reason, on_status)
  local host = Net.steam_host
  Net.disconnect()
  Net.error = reason
  if on_status then on_status(Net.status) end
  return host
end

local function poll_steam(dt, on_message, on_status)
  local P2P = MP.p2p
  local inbox = P2P.inbox
  P2P.inbox = {}
  for _, pkt in ipairs(inbox) do
    if Net.mode ~= 'steam' then return end
    Net.last_recv = 0
    if pkt.kind == 'W' and Net.status == 'connecting' then
      Net.status = 'connected'
      Net.ping_timer = 0
      pcall(MP.steam.set_joining, nil)
      if on_status then on_status(Net.status) end
    elseif pkt.kind == 'M' and Net.status == 'connected' then
      local msg = json.decode(pkt.body)
      if type(msg) == 'table' and msg.type then on_message(msg) end
    elseif pkt.kind == 'B' then
      return steam_lost('the host closed the lobby', on_status)
    end
  end
  if Net.status == 'connecting' then
    Net.waited = Net.waited + dt
    Net.hello_timer = Net.hello_timer + dt
    if Net.hello_timer >= 1 then
      Net.hello_timer = 0
      P2P.join_send('H')
    end
    if Net.waited > HANDSHAKE_TIMEOUT then
      steam_lost("their game didn't answer through Steam - are you Steam friends, and is their lobby still open?", on_status)
    end
  elseif Net.status == 'connected' then
    Net.last_recv = Net.last_recv + dt
    if Net.last_recv > STEAM_IDLE_TIMEOUT then
      steam_lost('lost contact with the host', on_status)
    end
  end
end

-- Called every frame; dispatches incoming messages to `on_message`.
function Net.poll(dt, on_message, on_status)
  if Net.pending_status then
    Net.pending_status = nil
    if on_status then on_status(Net.status) end
  end
  if Net.mode == 'steam' then
    poll_steam(dt, on_message, on_status)
  elseif Net.thread then
    Net.poll_tcp(on_message, on_status)
  end
  if Net.status == 'connected' then
    Net.ping_timer = Net.ping_timer + dt
    if Net.ping_timer > 15 then
      Net.ping_timer = 0
      Net.send({ type = 'ping' })
    end
  end
end

function Net.poll_tcp(on_message, on_status)
  local err = Net.thread:getError()
  if err then
    Net.status, Net.error = 'disconnected', 'network thread crashed: ' .. err
    Net.thread = nil
    if on_status then on_status(Net.status) end
    return
  end
  local item = Net.from_worker:pop()
  while item do
    if item:sub(1, 2) == 'M|' then
      local msg = json.decode(item:sub(3))
      if type(msg) == 'table' and msg.type then on_message(msg) end
    elseif item == 'connected' then
      Net.status = 'connected'
      Net.ping_timer = 0
      if on_status then on_status(Net.status) end
    elseif item == 'closed' then
      Net.status = 'disconnected'
      Net.error = 'connection closed'
      if on_status then on_status(Net.status) end
    elseif item:sub(1, 6) == 'error|' then
      Net.status = 'disconnected'
      Net.error = item:sub(7)
      if on_status then on_status(Net.status) end
    end
    item = Net.from_worker:pop()
  end
end

return Net
