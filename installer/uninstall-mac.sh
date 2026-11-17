#!/bin/bash
# Balatro Multiplayer - uninstaller for macOS.
# Always removes the Balatro Multiplayer mod and its settings. Then asks whether to also
# remove Lovely and Steamodded (the mod loaders), which other mods may still need.
# Never touches your save files.
#
#   curl -fsSL https://github.com/maxmoundas/balatro-multiplayer/releases/latest/download/uninstall-mac.sh | bash
# or, from the unzipped BalatroMultiplayer-Setup folder:
#   bash files/uninstall-mac.sh

set -euo pipefail

src="${BASH_SOURCE[0]:-}"
if [ -n "$src" ] && [ -f "$src" ] && [ -f "$(dirname "$src")/common-mac.sh" ]; then
  . "$(cd "$(dirname "$src")" && pwd)/common-mac.sh"
else
  # Piped from curl: fetch the shared helpers from the same release.
  tmp="$(mktemp -d -t bmp)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/common-mac.sh" 'https://github.com/maxmoundas/balatro-multiplayer/releases/latest/download/common-mac.sh' \
    || { echo 'Download failed (are you online?)' >&2; exit 1; }
  . "$tmp/common-mac.sh"
fi

printf '%sBalatro Multiplayer uninstaller (macOS)%s\n' "$YELLOW" "$RESET"
wait_balatro_closed

step 'Balatro Multiplayer mod'
if [ -d "$MODS_DIR/BalatroMultiplayer" ]; then
  rm -rf "$MODS_DIR/BalatroMultiplayer"
  done_ 'removed'
else
  done_ 'not installed'
fi
# Settings (name, server) saved by Steamodded.
cfg="$BALATRO_DATA/config/BalatroMultiplayerDuelCoop.jkr"
if [ -f "$cfg" ]; then rm -f "$cfg"; done_ 'settings removed'; fi

# Lovely + Steamodded: optional, other mods depend on them.
smods=()
while IFS= read -r d; do [ -n "$d" ] && smods+=("$d"); done < <(find_smods)
game="$(find_balatro_dir || true)"
has_lovely=0
if [ -n "$game" ] && { [ -f "$game/liblovely.dylib" ] || is_launcher "$game/Balatro.app/Contents/MacOS/love"; }; then has_lovely=1; fi

if [ "${#smods[@]}" -gt 0 ] || [ "$has_lovely" = 1 ]; then
  others=()
  if [ -d "$MODS_DIR" ]; then
    for d in "$MODS_DIR"/*/; do
      d="${d%/}"; name="$(basename "$d")"
      [ -d "$d" ] || continue
      [ "$name" = lovely ] && continue
      skip=0
      for s in ${smods[@]+"${smods[@]}"}; do [ "$s" = "$d" ] && skip=1; done
      [ "$skip" = 0 ] && others+=("$name")
    done
  fi
  printf '\n%sLovely and Steamodded (the mod loaders) are still installed.%s\n' "$CYAN" "$RESET"
  if [ "${#others[@]}" -gt 0 ]; then
    printf '%sYou have other mods that need them: %s%s\n' "$YELLOW" "$(IFS=,; echo "${others[*]}" | sed 's/,/, /g')" "$RESET"
    printf '%sKeep them unless you want to remove ALL mods.%s\n' "$YELLOW" "$RESET"
  else
    echo 'No other mods use them. Removing them makes Balatro completely unmodded again.'
  fi

  if ask_yes_no 'Also remove Lovely and Steamodded?'; then
    step 'Steamodded'
    for d in ${smods[@]+"${smods[@]}"}; do rm -rf "$d"; done_ "removed $(basename "$d")"; done
    rm -f "$BALATRO_DATA/config/Steamodded.jkr"
    step 'Lovely'
    if [ -n "$game" ]; then
      remove_launcher "$game"
      if [ -f "$game/liblovely.dylib" ]; then rm -f "$game/liblovely.dylib"; done_ 'removed liblovely.dylib'; fi
    fi
    if [ -d "$MODS_DIR/lovely" ]; then rm -rf "$MODS_DIR/lovely"; done_ 'removed Lovely logs'; fi
    rmdir "$MODS_DIR" 2>/dev/null || true
  else
    done_ 'kept Lovely and Steamodded'
  fi
fi

printf '\n%sDone. Your Balatro saves were not touched.%s\n' "$GREEN" "$RESET"
