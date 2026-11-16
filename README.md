# Balatro Multiplayer — Duel & Co-op

A Balatro mod (Steamodded). Any player can host from inside the game, and Steam friends join
through Steam itself: no server, port forwarding, tunnel or website. Each player runs their own
copy of Balatro, so everything plays exactly like the real game.

## Modes

### Duel (1v1)
- Both players get the **same seed, deck and stake**.
- **Hands are played in lockstep.** Neither player can play hand *N* of a blind until the other is
  also ready to play hand *N*, or has already finished that blind. Discards, shopping and other
  actions are not gated.
- After each blind both players have finished, points are awarded:
  - **+1** to whoever scored the single highest hand in that blind
  - **+1** to whoever beat the blind in the fewest hands (only players who beat it qualify)
  - If both tie on either category, both get the point.
- How a duel is decided:
  1. Both players beat the Ante 8 boss → most points wins.
  2. One player's run ends before the other's → the survivor wins. The survivor only has to get
     through the blind the other player lost on.
  3. Both runs end on the same blind → most points wins.
  4. A player who disconnects or returns to the main menu forfeits.
- Skipping blinds is allowed. A skipped blind gives the skipper no points for it.

### Co-op (2–4 players)
- Every player plays their own run (same seed). Only the **score** is shared. Decks, money,
  jokers and shops are each player's own.
- Each blind's requirement is multiplied by the number of players. At 3 players, a 300-chip
  blind needs 900.
- Teammates' scored hands are added to your chip counter as they happen. The blind is beaten
  when the team total reaches the requirement, and everyone moves on together.
- Running out of hands doesn't lose the blind right away. You wait while teammates keep
  playing. The team only fails if **everyone** runs out of hands below the target.
- All players have to select the blind before it starts. Skipping is disabled.
- The team wins when everyone beats the Ante 8 boss. Any player's run ending ends it for the team.

## Setup (players)

1. Install **Lovely**: download `lovely-x86_64-pc-windows-msvc.zip` from
   https://github.com/ethangreen-dev/lovely-injector/releases and put `winmm.dll` (older releases: `version.dll`) in the Balatro
   game folder (Steam → Balatro → Manage → Browse local files).
