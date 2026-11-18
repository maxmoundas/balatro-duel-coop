# Shared by install-mac.sh and uninstall-mac.sh (macOS). Sourced, not run.

if [ -t 1 ]; then
  YELLOW=$'\033[33m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  YELLOW=''; CYAN=''; GREEN=''; RED=''; RESET=''
fi

step()  { printf '\n%s==> %s%s\n' "$CYAN" "$1" "$RESET"; }
done_() { printf '    %s%s%s\n' "$GREEN" "$1" "$RESET"; }
die()   { printf '\n%sFailed: %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }

BALATRO_DATA="$HOME/Library/Application Support/Balatro"
MODS_DIR="$BALATRO_DATA/Mods"
STEAM_DIR="$HOME/Library/Application Support/Steam"
# First line after the shebang of the launcher we put in place of Balatro's executable.
LAUNCHER_MARK='# balatro-multiplayer lovely launcher'

# Questions are read from the terminal, so they work under `curl ... | bash` too.
ask() { # prompt -> answer on stdout
  local a=''
  [ -r /dev/tty ] || die 'No terminal to ask questions in. Run this from Terminal.'
  printf '%s' "$1" > /dev/tty
  IFS= read -r a < /dev/tty || true
  printf '%s' "$a"
}

ask_yes_no() { # question -> exit status 0 for yes
  local a
  while true; do
    a="$(ask "$1 [y/N] " | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "$a" in
      ''|n|no) return 1 ;;
      y|yes) return 0 ;;
    esac
  done
}

is_balatro_dir() { [ -d "$1/Balatro.app/Contents/MacOS" ]; }

find_balatro_dir() {
  local c
  local candidates=("$STEAM_DIR/steamapps/common/Balatro")
  local vdf="$STEAM_DIR/steamapps/libraryfolders.vdf"
  if [ -f "$vdf" ]; then
    while IFS= read -r c; do candidates+=("$c/steamapps/common/Balatro"); done \
      < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$vdf")
  fi
  for c in "${candidates[@]}"; do
    if is_balatro_dir "$c"; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

# Ask for the game folder when Steam's library list doesn't lead to it.
get_balatro_dir() {
  local game p
  game="$(find_balatro_dir || true)"
  while [ -z "$game" ]; do
    p="$(ask 'Could not find Balatro. Drag the Balatro game folder here (Steam > Balatro > Manage > Browse local files), then press Enter: ')"
    p="${p%"${p##*[![:space:]]}"}"; p="${p#"${p%%[![:space:]]*}"}" # trim
    p="${p%\'}"; p="${p#\'}"; p="${p//\\ / }"                       # Terminal's drag-and-drop quoting
    case "$p" in */Balatro.app|*/Balatro.app/) p="$(dirname "$p")" ;; esac
    if is_balatro_dir "$p"; then game="$p"; else printf '%sBalatro.app not found there.%s\n' "$RED" "$RESET" > /dev/tty; fi
  done
  printf '%s' "$game"
}

balatro_running() { pgrep -f 'Balatro.app/Contents/MacOS/love' >/dev/null 2>&1; }

wait_balatro_closed() {
  while balatro_running; do
    ask "${YELLOW}Balatro is running. Please quit it, then press Enter.${RESET}" > /dev/null
  done
}

# Steamodded folders in the Mods folder (any name; it has src/core.lua).
find_smods() {
  local d
  [ -d "$MODS_DIR" ] || return 0
  for d in "$MODS_DIR"/*/; do
    [ -f "$d/src/core.lua" ] && printf '%s\n' "${d%/}"
  done
  return 0
}

is_launcher() { [ -f "$1" ] && head -n 2 "$1" 2>/dev/null | grep -qF "$LAUNCHER_MARK"; }
is_macho() { file -b "$1" 2>/dev/null | grep -q 'Mach-O'; }

write_launcher() { # path
  cat > "$1" <<'EOF'
#!/bin/bash
# balatro-multiplayer lovely launcher
# Starts Balatro with Lovely (the mod loader). Installed by Balatro Duel & Co-op's
# install-mac.sh in place of Balatro's executable; the real one is love-original.
# To undo, run uninstall-mac.sh (or Steam > Balatro > Properties > Installed Files >
# Verify integrity of game files).
here="$(cd "$(dirname "$0")" && pwd)"
lovely="$(cd "$here/../../.." && pwd)/liblovely.dylib"
# Steam passes its overlay libraries in STEAM_DYLD_INSERT_LIBRARIES; keep them.
libs="${STEAM_DYLD_INSERT_LIBRARIES:-}"
[ -f "$lovely" ] && libs="$lovely${libs:+:$libs}"
[ -n "$libs" ] && export DYLD_INSERT_LIBRARIES="$libs"
exec "$here/love-original" "$@"
EOF
  chmod 755 "$1"
}

# Put the launcher in place of Balatro.app/Contents/MacOS/love (idempotent; also
# repairs things after a Balatro update replaced the launcher with the real binary).
install_launcher() { # game dir
  local macos="$1/Balatro.app/Contents/MacOS"
  local love="$macos/love" real="$macos/love-original"
  if is_launcher "$love"; then
    [ -f "$real" ] || die "love-original is missing. In Steam: right-click Balatro > Properties > Installed Files > Verify integrity of game files, then run this installer again."
    write_launcher "$love"
    done_ 'already installed'
  elif is_macho "$love"; then
    mv -f "$love" "$real"
    write_launcher "$love"
    done_ 'installed'
  else
    die "$love isn't the Balatro game or our launcher (another mod tool may have replaced it). Verify the game files in Steam, then run this installer again."
  fi
}

# Put Balatro's real executable back.
remove_launcher() { # game dir
  local macos="$1/Balatro.app/Contents/MacOS"
  local love="$macos/love" real="$macos/love-original"
  if is_launcher "$love" && [ -f "$real" ]; then
    mv -f "$real" "$love"
    done_ 'removed launcher (restored the original game executable)'
  elif [ -f "$real" ] && is_macho "$love"; then
    rm -f "$real" # leftover from before a Balatro update
  fi
}
