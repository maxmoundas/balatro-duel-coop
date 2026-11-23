# Versions

Every release of Balatro Duel & Co-op, what changed, and which versions can play together.
Per-release notes (the text that goes on GitHub, Thunderstore and Nexus) are in
[docs/releases/](releases/). How to cut a release: [RELEASING.md](RELEASING.md).

## At a glance

| Version | Released | Protocol | Plays with | Summary |
|---|---|---|---|---|
| [1.0.2](releases/v1.0.2.md) | unreleased | 5 | 1.0.2 only | Host can choose same or different seeds; Co-op Endless mode stays in sync; victory popup no longer gets stuck in Endless. |
| 1.0.1 | 2026-11-18 | 4 | 1.0.0, 1.0.1 | Listing and store-page update. No gameplay changes. |
| 1.0.0 | 2026-11-18 | 4 | 1.0.0, 1.0.1 | First public release. |

**Protocol** is the multiplayer protocol version (`MP.PROTOCOL` in `mod/BalatroDuelCoop/main.lua`,
`Relay.PROTOCOL_VERSION` in `mod/BalatroDuelCoop/src/relay.lua`). Players can only join a lobby
whose host (or dedicated server) runs the same protocol. Older clients get "different mod version
- everyone needs the latest Balatro Duel & Co-op". When the protocol changes, every player has to
update, and so does any dedicated server.

## Details

### 1.0.2 (unreleased)

**New**
- **Same seed or different seeds.** In the lobby the host can switch between everyone playing
  the same seed (the default, same as before) and each player getting their own random seed. The
  lobby header shows the seed, or **PER PLAYER**. Works in Duel and Co-op.
- **Co-op Endless mode plays together.** After a team victory, players who choose Endless Mode
  keep playing as a team, with the same round gates and pooled blind scores. A player who goes to
  the main menu from the win screen leaves the run without holding up the others. The endless
  run ends for the team when a blind is lost ("ENDLESS RUN OVER").

**Fixed**
- The "TEAM VICTORY / Main Menu" popup stayed on screen for the rest of an Endless run. The
  victory now shows over the win screen and goes away once you continue. The same applied to the
  Duel result.
- In Co-op, both players could continue into Endless, but rounds were no longer kept in sync
  (nobody waited for the others before the shop or the next blind).

**Rules / protocol**
- Protocol 4 → 5. Mixed 1.0.1 / 1.0.2 lobbies are refused with the "different mod version"
  message.
- New messages: `lobby_options` (client → relay, host only, before the game starts),
  `team_blind_won` (relay → co-op teammates when the first player beats a blind). `lobby` and
  `start` carry `sameSeed`; with different seeds each player's `start` has their own `seed`. A
  co-op team win sends `game_over` with `endless = true`, and the lobby keeps running.
- Co-op with different seeds: teammates can face different bosses and so different
  requirements. As soon as one player beats their blind it counts as beaten for the whole team.

### 1.0.1 (2026-11-18)

- Version bump for store listings: AI disclosure in the Thunderstore README, Nexus header image.
- No changes to gameplay or the protocol; plays with 1.0.0.

### 1.0.0 (2026-11-18)

First public release.
- **Duel** (1v1): same seed, deck and stake; points for best hand and fewest hands per blind.
- **Co-op** (2–4 players): pooled blind score, requirements scaled by player count, teammates
  can carry a player who is out of hands, team-wide Mr. Bones saves, shared Hieroglyph /
  Petroglyph.
- Round sync between blinds (shop and blind gates), skipping blinds, challenges in both modes.
- In-game hosting over Steam networking, Steam friend invites and rich-presence joining;
  optional dedicated Node server.
- Player viewer (Tab), in-run status bar, toasts.
- Windows and Mac installers, mod-only zip for mod managers, Thunderstore package.
