-- Steam friends integration via LuaJIT FFI on the steam_api64.dll Balatro already ships
-- (Balatro's bundled luasteam doesn't expose friends lists or invites).
--
-- Connect string format (what Steam passes to an invited friend's game):
--   +mp_join <CODE> steam:<hostSteamID>   (or <host:port> for a dedicated server)

local Steam = { ok = false }
MP.steam = Steam

local ffi_ok, ffi = pcall(require, 'ffi')

local FRIEND_FLAG_IMMEDIATE = 0x04
local PERSONA_STATES = { [0] = 'Offline', 'Online', 'Busy', 'Away', 'Snooze', 'Online', 'Online' }

function Steam.init()
  if Steam.ok or Steam.tried then return Steam.ok end
  if not G.STEAM then return false end -- Steam not initialised yet: try again later
  Steam.tried = true
  if not ffi_ok then return false end
  local ok, err = pcall(function()
    ffi.cdef [[
      typedef struct { uint64_t m_gameID; uint32_t m_unGameIP; uint16_t m_usGamePort; uint16_t m_usQueryPort; uint64_t m_steamIDLobby; } MP_FriendGameInfo_t;
      void* SteamAPI_SteamFriends_v017();
      void* SteamAPI_SteamUser_v022();
      void* SteamAPI_SteamApps_v008();
      void* SteamAPI_SteamUtils_v010();
      int SteamAPI_ISteamFriends_GetFriendCount(void* self, int iFriendFlags);
      uint64_t SteamAPI_ISteamFriends_GetFriendByIndex(void* self, int iFriend, int iFriendFlags);
      const char* SteamAPI_ISteamFriends_GetFriendPersonaName(void* self, uint64_t steamIDFriend);
      int SteamAPI_ISteamFriends_GetFriendPersonaState(void* self, uint64_t steamIDFriend);
      bool SteamAPI_ISteamFriends_GetFriendGamePlayed(void* self, uint64_t steamIDFriend, MP_FriendGameInfo_t* pFriendGameInfo);
      bool SteamAPI_ISteamFriends_InviteUserToGame(void* self, uint64_t steamIDFriend, const char* pchConnectString);
      void SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialogConnectString(void* self, const char* pchConnectString);
      bool SteamAPI_ISteamFriends_SetRichPresence(void* self, const char* pchKey, const char* pchValue);
      void SteamAPI_ISteamFriends_ClearRichPresence(void* self);
      const char* SteamAPI_ISteamFriends_GetFriendRichPresence(void* self, uint64_t steamIDFriend, const char* pchKey);
      void SteamAPI_ISteamFriends_RequestFriendRichPresence(void* self, uint64_t steamIDFriend);
      const char* SteamAPI_ISteamFriends_GetPersonaName(void* self);
      uint64_t SteamAPI_ISteamUser_GetSteamID(void* self);
      int SteamAPI_ISteamApps_GetLaunchCommandLine(void* self, char* pszCommandLine, int cubCommandLine);
      uint32_t SteamAPI_ISteamUtils_GetAppID(void* self);
    ]]
    local lib = ffi.load('steam_api64')
    local friends = lib.SteamAPI_SteamFriends_v017()
    if friends == nil then error('ISteamFriends unavailable') end
    Steam.lib, Steam.friends_if = lib, friends
    Steam.app_mask = ffi.new('uint64_t', 16777216) -- CGameID: low 24 bits are the app id
    Steam.user_if = lib.SteamAPI_SteamUser_v022()
    Steam.apps_if = lib.SteamAPI_SteamApps_v008()
    local utils = lib.SteamAPI_SteamUtils_v010()
    Steam.app_id = utils ~= nil and tonumber(lib.SteamAPI_ISteamUtils_GetAppID(utils)) or 2379780
  end)
  if not ok then print('[BalatroMultiplayer] Steam friends unavailable: ' .. tostring(err)) end
  Steam.ok = ok
  return ok
end

local function id_str(u64) return (tostring(u64):gsub('ULL$', '')) end
local function id_num(s)
  local n = ffi.new('uint64_t', 0)
  for d in tostring(s):gmatch('%d') do n = n * 10 + (d:byte() - 48) end
  return n
end

function Steam.my_id()
  if not Steam.init() or Steam.user_if == nil then return nil end
  return id_str(Steam.lib.SteamAPI_ISteamUser_GetSteamID(Steam.user_if))
end

function Steam.my_name()
  if not Steam.init() then return nil end
  local p = Steam.lib.SteamAPI_ISteamFriends_GetPersonaName(Steam.friends_if)
  return p ~= nil and ffi.string(p) or nil
end

local function rich(id, key)
  local p = Steam.lib.SteamAPI_ISteamFriends_GetFriendRichPresence(Steam.friends_if, id, key)
  local s = p ~= nil and ffi.string(p) or ''
  return s ~= '' and s or nil
end

-- Parses "CODE|mode|host:port" from a friend's mp_lobby rich presence.
local function parse_lobby(s)
  if not s then return nil end
  local code, mode, server = s:match('^(%w+)|(%w+)|(.+)$')
  if code then return { code = code, mode = mode, server = server } end
end

-- Friends list, sorted: in Balatro with an open lobby, in Balatro, online, (offline omitted).
function Steam.friends()
  if not Steam.init() then return {} end
  local lib, f = Steam.lib, Steam.friends_if
  local out = {}
  local info = ffi.new('MP_FriendGameInfo_t')
  local n = lib.SteamAPI_ISteamFriends_GetFriendCount(f, FRIEND_FLAG_IMMEDIATE)
  for i = 0, n - 1 do
    local id = lib.SteamAPI_ISteamFriends_GetFriendByIndex(f, i, FRIEND_FLAG_IMMEDIATE)
    local state = lib.SteamAPI_ISteamFriends_GetFriendPersonaState(f, id)
    if state ~= 0 then
      local in_game = lib.SteamAPI_ISteamFriends_GetFriendGamePlayed(f, id, info)
      local in_balatro = in_game and tonumber(info.m_gameID % Steam.app_mask) == Steam.app_id
      local lobby = in_balatro and parse_lobby(rich(id, 'mp_lobby')) or nil
      local invites = in_balatro and rich(id, 'mp_invite') or nil
      local me = Steam.my_id()
      local name_p = lib.SteamAPI_ISteamFriends_GetFriendPersonaName(f, id)
      out[#out + 1] = {
        id = id_str(id),
        name = name_p ~= nil and ffi.string(name_p) or '?',
        status = in_balatro and (lobby and 'In a lobby' or 'Playing Balatro') or (in_game and 'In another game' or PERSONA_STATES[state] or 'Online'),
        in_balatro = in_balatro,
        lobby = lobby,
        -- They invited us: their 'mp_invite' rich presence lists the Steam IDs they invited.
        invited_me = lobby and invites and me and (',' .. invites .. ','):find(',' .. me .. ',', 1, true) ~= nil or false,
      }
    end
  end
  table.sort(out, function(a, b)
    local ra = (a.lobby and 0) or (a.in_balatro and 1) or 2
    local rb = (b.lobby and 0) or (b.in_balatro and 1) or 2
    if ra ~= rb then return ra < rb end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

-- Ask Steam to fetch rich presence for friends in Balatro (cached by Steam a moment later).
function Steam.request_presence()
  if not Steam.init() then return end
  local lib, f = Steam.lib, Steam.friends_if
  local info = ffi.new('MP_FriendGameInfo_t')
  local n = lib.SteamAPI_ISteamFriends_GetFriendCount(f, FRIEND_FLAG_IMMEDIATE)
  for i = 0, n - 1 do
    local id = lib.SteamAPI_ISteamFriends_GetFriendByIndex(f, i, FRIEND_FLAG_IMMEDIATE)
    if lib.SteamAPI_ISteamFriends_GetFriendGamePlayed(f, id, info) and tonumber(info.m_gameID % Steam.app_mask) == Steam.app_id then
      lib.SteamAPI_ISteamFriends_RequestFriendRichPresence(f, id)
    end
  end
end

function Steam.connect_string(code, server)
  return '+mp_join ' .. tostring(code) .. ' ' .. tostring(server)
end

function Steam.invite(friend_id, connect)
  if not Steam.init() then return false end
  return Steam.lib.SteamAPI_ISteamFriends_InviteUserToGame(Steam.friends_if, id_num(friend_id), connect)
end

function Steam.open_invite_dialog(connect)
  if not Steam.init() then return false end
  Steam.lib.SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialogConnectString(Steam.friends_if, connect)
  return true
end

-- Rich presence: lets friends see/join our open lobby, and carries our invites
-- ('mp_invite' = comma-separated Steam IDs) so a friend's running game can pop them up.
function Steam.set_lobby_presence(lobby, server, invited_ids)
  if not Steam.init() then return end
  local lib, f = Steam.lib, Steam.friends_if
  local mode = lobby and (lobby.mode == 'duel' and 'Duel' or 'Co-op') or nil
  local invites = ''
  if lobby and not lobby.started and server and invited_ids then
    for _, id in ipairs(invited_ids) do
      if #invites + #id + 1 > 250 then break end
      invites = invites == '' and id or (invites .. ',' .. id)
    end
  end
  lib.SteamAPI_ISteamFriends_SetRichPresence(f, 'mp_invite', invites)
  if lobby and not lobby.started and server then
    lib.SteamAPI_ISteamFriends_SetRichPresence(f, 'mp_lobby', lobby.code .. '|' .. lobby.mode .. '|' .. server)
    lib.SteamAPI_ISteamFriends_SetRichPresence(f, 'connect', Steam.connect_string(lobby.code, server))
    lib.SteamAPI_ISteamFriends_SetRichPresence(f, 'status', 'Hosting a multiplayer ' .. mode .. ' lobby')
  else
    lib.SteamAPI_ISteamFriends_SetRichPresence(f, 'mp_lobby', '')
    lib.SteamAPI_ISteamFriends_SetRichPresence(f, 'connect', '')
    lib.SteamAPI_ISteamFriends_SetRichPresence(f, 'status', lobby and ('In a multiplayer ' .. mode) or '')
  end
end

-- ---------------------------------------------------------------------------
-- Peer-to-peer packets through Steam (ISteamNetworking). Steam connects the two
-- PCs directly when it can and relays through Valve's servers when it can't, so
-- hosting needs no port forwarding, tunnel or website.

local P2P_CHANNEL = 21     -- our own channel, away from anything else using P2P
local P2P_RELIABLE = 2     -- k_EP2PSendReliable (ordered, up to 1 MB per packet)

function Steam.p2p_init()
  if Steam.net_if ~= nil and Steam.net_if then return true end
  if Steam.p2p_tried or not Steam.init() then return false end
  Steam.p2p_tried = true
  local ok, err = pcall(function()
    ffi.cdef [[
      void* SteamAPI_SteamNetworking_v006();
      bool SteamAPI_ISteamNetworking_SendP2PPacket(void* self, uint64_t steamIDRemote, const void* pubData, uint32_t cubData, int eP2PSendType, int nChannel);
      bool SteamAPI_ISteamNetworking_IsP2PPacketAvailable(void* self, uint32_t* pcubMsgSize, int nChannel);
      bool SteamAPI_ISteamNetworking_ReadP2PPacket(void* self, void* pubDest, uint32_t cubDest, uint32_t* pcubMsgSize, uint64_t* psteamIDRemote, int nChannel);
      bool SteamAPI_ISteamNetworking_AcceptP2PSessionWithUser(void* self, uint64_t steamIDRemote);
      bool SteamAPI_ISteamNetworking_CloseP2PSessionWithUser(void* self, uint64_t steamIDRemote);
      bool SteamAPI_ISteamNetworking_AllowP2PPacketRelay(void* self, bool bAllow);
    ]]
    local n = Steam.lib.SteamAPI_SteamNetworking_v006()
    if n == nil then error('ISteamNetworking unavailable') end
    Steam.lib.SteamAPI_ISteamNetworking_AllowP2PPacketRelay(n, true)
    Steam.net_if = n
    Steam.p2p_size = ffi.new('uint32_t[1]')
    Steam.p2p_from = ffi.new('uint64_t[1]')
    Steam.p2p_cap = 64 * 1024
    Steam.p2p_buf = ffi.new('uint8_t[?]', Steam.p2p_cap)
  end)
  if not ok then
    Steam.net_if = false
    print('[BalatroMultiplayer] Steam networking unavailable: ' .. tostring(err))
  end
  return ok
end

function Steam.p2p_ok() return Steam.p2p_init() end

function Steam.p2p_send(id, data)
  if not Steam.p2p_init() then return false end
  return Steam.lib.SteamAPI_ISteamNetworking_SendP2PPacket(Steam.net_if, id_num(id), data, #data, P2P_RELIABLE, P2P_CHANNEL)
end

-- Let `id` open a session with us (harmless if they never do).
function Steam.p2p_accept(id)
  if not Steam.p2p_init() then return end
  Steam.lib.SteamAPI_ISteamNetworking_AcceptP2PSessionWithUser(Steam.net_if, id_num(id))
end

function Steam.p2p_close(id)
  if not Steam.p2p_init() then return end
  Steam.lib.SteamAPI_ISteamNetworking_CloseP2PSessionWithUser(Steam.net_if, id_num(id))
end

-- Returns every waiting packet as { from = steamid string, data = string }.
function Steam.p2p_read()
  local out = {}
  if not Steam.p2p_init() then return out end
  local lib, n, size, from = Steam.lib, Steam.net_if, Steam.p2p_size, Steam.p2p_from
  for _ = 1, 256 do
    if not lib.SteamAPI_ISteamNetworking_IsP2PPacketAvailable(n, size, P2P_CHANNEL) then break end
    local want = tonumber(size[0])
    if want > Steam.p2p_cap then
      Steam.p2p_cap = want
      Steam.p2p_buf = ffi.new('uint8_t[?]', want)
    end
    if not lib.SteamAPI_ISteamNetworking_ReadP2PPacket(n, Steam.p2p_buf, Steam.p2p_cap, size, from, P2P_CHANNEL) then break end
    out[#out + 1] = { from = id_str(from[0]), data = ffi.string(Steam.p2p_buf, size[0]) }
  end
  return out
end

-- While connecting to a friend's game we advertise their Steam ID, so their game
-- knows to open a P2P session with us (Steam only delivers packets from people
-- you have accepted or already sent to).
function Steam.set_joining(host_id)
  if not Steam.init() then return end
  Steam.lib.SteamAPI_ISteamFriends_SetRichPresence(Steam.friends_if, 'mp_joining', host_id or '')
end

-- Friends playing Balatro: { id, joining_me = bool }.
function Steam.balatro_friends()
  local out = {}
  if not Steam.init() then return out end
  local lib, f = Steam.lib, Steam.friends_if
  local me = Steam.my_id()
  local info = ffi.new('MP_FriendGameInfo_t')
  local n = lib.SteamAPI_ISteamFriends_GetFriendCount(f, FRIEND_FLAG_IMMEDIATE)
  for i = 0, n - 1 do
    local id = lib.SteamAPI_ISteamFriends_GetFriendByIndex(f, i, FRIEND_FLAG_IMMEDIATE)
    if lib.SteamAPI_ISteamFriends_GetFriendGamePlayed(f, id, info) and tonumber(info.m_gameID % Steam.app_mask) == Steam.app_id then
      lib.SteamAPI_ISteamFriends_RequestFriendRichPresence(f, id)
      out[#out + 1] = { id = id_str(id), joining_me = me ~= nil and rich(id, 'mp_joining') == me }
    end
  end
  return out
end

-- "+mp_join CODE host:port" from the process command line (Steam invite accepted while
-- the game was closed) or from steam://run launch parameters.
function Steam.launch_join()
  local parts = {}
  for _, a in ipairs(arg or {}) do parts[#parts + 1] = tostring(a) end
  if Steam.init() and Steam.apps_if ~= nil then
    local buf = ffi.new('char[512]')
    local len = Steam.lib.SteamAPI_ISteamApps_GetLaunchCommandLine(Steam.apps_if, buf, 512)
    if len > 0 then parts[#parts + 1] = ffi.string(buf) end
  end
  local s = table.concat(parts, ' ')
  local code, server = s:match('%+mp_join%s+(%w+)%s*([^%s]*)')
  if code then return { code = code:upper(), server = server ~= '' and server or nil } end
end

return Steam