2. Install **Steamodded**: download the latest release from
   https://github.com/Steamodded/smods/releases and extract it into `%APPDATA%\Balatro\Mods\`.
   You should end up with `Mods\smods-*\`.
3. Install this mod: run `.\install-mod.ps1`, or copy `mod\BalatroMultiplayer` into
   `%APPDATA%\Balatro\Mods\`.
4. Launch Balatro. A **MULTIPLAYER** button appears next to Play on the main menu. If it doesn't,
   press **F8** on the main menu.

In game: **F7** toggles the multiplayer status bar. **Tab** (or clicking the status bar) opens
the player viewer.

## Hosting a game (any player, nothing extra to install)

Pick **Duel** or **Co-op** in the Multiplayer menu, choose a deck and stake, and press Play.
The mod then:
1. Starts a game server inside Balatro, on a background thread. It only listens on
   `127.0.0.1:8788`, so there's no firewall prompt.
2. Lets Steam friends connect to it through **Steam's peer-to-peer networking**
   (`ISteamNetworking`, part of the `steam_api64.dll` Balatro already ships). Steam connects the
   two PCs directly when it can and relays through Valve's servers when it can't, so it works
   behind any router, including mobile hotspots and shared (CGNAT) connections.

The game stays hosted until you click **Stop hosting** or close Balatro. If the host quits
mid-game, everyone is disconnected.

Only the host's **Steam friends** can join an in-game hosted lobby: friends are how the host's
game discovers who is connecting. **Advanced** (in the Multiplayer menu) lets you change your
name or use a dedicated server instead (see below), which anyone can join.

## Joining and inviting

- **Invite Steam Friends** (in your lobby): use the Steam overlay's invite dialog, or click
  **Invite** next to a friend. Friends playing Balatro are listed first.
  - **Their game is closed:** a Steam invite. Accepting it launches Balatro and joins you.
  - **Their game is open:** an invite pops up in their Multiplayer menu (it's passed through Steam
    rich presence, so no shared server is needed).
- **Friends' lobbies:** open lobbies of friends playing Balatro appear in your Multiplayer menu
  as one-click Join buttons.
- **Invite code:** the host clicks **Copy invite code** (`CODE@steam:<id>`) and sends it to you,
  e.g. on Discord. You click **Paste** and then **Join**. This also needs you to be Steam friends.

The mod reads your Steam friends list through Steam's own API (`steam_api64.dll`, already part
of Balatro). Your Steam ID is sent only to the server of a lobby you're in, so invites can be
delivered. While you're connecting to a friend's game, your rich presence briefly carries their
Steam ID (`mp_joining`) so their game knows to accept your connection.

## Installer for friends

```powershell
.\tools\build-friend-package.ps1
```

This builds `dist\BalatroMultiplayer-Setup.zip`. Friends unzip it and double-click `Install.bat`.
It finds Balatro through Steam's library list and installs Lovely v0.10.0 and Steamodded
26.1002.0 (the tested versions), skipping either one if it's already installed. Then it installs
the mod. Every player needs Balatro on Steam (PC).

## Dedicated server (optional)

Running a separate server isn't needed, but you can, for example to keep one always online.
The Node server runs the same rules file as the game (`mod/BalatroMultiplayer/src/relay.lua`,
through the fengari Lua VM):

```sh
cd server
npm install
npm start          # listens on 0.0.0.0:8788  (or double-click start-server.bat)
npm test           # 25 tests of the rules + TCP, run against relay.lua
```

`PORT`/`HOST` override the defaults; `MIN_PLAYERS=1` allows solo lobbies for testing. To deploy
on Fly.io, run `fly deploy --config server/fly.toml` from the repo root. Players then enter the
server under **Advanced**, or you can build it into the friend package with
`build-friend-package.ps1 -Server host:port`.

## How it works

| Piece | File |
|---|---|
| Rules: lobbies, gates, points, win conditions, invites | `mod/BalatroMultiplayer/src/relay.lua` |
| In-game server (LÖVE thread + luasocket) | `mod/BalatroMultiplayer/src/host_server.lua`, `host.lua` |
| Steam P2P transport (host bridge + joining) | `mod/BalatroMultiplayer/src/p2p.lua` |
| Client connection (TCP thread or Steam P2P) | `mod/BalatroMultiplayer/src/net.lua` |
| Steam friends, invites, rich presence (FFI) | `mod/BalatroMultiplayer/src/steam.lua` |
| Game hooks, run state, message handling | `mod/BalatroMultiplayer/src/game.lua` |
| Menus + HUD / player viewer | `mod/BalatroMultiplayer/src/ui.lua`, `viewer.lua` |
| Standalone server (runs relay.lua via fengari) | `server/src/server.js`, `relay-host.js` |

The mod hooks these vanilla functions: `G.FUNCS.select_blind`, `G.FUNCS.skip_blind`,
`G.FUNCS.play_cards_from_highlighted` (duel hand gate), `G.FUNCS.evaluate_play` (hand score),
`Blind:set_blind` (co-op scaling), `end_round` (blind results / co-op wait),
`Game:update_game_over`, `win_game`, `save_run` (multiplayer runs aren't saved) and
`G.FUNCS.go_to_menu` (forfeit).

## Known limitations (v0.1)
- Not fully tested in-game yet. The rules (relay.lua) are covered by 25 tests, the Steam calls
  were checked against a real account, and the Lua is syntax-checked.
- Joining an in-game hosted lobby needs you to be Steam friends with the host.
- A multiplayer run can't be resumed after Balatro is closed.
- In Co-op, the blind-select screen shows the unscaled requirement. The scaled number appears
  once the blind starts.
- Some other mods that change scoring (e.g. Talisman's big numbers) aren't supported yet.

## Testing

- **With a second PC and Steam account:** see [TESTING.md](TESTING.md) for setup and a
  step-by-step test checklist.
- **Alone:** `node tools/test-bot.js CODE` adds a stand-in second player to your lobby. It
  connects to your in-game server on this PC and shadows your blinds, hands and scores. It tests
  the game rules and menus, not the Steam connection.
