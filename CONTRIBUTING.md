# Feedback and contributing

Feedback of any kind is welcome: bug reports, feature requests, rule ideas, or just how a game
went.

## Giving feedback

- **On GitHub:** [open an issue](https://github.com/maxmoundas/balatro-duel-coop/issues/new/choose)
  and pick **Bug report** or **Feedback or idea**. You'll need a free GitHub account.
- **No GitHub account?** Reply in the Steam Community discussion thread for the mod. Feedback
  there is read too.

Before reporting something as a bug, it's worth checking
[How multiplayer plays](docs/HOW-IT-PLAYS.md), which explains the rules and how edge cases (Mr.
Bones, Hieroglyph/Petroglyph, skipping, disconnects) are handled.

For bugs, the most useful things to include are the mode, your platform (Windows or Mac), what you
expected versus what happened, and the newest log file from Lovely's log folder:

- Windows: `%APPDATA%\Balatro\Mods\lovely\log\`
- Mac: `~/Library/Application Support/Balatro/Mods/lovely/log/`

## Pull requests

PRs are welcome. For anything larger than a small fix, please open an issue first so we can agree
on the approach.

- The rules (lobbies, round gates, points, win conditions) live in
  `mod/BalatroDuelCoop/src/relay.lua`, which runs both in-game and in the Node server. Run the
  tests with `cd server && npm install && npm test`.
- `node tools/test-bot.js CODE` adds a stand-in second player to your lobby for testing alone.
- [TESTING.md](TESTING.md) has a checklist for testing with two PCs and two Steam accounts.
- The [README](README.md#how-it-works) has a map of which file does what.
