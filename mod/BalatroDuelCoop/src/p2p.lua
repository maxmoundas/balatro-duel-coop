-- Steam P2P transport.
--
-- Packets on our Steam P2P channel start with one type byte:
--   'H'  hello: a joiner asking to connect (sent every second until answered)
--   'W'  welcome: the host is ready for us (also sent ahead of time to invited friends)
--   'M'  one protocol message (JSON) follows
--   'B'  bye: the session is over
--
-- Hosting: every friend who connects gets a virtual connection in the host server
-- thread (host_server.lua); their messages are passed through unchanged.
-- Joining: net.lua uses this instead of TCP when the lobby's server is "steam:<id>".
--
-- Steam only hands us packets from people we've accepted or sent to, and Balatro's
-- Steam layer doesn't surface session requests. So a joiner advertises who they're
-- joining in rich presence ('mp_joining'), and the host opens the session from its
-- side by accepting and greeting them.

local P2P = { peers = {}, greeted = {}, inbox = {}, scan_at = 0 }
MP.p2p = P2P

local Steam = MP.steam

function P2P.available()
  return Steam and Steam.ok and Steam.p2p_ok() or false
end

function P2P.server_string()
  local me = Steam and Steam.my_id and Steam.my_id()
  return me and ('steam:' .. me) or nil
end

-- Host side ---------------------------------------------------------------------

local function hosting() return MP.host and MP.host.running() and MP.host.cmd ~= nil end

-- Open the session from our side so the friend's packets reach us.
function P2P.greet(id)
  if not P2P.available() then return end
  Steam.p2p_accept(id)
  Steam.p2p_send(id, 'W')
  P2P.greeted[id] = love.timer.getTime()
end

local function host_packet(from, kind, body)
  local peer = P2P.peers[from]
  if kind == 'H' or kind == 'M' then
    if not peer then
      peer = { id = from }
      P2P.peers[from] = peer
      MP.host.cmd:push('P|open|' .. from)
      print('[BalatroDuelCoop] Steam player connected: ' .. from)
      if MP.UI then MP.UI.refresh() end
    end
    peer.last = love.timer.getTime()
    if kind == 'H' then Steam.p2p_send(from, 'W')
    elseif body ~= '' then MP.host.cmd:push('P|line|' .. from .. '|' .. body) end
  elseif kind == 'B' and peer then
    P2P.peers[from] = nil
    MP.host.cmd:push('P|close|' .. from)
    Steam.p2p_close(from)
  end
end

-- From host.lua: a line the relay wants delivered to a Steam peer.
function P2P.host_deliver(id, line)
  if P2P.peers[id] then Steam.p2p_send(id, 'M' .. line) end
end

-- From host.lua: the relay dropped this peer (left, idle, ...).
function P2P.host_dropped(id)
  if P2P.peers[id] then
    P2P.peers[id] = nil
    Steam.p2p_send(id, 'B')
  end
end

function P2P.host_stopped()
  for id in pairs(P2P.peers) do
    Steam.p2p_send(id, 'B')
    Steam.p2p_close(id)
  end
  P2P.peers, P2P.greeted = {}, {}
end

-- Every couple of seconds while hosting: greet friends who say they're joining us.
local function host_scan(now)
  if now < P2P.scan_at then return end
  P2P.scan_at = now + 2
  for _, f in ipairs(Steam.balatro_friends()) do
    Steam.p2p_accept(f.id) -- cheap, and lets anyone in Balatro reach us
    if f.joining_me and not P2P.peers[f.id] and now - (P2P.greeted[f.id] or -99) > 3 then
      P2P.greet(f.id)
    end
  end
end

-- Join side -----------------------------------------------------------------------

-- net.lua reads P2P.inbox for packets from the host it's connected to.
P2P.join_host = nil

function P2P.join_send(data)
  if P2P.join_host then return Steam.p2p_send(P2P.join_host, data) end
  return false
end

-- Pump ------------------------------------------------------------------------------

function P2P.update(dt)
  if not P2P.available() then return end
  local now = love.timer.getTime()
  for _, pkt in ipairs(Steam.p2p_read()) do
    local kind, body = pkt.data:sub(1, 1), pkt.data:sub(2)
    if pkt.from == P2P.join_host then
      P2P.inbox[#P2P.inbox + 1] = { kind = kind, body = body }
    elseif hosting() then
      host_packet(pkt.from, kind, body)
    end
  end
  if hosting() then host_scan(now) end
end

return P2P
