# How multiplayer plays

This page covers the rules of each mode in detail: what's shared, what isn't, when you wait for
other players, and how unusual cards and situations are handled. For installing and starting a
game, see the [README](../README.md).

- [The basics (both modes)](#the-basics-both-modes)
- [Duel (1v1)](#duel-1v1)
- [Co-op (2–4 players)](#co-op-24-players)
- [Waiting for other players](#waiting-for-other-players)
- [Seeing what other players are doing](#seeing-what-other-players-are-doing)
- [Special cards and edge cases](#special-cards-and-edge-cases)
- [Leaving, disconnects and crashes](#leaving-disconnects-and-crashes)

---

## The basics (both modes)

- **Everyone plays their own copy of the run.** Each player has their own deck, hand, jokers,
  money, shop, consumables and vouchers. Nothing you buy or use changes another player's game,
  except for the [co-op exceptions below](#special-cards-and-edge-cases).
- **Everyone gets the same seed, deck and stake.** The host picks the deck and stake (or a
  challenge) in the lobby, and the seed is generated for the lobby. With the same seed you see the
  same blinds, bosses and starting shops, but your choices quickly make your runs different.
- **Challenges** can be played in either mode. A challenge brings its own deck and rules and is
  always played at White Stake, the same as in single player.
- **Hands are never held up.** Inside a blind or a shop, you play at your own speed. Players only
  wait for each other between rounds (see [Waiting for other players](#waiting-for-other-players)).
- **Multiplayer runs aren't saved.** If you close Balatro, the run can't be resumed. Your
  single-player save is never touched. Because every multiplayer run uses a set seed, Balatro
  treats it as a seeded run.
- **The run ends at the Ante 8 boss.** Beating it is a win, the same as in single player.

---

## Duel (1v1)

Two players race through the same run. You win by outlasting your opponent, or by outscoring them
if you both make it to the end.

### Points

After **both** players have finished a blind, two points are handed out for it:

| Point | Who gets it |
|---|---|
| **Best hand** | Whoever scored the single highest hand in that blind. |
| **Fewest hands** | Whoever beat the blind in the fewest hands. You only qualify if you beat it. |

- If you tie on either one, you both get that point.
- **Skipping a blind** gives you nothing for that blind. If your opponent plays it, they can take
  both points.
- If neither player plays a hand in a blind (for example, you both skip it), nobody gets points.
- Points appear as a message as soon as the second player finishes the blind, and the running
  total is on the status bar at the top of the screen.

### How a duel is decided

1. **Both players beat the Ante 8 boss:** most points wins. Equal points is a draw.
2. **One player's run ends first:** the other player wins as soon as they get past the blind the
   first player lost on. They don't have to finish the whole run.
3. **Both runs end on the same blind:** most points wins.
4. **Both runs end, on different blinds:** whoever got further wins.
5. **A player leaves** (returns to the main menu, closes the game or disconnects): the other
   player wins.

If your run ends while your opponent is still playing, you'll see *"Waiting for your opponent to
finish..."*. You can still press **Tab** to watch their board until the duel is decided.

---

## Co-op (2–4 players)

Everyone works together to beat the same blinds. Each player still has their own run; **only the
score is shared**.

### Shared score

- **Each blind's requirement is multiplied by the number of players playing it.** With 3 players,
  a 300-chip blind needs 900.
- **Every hand a teammate scores is added to your chip counter** as soon as it lands, with a
  message saying who scored it.
- **The blind is beaten as soon as the team total reaches the requirement**, no matter whose hand
  got it there. If a teammate's hand beats it while you're mid-hand, your hand finishes first and
  then the round ends for you as usual.
- Rewards (money at Cash Out, interest, end-of-round joker effects) are each player's own, worked
  out by their own game.

### Running out of hands

- **Running out of hands doesn't lose the blind.** You see an *"Out of hands"* banner and wait
  while your teammates keep playing. If they reach the target, you move on with them.
- **The blind is only lost if everyone playing it runs out of hands** before the team reaches the
  target. Then the team loses together, unless someone is saved (see
  [Mr. Bones](#mr-bones)).

### Skipping blinds

- A player who **skips** a blind takes its tag and sits that blind out.
- The players who select it play it, and the requirement is multiplied by **how many of them are
  playing** instead of the full team. If 1 of 3 players skips, the blind needs 2× its normal score.
- The blind select screen shows the requirement for the whole team. The final number appears once
  the blind starts, after everyone has chosen.
- The skipper then waits at the next blind select until everyone who played the skipped blind has
  finished it and left the shop.
- If **everyone** skips, the blind is skipped for the whole team.

### Winning and losing

- **The team wins when every player has beaten the Ante 8 boss.**
- **The team loses when a blind is lost**, which (as above) only happens when every player
  playing it is out of hands. Everyone, including players who skipped that blind or are waiting
  between rounds, goes to the game over screen together.

---

## Waiting for other players

Rounds stay in sync through two checkpoints, in both modes:

1. **Before the shop.** When you beat a blind and click **Cash Out**, the shop opens once every
   other player has finished that blind.
2. **Before the next blind.** When you select (or skip) the next blind, it starts once every other
   player has left their shop and chosen that blind too.

While you wait:

- A banner shows **who you're waiting for**, for example *"Waiting for Alex to finish the blind
  before the shop opens..."*.
- Press **Tab** (or click the status bar) to look at their board while you wait.
- Your click is remembered. You don't need to click again; the game carries on by itself once
  everyone is ready.
- **Players whose run has ended never hold anyone up.** In Duel, if your opponent has lost, you
  play on without waiting.

Everything else (playing hands, discarding, using tarots and planets, buying, selling,
rearranging) happens at your own pace and is never held up.

---

## Seeing what other players are doing

- **Status bar** (top of the screen, **F7** to hide or show it):
  - **Duel:** both players' points, and your opponent's last hand, best hand and hands played in
    the current blind.
  - **Co-op:** the current score multiplier (for example *CO-OP x3*), how much your teammates have
    added to this blind, and each teammate's last hand.
- **Player viewer** (**Tab**, or click the status bar):
  - **Compare:** your run next to theirs.
  - **Their cards:** jokers, consumables, vouchers, tags and their current hand.
  - **Deck:** their whole deck, with every enhancement, seal and edition. **Show mine** switches
    to yours.
  - **Poker hands:** their hand levels next to yours.
  - **History:** the score of every blind, hand by hand.
- The viewer updates live, and you can hover any card to read it.

---

## Special cards and edge cases

### Mr. Bones

**Duel:** works exactly as in single player. If Mr. Bones saves you, your run continues, but the
blind still counts as **not beaten** for points: you can't get the *fewest hands* point for it
(you can still get *best hand*).

**Co-op:** when every player playing a blind is out of hands, each player's game checks whether
it would be saved. A player is saved if they have a Mr. Bones that isn't debuffed and the
**team's combined score** is at least 25% of the **team's requirement**.

- If **anyone** is saved, **the whole team is saved** and moves on to the next round.
- The player who owns Mr. Bones loses it, as usual. Everyone else sees *"Saved by your team"*.
- A Mr. Bones belonging to a player who skipped that blind doesn't count, because they weren't
  playing it.

### Vouchers that go back an ante (Hieroglyph, Petroglyph)

- **Never below Ante 1.** In both modes, a multiplayer run can't go below Ante 1. Redeeming one of
  these at Ante 1 still gives you the voucher (and its cost of one hand or discard per round), but
  the ante stays at 1.
- **Duel:** only your own run goes back. You have more blinds to get through to reach the Ante 8
  boss, while your opponent doesn't. Points are still compared blind by blind in the order you
  each played them (your 10th blind against their 10th blind), even if you're at different antes
  by then.
- **Co-op:** when anyone redeems one, **the whole team goes back** with them, so everyone stays on
  the same ante. A message tells everyone who used it. Only the ante moves for teammates; the
  hand or discard penalty stays with the player who redeemed it.
- Starting vouchers from a deck or challenge don't trigger the team-wide move, since every player
  starts with them anyway.

### Other notes

- **Boss blinds** affect each player's own game, as usual. In Co-op, a boss that debuffs your
  cards or limits your hands only affects your own hands; your teammates' scores still count in
  full.
- **Endless mode:** the match is decided at the Ante 8 boss. Anything after that doesn't count.
- **Other mods:** mods that change scoring (for example Talisman) aren't supported yet.

---

## Leaving, disconnects and crashes

- **Duel:** if a player returns to the main menu, closes the game or disconnects, they forfeit and
  the other player wins.
- **Co-op:** if a player leaves, the rest of the team keeps playing. Blinds after that are scaled
  for the players who are left, and nobody waits for the player who left.
- **The host** runs the game server inside their Balatro. If the host closes the game, everyone is
  disconnected and the match ends.
- **Starting a new run** from the game over screen (**New Run**) starts a normal single-player
  run.
- Everyone needs the **same version of the mod**. If versions don't match, joining fails with a
  message telling you to update.

Found something that behaves differently from this page? Please
[report it](https://github.com/maxmoundas/balatro-multiplayer/issues/new/choose).
