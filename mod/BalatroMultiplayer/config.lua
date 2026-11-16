return {
  server_host = '',      -- empty: host games in-game (friends join through Steam). Set host + port to use a dedicated server.
  server_port = '8788',
  host_port = '8788',    -- loopback port for the in-game server (your own game and tools/test-bot.js connect here)
  player_name = '',      -- empty: your Steam name
  auto_connect = true,   -- with a dedicated server: connect on startup so invites can pop up in-game
}
