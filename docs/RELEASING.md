# Releasing a new version

A checklist for cutting a release. Version history is in [VERSIONS.md](VERSIONS.md).

## Choosing the version number

- **Patch (1.0.x):** fixes and small features.
- **Minor (1.x.0):** bigger features or rule changes.
- **Protocol:** bump `MP.PROTOCOL` (`mod/BalatroDuelCoop/main.lua`) and
  `Relay.PROTOCOL_VERSION` (`mod/BalatroDuelCoop/src/relay.lua`) together whenever messages or
  rules change so that old and new versions would misbehave together. Also update the
  `protocol:` value in `server/test/relay.test.js` and `tools/test-bot.js`. A protocol bump means
  every player and any dedicated server must update, so say so at the top of the release notes.

## 1. Prepare

1. Set the version in all four places (they must match):
   - `mod/BalatroDuelCoop/BalatroDuelCoop.json` → `"version": "X.Y.Z"` (the release workflow
     checks the tag against this one)
   - `mod/BalatroDuelCoop/main.lua` → `MP.VERSION = 'X.Y.Z'`
   - `publish/thunderstore/manifest.json` → `"version_number": "X.Y.Z"`
   - `publish/mod-index/meta.json` → `"version": "vX.Y.Z"`
2. Write the player-facing notes in `docs/releases/vX.Y.Z.md`. The release workflow puts this
   file at the top of the GitHub Release; reuse it for Thunderstore, Nexus and announcements.
3. Add the version to [VERSIONS.md](VERSIONS.md): a row in the table and a details section.
   Change "unreleased" to the date when you tag.
4. Update player docs if the rules changed: `README.md`, `docs/HOW-IT-PLAYS.md`,
   `publish/thunderstore/README.md`, `publish/mod-index/description.md`, and `TESTING.md` for new
   things to check.

## 2. Test

1. `cd server && npm install && npm test`: all tests pass.
2. Build the package locally: `.\tools\build-friend-package.ps1` (Windows) or
   `./tools/build-friend-package.sh` (Mac), and install it.
3. Play through [TESTING.md](TESTING.md) with two PCs, at least the sections the release touches.
   For quick checks alone, `node tools/test-bot.js CODE` joins your lobby as a second player.

## 3. Publish

1. Commit and push to `main`. The **Build installer** workflow builds the zips as a check;
   make sure it passes on GitHub (Actions tab).
2. Tag and push:
   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
   The workflow creates the GitHub Release (marked Latest) with `BalatroDuelCoop-Setup.zip`,
   `BalatroDuelCoop.zip`, `BalatroDuelCoop-Thunderstore.zip` and the Mac scripts, and uses
   `docs/releases/vX.Y.Z.md` as the release notes. The README's install links always point at the
   latest release, so they need no change.
3. **Dedicated server** (only if you run one, e.g. on Fly.io): redeploy so it runs the new
   `relay.lua`. Required when the protocol changed:
   `fly deploy --config server/fly.toml` from the repo root.
4. **Thunderstore:** download `BalatroDuelCoop-Thunderstore.zip` from the GitHub Release and
   upload it at thunderstore.io (Upload → Balatro). The version comes from the manifest inside.
5. **Nexus Mods:** on the mod page, upload `BalatroDuelCoop-Setup.zip` (and the mod-only zip if
   you list it) as a new main file with version X.Y.Z, archive the old file, and paste the
   release notes into the changelog.
6. **Balatro Mod Index:** `meta.json` has `automatic-version-check`, so the index picks up the new
   GitHub Release on its own. Check that it shows the new version after a while; if it doesn't,
   open a PR to the index updating the version.
7. **Announce:** post the release notes in the Steam guide / discussion thread and Discord. If
   the protocol changed, lead with "everyone needs to update".

## 4. Afterwards

- Install from the public links (Windows zip, Mac one-liner, r2modman/Gale) on a clean
  machine if you can, and join a game with someone on the new version.
- Watch the issue tracker for a day or two for install or connection problems.
