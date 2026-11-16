# Testing with a second PC and Steam account

This tests the real thing: two copies of Balatro on two Windows PCs, signed in to two Steam
accounts, connected through Steam. Below, **PC A** is your main PC (account A) and **PC B** is the
second laptop (account B).

## What each account needs

- **Its own copy of Balatro.** Steam Family Sharing doesn't let two accounts play the same copy
  at the same time.
- **Steam friends with the other account.** Only the host's Steam friends can join a lobby hosted
  in-game. Add each other under Steam → Friends → Add a Friend, and accept the request on the other
  account.
- **Online status, not Invisible or Offline.** Lobbies, invites and joining all go through Steam's
  friend status, and an invisible player looks offline to the other game.

## One-time setup on PC B (the laptop)

1. Install Steam, sign in with **account B** and install Balatro.
2. **Launch Balatro once,** let it reach the main menu, then quit. This creates its save folder.
3. On PC A, build the latest package (from the repo root, in PowerShell):
   ```powershell
   .\tools\build-friend-package.ps1
   ```
   Copy `dist\BalatroMultiplayer-Setup.zip` to PC B, by USB stick, cloud drive or email.
4. On PC B, **unzip** the whole file (right-click → Extract All), close Balatro, and double-click
   **Install.bat**.
   - If Windows SmartScreen warns you, click **More info → Run anyway**.
   - The installer finds the game through Steam and installs Lovely and Steamodded (the mod
     loaders), then this mod.
   - If the game is under `Program Files` and the installer can't write there, right-click
     `Install.bat` → **Run as administrator**.
5. Launch Balatro from Steam on PC B. Check that **MULTIPLAYER** is on the main menu, under PLAY.
   Your multiplayer name defaults to your Steam name. Change it under MULTIPLAYER → **Advanced**
   if both accounts have similar names.

**Keep both PCs on the same version.** After any change to the mod, rebuild the zip and run
`Install.bat` on PC B again. On PC A, run `.\install-mod.ps1`.

## Test checklist

Start with both PCs at the Balatro main menu.

### 1. Invite and join (game already open)
1. **PC A:** MULTIPLAYER → **Duel** → choose deck and stake → **Play**.
   - Expect a short "Setting up your lobby…" screen, then the lobby.
2. **PC A:** **Invite Steam Friends** → **Invite** next to account B.
3. **PC B:** within a few seconds a gold "… invited you to a Duel!" banner appears in the
   MULTIPLAYER menu, or a toast if the menu is closed. Click **Join**.
   - The lobby should also be listed under **Friends' lobbies** on PC B.
4. Both lobbies should list 2/2 players.

### 2. Play a duel
1. **PC A:** **Start Game**. Both PCs start the same run: same seed, deck and stake.
2. Play a few blinds:
   - **Free play:** play several hands quickly on one PC while the other does nothing. Nothing
     should hold you up mid-blind.
   - **Shop gate:** beat the blind on one PC and click **Cash Out**. It should show "Waiting for
     <their Steam name>" until the other PC finishes the blind, then open the shop.
   - **Next-blind gate:** leave the shop on one PC and select the next blind. It should wait
     until the other PC also selects (or skips) that blind.
   - **Points:** after both finish a blind, both PCs show the points for the round.
   - **Names:** the lobby, status bar and viewer show each player's Steam name, not "P1".
   - **Player viewer:** press **Tab** (or click the status bar). Check every tab: **Compare**,
     **Their cards** (jokers, consumables, vouchers, hand, tags), **Deck** (all their cards with
     enhancements/seals/editions; **Show mine** switches to yours), **Poker hands** (levels side
     by side) and **History**. Hover cards to read them.
   - Skip a blind on one PC to check skipping.
3. **Ending:** lose on purpose on one PC, by playing junk hands. The other player should win once
   they get past that blind.

### 3. Co-op
1. **PC B hosts this time:** MULTIPLAYER → **Co-op** → Play, then invite account A.
2. Start the game. Check that:
   - each blind's requirement is twice the normal amount
   - each player's hands add to the shared chip count on both PCs
   - running out of hands on one PC makes it wait while the other keeps playing

### 4. Invite while the friend's game is closed
1. **PC B:** quit Balatro.
2. **PC A:** host a lobby, then **Invite Steam Friends** → invite account B.
3. **PC B:** accept the invite in Steam chat (or click **Join Game** on account A in the friends
   list). Balatro should launch and join the lobby on its own.

### 5. Disconnects
- During a duel, quit Balatro on the joining PC. The host should win ("opponent left").
- During a game, quit on the **host** PC. The other PC should show "Disconnected" and its gates
  should release.
- Click **Leave Lobby** in a lobby that hasn't started. The other side's player list should update.

### 6. Different networks
Repeat test 1 with PC B on a phone hotspot instead of your home Wi-Fi. When the PCs can't reach
each other directly, Steam passes the traffic through its own relay servers, and this checks that
path.

## If something goes wrong

- **"Their game didn't answer through Steam" after about 30 s:** check that the accounts are Steam
  friends, both show as Online in Steam, and the host's lobby is still open. Then try again.
  Accepting a direct **Invite** is the fastest way to connect.
- **The invite never shows up on PC B:** open PC B's MULTIPLAYER menu, since invites are checked
  every 5 seconds there. Make sure PC B's account isn't set to Invisible.
- **Logs:** each PC writes a log to `%APPDATA%\Balatro\Mods\lovely\log\` (newest file). Search for
  `BalatroMultiplayer`. Lines like `Steam player connected: <id>` (on the host) or
  `Steam networking unavailable` show what happened. Send me the newest log from **both** PCs
  along with a short description and screenshots.
- **The MULTIPLAYER button is missing on PC B:** re-run `Install.bat`. If Balatro shows a
  Steamodded or Lovely error at startup, take a screenshot of it.
