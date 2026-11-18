-- Balatro Duel & Co-op: Duel (1v1, same seed, points) and Co-op (2-4 players, shared score).
-- Requires Steamodded (which requires Lovely).

MP = MP or {}
MP.VERSION = '1.0.0'
MP.PROTOCOL = 4 -- must match Relay.PROTOCOL_VERSION in src/relay.lua
MP.mod = SMODS.current_mod
MP.config = MP.mod.config or {}

-- server_host empty = host games in-game (default); set it to use a dedicated server instead.
-- Read the saved version BEFORE filling defaults (the defaults include the current version).
local saved_version = tonumber(MP.config.config_version) or 1
local defaults = { server_host = '', server_port = '8788', host_port = '8788', player_name = '', auto_connect = true, config_version = 3 }
for k, v in pairs(defaults) do
  if MP.config[k] == nil then MP.config[k] = v end
end
-- v1 defaulted to a local Node server; v2 hosts in-game instead.
if saved_version < 2 then
  local h = tostring(MP.config.server_host or '')
  if h == '127.0.0.1' or h == 'localhost' then MP.config.server_host = '' end
end
-- v2 could save the Balatro profile name ("P1", "P2", ...) when Steam wasn't ready yet.
-- An empty name means "use my Steam name", resolved when connecting.
if saved_version < 3 then
  if tostring(MP.config.player_name or ''):match('^P%d+$') then MP.config.player_name = '' end
  MP.config.config_version = 3
end
MP.config.server_port = tostring(MP.config.server_port)
MP.config.host_port = tostring(MP.config.host_port)

local function load(path)
  local chunk, err = SMODS.load_file(path)
  if not chunk then error('[BalatroDuelCoop] failed to load ' .. path .. ': ' .. tostring(err)) end
  return chunk()
end

MP.json = load('src/json.lua')
MP.net = load('src/net.lua')
load('src/steam.lua')
load('src/ui.lua')
load('src/game.lua')
load('src/viewer.lua')
load('src/host.lua')
load('src/p2p.lua')

if saved_version < 3 then pcall(SMODS.save_mod_config, MP.mod) end -- persist the migration

MP.install_hooks()
MP.UI.install_hooks()
MP.UI.install_picker_hooks()

-- The name other players see: a custom name from Advanced, otherwise the Steam name.
-- Resolved on demand because Steam may not be ready yet when the mod loads.
function MP.display_name()
  local custom = tostring(MP.config.player_name or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if custom ~= '' then return custom:sub(1, 20) end
  local ok, name = pcall(function() return MP.steam.my_name() end)
  if ok and type(name) == 'string' and name ~= '' then return name:sub(1, 20) end
  MP.fallback_name = MP.fallback_name or ('Player' .. math.random(100, 999))
  return MP.fallback_name
end
