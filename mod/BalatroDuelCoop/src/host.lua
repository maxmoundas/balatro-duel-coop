-- Hosting from inside the game: runs the relay server on a background thread.
-- Our own game connects to it over loopback; friends reach it through Steam P2P
-- (p2p.lua), so nobody needs Node.js, a router change, a tunnel or a website.

local Host = { state = 'off', error = nil }
MP.host = Host

local function read_mod_file(rel)
  if NFS and MP.mod and MP.mod.path then
    local s = NFS.read(MP.mod.path .. rel)
    if s then return s end
  end
  return love.filesystem.read('Mods/BalatroDuelCoop/' .. rel)
end

function Host.port() return tonumber(MP.config.host_port) or 8788 end
function Host.running() return Host.state == 'running' end

function Host.start()
  if Host.state == 'running' or Host.state == 'starting' then return end
  local relay_src, json_src, server_src = read_mod_file('src/relay.lua'), read_mod_file('src/json.lua'), read_mod_file('src/host_server.lua')
  if not (relay_src and json_src and server_src) then
    Host.state, Host.error = 'error', 'mod files missing - reinstall the mod'
    return
  end
  Host.cmd, Host.evt = love.thread.newChannel(), love.thread.newChannel()
  Host.thread = love.thread.newThread(server_src)
  Host.thread:start(relay_src, json_src, Host.port(), Host.cmd, Host.evt)
  Host.state, Host.error = 'starting', nil
end

function Host.stop()
  if Host.state == 'off' then return end
  if MP.p2p then MP.p2p.host_stopped() end
  if Host.cmd then Host.cmd:push('stop') end
  Host.state = 'off'
end

-- What friends use to reach our lobby: our Steam ID (nil if Steam isn't available).
function Host.public_address()
  return Host.running() and MP.p2p and MP.p2p.available() and MP.p2p.server_string() or nil
end

-- One-line status for menus.
function Host.status_text()
  if Host.state == 'starting' then return 'Starting your game server...' end
  if Host.state == 'error' then return 'Could not start your game server: ' .. tostring(Host.error) end
  if Host.state ~= 'running' then return nil end
  if Host.public_address() then
    local n = 0
    for _ in pairs(MP.p2p.peers) do n = n + 1 end
    return 'Hosting through Steam - friends can join' .. (n > 0 and (' (' .. n .. ' connected)') or '')
  end
  return 'Steam is unavailable - only this PC can join (is Steam running?)'
end

function Host.update(dt)
  if Host.thread then
    local err = Host.thread:getError()
    if err then
      Host.thread = nil
      Host.state, Host.error = 'error', err
      if MP.UI then MP.UI.refresh() end
    end
  end
  if not Host.evt then return end
  local refresh = false
  local e = Host.evt:pop()
  while e do
    local op = e:sub(1, 2)
    if op == 'P|' then
      local id, line = e:match('^P|(%d+)|(.*)$')
      if id then MP.p2p.host_deliver(id, line) end
    elseif op == 'X|' then
      MP.p2p.host_dropped(e:sub(3))
      refresh = true
    elseif e == 'listening' then
      Host.state = 'running'
      if MP.on_host_listening then MP.on_host_listening() end
      refresh = true
    elseif e:sub(1, 6) == 'error|' then
      local msg = e:sub(7)
      if msg:find('in use', 1, true) then msg = 'port ' .. Host.port() .. ' is already in use (close other servers)' end
      Host.state, Host.error = 'error', msg
      if MP.on_host_failed then MP.on_host_failed(msg) end
      refresh = true
    elseif e:sub(1, 4) == 'log|' then
      print('[BalatroDuelCoop host] ' .. e:sub(5))
    elseif e == 'stopped' then
      Host.thread = nil
    end
    e = Host.evt:pop()
  end
  if refresh and MP.UI then MP.UI.refresh() end
end

-- Earlier versions ran a playit.gg agent in the background; stop any that a crash left behind.
function Host.cleanup_legacy()
  local pid = tonumber(love.filesystem.read('mp_playit/playitd.pid') or '')
  if not pid then return end
  love.filesystem.remove('mp_playit/playitd.pid')
  local ok, ffi = pcall(require, 'ffi')
  if not ok or (jit and jit.os ~= 'Windows') then return end
  pcall(function()
    pcall(ffi.cdef, [[
      void* OpenProcess(uint32_t, int, uint32_t);
      int TerminateProcess(void*, unsigned int);
      int CloseHandle(void*);
      int QueryFullProcessImageNameA(void*, uint32_t, char*, uint32_t*);
    ]])
    local C = ffi.C
    local h = C.OpenProcess(0x1000 + 0x0001, 0, pid)
    if h == nil then return end
    local buf, len = ffi.new('char[1024]'), ffi.new('uint32_t[1]', 1024)
    if C.QueryFullProcessImageNameA(h, 0, buf, len) ~= 0 and ffi.string(buf):lower():find('playitd', 1, true) then
      C.TerminateProcess(h, 0)
    end
    C.CloseHandle(h)
  end)
end

return Host
