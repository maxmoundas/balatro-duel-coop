'use strict';

// Runs the mod's relay.lua (the single source of truth for multiplayer rules) inside Node
// via fengari, so the standalone server and the in-game host server behave identically.

const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const LUA_DIR = process.env.RELAY_LUA_DIR || path.join(__dirname, '..', '..', 'mod', 'BalatroDuelCoop', 'src');

const GLUE = `
local json = load_module('json')
local Relay = load_module('relay')
math.randomseed(SEED)
local relay = Relay.new({ json = json, min_players = MIN_PLAYERS, log = js_log })
local conns = {}
function on_connect(cid)
  conns[cid] = relay:connect(function(line) js_send(cid, line) end)
end
function on_line(cid, line)
  local p = conns[cid]
  if p then relay:receive(p, line) end
end
function on_close(cid)
  local p = conns[cid]
  conns[cid] = nil
  if p then relay:disconnect(p) end
end
function lobby_count()
  local n = 0
  for _ in pairs(relay.lobbies) do n = n + 1 end
  return n
end
`;

class RelayHost {
  constructor({ minPlayers = 2, log = () => {}, onSend }) {
    this.onSend = onSend;
    const L = this.L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);

    const sources = {};
    for (const name of ['json', 'relay']) sources[name] = fs.readFileSync(path.join(LUA_DIR, `${name}.lua`), 'utf8');

    lua.lua_pushjsfunction(L, (L) => {
      const name = lua.lua_tojsstring(L, 1);
      if (lauxlib.luaL_loadbuffer(L, to_luastring(sources[name]), null, to_luastring(`@${name}.lua`)) !== lua.LUA_OK) {
        return lua.lua_error(L);
      }
      lua.lua_call(L, 0, 1);
      return 1;
    });
    lua.lua_setglobal(L, to_luastring('load_module'));

    lua.lua_pushjsfunction(L, (L) => {
      const cid = lua.lua_tointeger(L, 1);
      const line = lua.lua_tojsstring(L, 2);
      this.onSend(cid, line);
      return 0;
    });
    lua.lua_setglobal(L, to_luastring('js_send'));

    lua.lua_pushjsfunction(L, (L) => { log(lua.lua_tojsstring(L, 1)); return 0; });
    lua.lua_setglobal(L, to_luastring('js_log'));

    lua.lua_pushinteger(L, minPlayers);
    lua.lua_setglobal(L, to_luastring('MIN_PLAYERS'));
    lua.lua_pushinteger(L, Math.floor(Math.random() * 2 ** 31));
    lua.lua_setglobal(L, to_luastring('SEED'));

    if (lauxlib.luaL_dostring(L, to_luastring(GLUE)) !== lua.LUA_OK) {
      throw new Error('relay.lua failed to load: ' + lua.lua_tojsstring(L, -1));
    }
  }

  call(fn, ...args) {
    const L = this.L;
    lua.lua_getglobal(L, to_luastring(fn));
    for (const a of args) {
      if (typeof a === 'number') lua.lua_pushinteger(L, a);
      else lua.lua_pushstring(L, to_luastring(String(a)));
    }
    if (lua.lua_pcall(L, args.length, 1, 0) !== lua.LUA_OK) {
      const err = lua.lua_tojsstring(L, -1);
      lua.lua_pop(L, 1);
      throw new Error(err);
    }
    const ret = lua.lua_isnumber(L, -1) ? lua.lua_tonumber(L, -1) : null;
    lua.lua_pop(L, 1);
    return ret;
  }

  connect(cid) { this.call('on_connect', cid); }
  line(cid, line) { this.call('on_line', cid, line); }
  close(cid) { this.call('on_close', cid); }
  lobbyCount() { return this.call('lobby_count'); }
}

module.exports = { RelayHost, LUA_DIR };
