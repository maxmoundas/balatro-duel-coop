-- Balatro Multiplayer: Duel (1v1, same seed, points) and Co-op (2-4 players, shared score).
-- Requires Steamodded (which requires Lovely).

MP = MP or {}
MP.VERSION = '0.1.0'
MP.mod = SMODS.current_mod
MP.config = MP.mod.config or {}

-- server_host empty = host games in-game (default); set it to use a dedicated server instead.
-- Read the saved version BEFORE filling defaults (the defaults include the current version).
local saved_version = tonumber(MP.config.config_version) or 1
local defaults = { server_host = '', server_port = '8788', host_port = '8788', player_name = '', auto_connect = true, config_version = 2 }
for k, v in pairs(defaults) do
  if MP.config[k] == nil then MP.config[k] = v end
end
-- v1 defaulted to a local Node server; v2 hosts in-game instead.
if saved_version < 2 then
  local h = tostring(MP.config.server_host or '')
  if h == '127.0.0.1' or h == 'localhost' then MP.config.server_host = '' end
  MP.config.config_version = 2
end
MP.config.server_port = tostring(MP.config.server_port)
MP.config.host_port = tostring(MP.config.host_port)

local function load(path)
  local chunk, err = SMODS.load_file(path)
  if not chunk then error('[BalatroMultiplayer] failed to load ' .. path .. ': ' .. tostring(err)) end
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

if saved_version < 2 then pcall(SMODS.save_mod_config, MP.mod) end -- persist the migration

MP.install_hooks()
MP.UI.install_hooks()
MP.UI.install_picker_hooks()

if MP.config.player_name == '' then
  local name = MP.steam.my_name and select(2, pcall(MP.steam.my_name))
  if type(name) ~= 'string' or name == '' then
    local ok, pname = pcall(function() return G.PROFILES[G.SETTINGS.profile].name end)
    name = (ok and pname and pname ~= '') and pname or ('Player' .. math.random(100, 999))
  end
  MP.config.player_name = name:sub(1, 16)
end
