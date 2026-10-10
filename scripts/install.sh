#!/bin/bash
# Adaptive Natural Scrolling — installer
# https://github.com/uzergit/MacOS-Adaptive-Natural-Scrolling
#
#   curl -fsSL https://github.com/uzergit/MacOS-Adaptive-Natural-Scrolling/releases/latest/download/install.sh | sudo bash
#
# Installs for every user on this Mac, including accounts created later.
# Run it again to upgrade; your settings are kept.
#
# The release copy of this script carries a prebuilt universal binary. Run from a
# source checkout instead, it builds from Sources/ (needs the Xcode Command Line Tools).

set -euo pipefail

VERSION="@VERSION@"
LABEL="io.github.uzergit.adaptive-natural-scrolling"
PREFIX="/Library/Application Support/AdaptiveNaturalScrolling"
PLIST="/Library/LaunchAgents/$LABEL.plist"
LINK="/usr/local/bin/adaptive-scroll"
LEGACY_LABEL="com.local.autonaturalscroll"
# Stage into another root without starting anything (packaging / testing).
DESTDIR="${DESTDIR:-}"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

gui_users() {
  local pid uid
  for pid in $(pgrep -x loginwindow || true); do
    uid=$(ps -o uid= -p "$pid" | tr -d ' ')
    [[ -n "$uid" && "$uid" != 0 ]] && echo "$uid"
  done | sort -u
}

payload() {
cat <<'__END_OF_PAYLOAD__'
@PAYLOAD@
__END_OF_PAYLOAD__
}

main() {
  [[ "$(uname -s)" == Darwin ]] || die "This is for macOS."
  local major
  major=$(sw_vers -productVersion | cut -d. -f1)
  (( major >= 13 )) || die "Needs macOS 13 (Ventura) or newer."

  if [[ -z "$DESTDIR" && $EUID -ne 0 ]]; then
    [[ -f "${BASH_SOURCE[0]:-}" ]] && exec sudo /bin/bash "${BASH_SOURCE[0]}" "$@"
    die "Needs admin rights. Pipe it into sudo:  curl -fsSL <url> | sudo bash"
  fi

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  if [[ "$(payload)" == "@""PAYLOAD""@" ]]; then
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [[ -d "$here/../Sources" ]] || die "No built-in payload and no Sources/ folder next to this script."
    command -v swiftc >/dev/null || die "Building from source needs the Xcode Command Line Tools: xcode-select --install"
    say "Building from source"
    swiftc -O "$here"/../Sources/*.swift -o "$tmp/adaptive-scroll"
    cp "$here/uninstall.sh" "$tmp/uninstall.sh"
    VERSION=$("$tmp/adaptive-scroll" version)
  else
    payload | /usr/bin/base64 -D > "$tmp/payload.tgz"
    echo "@PAYLOAD_SHA256@  $tmp/payload.tgz" | shasum -a 256 -c --status \
      || die "The installer is damaged (checksum mismatch). Download it again."
    tar -xzf "$tmp/payload.tgz" -C "$tmp"
  fi

  say "Installing Adaptive Natural Scrolling $VERSION"

  local own=(-o root -g wheel) uid
  [[ -n "$DESTDIR" ]] && own=()

  if [[ -z "$DESTDIR" ]]; then
    for uid in $(gui_users); do
      launchctl bootout "gui/$uid/$LABEL" 2>/dev/null || true
      launchctl bootout "gui/$uid/$LEGACY_LABEL" 2>/dev/null || true
    done
    # Clean up the pre-release prototype if it's there.
    rm -f "/Library/LaunchAgents/$LEGACY_LABEL.plist"
    rm -rf "/Library/Application Support/AutoNaturalScroll"
  fi

  install -d ${own[@]+"${own[@]}"} -m 755 "$DESTDIR$PREFIX" "$DESTDIR/Library/LaunchAgents" "$DESTDIR/usr/local/bin"
  install ${own[@]+"${own[@]}"} -m 755 "$tmp/adaptive-scroll" "$DESTDIR$PREFIX/adaptive-scroll"
  install ${own[@]+"${own[@]}"} -m 755 "$tmp/uninstall.sh" "$DESTDIR$PREFIX/uninstall.sh"
  xattr -c "$DESTDIR$PREFIX/adaptive-scroll" "$DESTDIR$PREFIX/uninstall.sh" 2>/dev/null || true

  "$DESTDIR$PREFIX/adaptive-scroll" config defaults > "$DESTDIR$PREFIX/config.default.json"
  if [[ -f "$DESTDIR$PREFIX/config.json" ]]; then
    say "Kept your existing settings ($PREFIX/config.json)"
  else
    cp "$DESTDIR$PREFIX/config.default.json" "$DESTDIR$PREFIX/config.json"
    say "Created settings file: $PREFIX/config.json"
  fi
  chmod 644 "$DESTDIR$PREFIX"/config*.json
  [[ -z "$DESTDIR" ]] && chown root:wheel "$PREFIX"/config*.json

  cat > "$DESTDIR$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$PREFIX/adaptive-scroll</string>
		<string>daemon</string>
	</array>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
EOF
  chmod 644 "$DESTDIR$PLIST"
  [[ -z "$DESTDIR" ]] && chown root:wheel "$PLIST"

  ln -sf "$PREFIX/adaptive-scroll" "$DESTDIR$LINK"

  if [[ -n "$DESTDIR" ]]; then
    say "Staged into $DESTDIR (nothing started)"
    return
  fi

  # Start now for everyone logged in; everyone else (including future accounts) gets it at login.
  for uid in $(gui_users); do
    if launchctl bootstrap "gui/$uid" "$PLIST" 2>/dev/null; then
      say "Started for $(id -un "$uid")"
    else
      say "Couldn't start for $(id -un "$uid") now; it will start at their next login"
    fi
  done

  cat <<EOF

Done! Natural scrolling now turns off while a mouse is connected and back on
when it's just the trackpad — for every user on this Mac.

  adaptive-scroll status        what's connected and what's set
  adaptive-scroll devices       which devices count as a mouse
  adaptive-scroll config edit   customize it
  adaptive-scroll help          everything else

To uninstall:  sudo adaptive-scroll uninstall

EOF
}

main "$@"
