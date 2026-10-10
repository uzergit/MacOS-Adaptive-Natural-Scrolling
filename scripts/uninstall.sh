#!/bin/bash
# Adaptive Natural Scrolling — uninstaller
# https://github.com/uzergit/MacOS-Adaptive-Natural-Scrolling
#
#   curl -fsSL https://github.com/uzergit/MacOS-Adaptive-Natural-Scrolling/releases/latest/download/uninstall.sh | sudo bash
#
# Options (after "sudo bash -s --" when piping):
#   --purge   also delete every user's personal settings
#   --keep-config  keep the all-users settings file for a later reinstall

set -euo pipefail

LABEL="io.github.uzergit.adaptive-natural-scrolling"
PREFIX="/Library/Application Support/AdaptiveNaturalScrolling"
PLIST="/Library/LaunchAgents/$LABEL.plist"
LINK="/usr/local/bin/adaptive-scroll"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

main() {
  local purge=0 keep_config=0 arg
  for arg in "$@"; do
    case "$arg" in
      --purge) purge=1 ;;
      --keep-config) keep_config=1 ;;
      -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) die "Unknown option: $arg" ;;
    esac
  done

  if [[ $EUID -ne 0 ]]; then
    [[ -f "${BASH_SOURCE[0]:-}" ]] && exec sudo /bin/bash "${BASH_SOURCE[0]}" "$@"
    die "Needs admin rights. Pipe it into sudo:  curl -fsSL <url> | sudo bash"
  fi

  say "Uninstalling Adaptive Natural Scrolling"

  local pid uid
  for pid in $(pgrep -x loginwindow || true); do
    uid=$(ps -o uid= -p "$pid" | tr -d ' ')
    [[ -n "$uid" && "$uid" != 0 ]] && launchctl bootout "gui/$uid/$LABEL" 2>/dev/null || true
  done
  # Anything left running (e.g. a session that was switched away from)
  pkill -f "$PREFIX/adaptive-scroll daemon" 2>/dev/null || true

  rm -f "$PLIST"
  [[ -L "$LINK" ]] && rm -f "$LINK"

  if (( keep_config )); then
    find "$PREFIX" -mindepth 1 ! -name config.json -delete 2>/dev/null || true
    say "Kept $PREFIX/config.json"
  else
    rm -rf "$PREFIX"
  fi

  local home
  if (( purge )); then
    for home in /Users/*; do
      rm -rf "$home/Library/Application Support/AdaptiveNaturalScrolling"
    done
    say "Deleted every user's personal settings"
  fi

  cat <<EOF

Removed. Each user's natural scrolling stays however it was last set — change it
in System Settings › Mouse or Trackpad.
EOF
  (( purge )) || echo "Personal settings (if any) were left in ~/Library/Application Support/AdaptiveNaturalScrolling."
}

main "$@"
