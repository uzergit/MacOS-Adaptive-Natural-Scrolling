this project was FULLY made by Claude

# Adaptive Natural Scrolling for macOS

**Natural scrolling on the trackpad, normal scrolling with a mouse — automatically.**

macOS uses one "natural scrolling" setting for both your trackpad and your mouse, so
most people end up with one of them feeling backwards. Adaptive Natural Scrolling
watches for mice connecting and disconnecting and flips the setting for you:

- 🖱️ **Mouse connected** → natural scrolling **off**
- 💻 **Only the trackpad** → natural scrolling **on**

It switches instantly (no logout), works for **every user on the Mac — including
accounts created later**, needs no permissions, never touches the network, and is
fully customizable.

## Install

Paste this into Terminal:

```bash
curl -fsSL https://github.com/uzergit/MacOS-Adaptive-Natural-Scrolling/releases/latest/download/install.sh | sudo bash
```

It asks for your password (it installs for all users), starts working right away and
sets itself up for everyone's next login. Run it again any time to upgrade — your
settings are kept.

<details>
<summary>Prefer to download it first?</summary>

Grab `install.sh` from the [latest release](https://github.com/uzergit/MacOS-Adaptive-Natural-Scrolling/releases/latest), then:

```bash
sudo bash ~/Downloads/install.sh
```
</details>

Requires macOS 13 (Ventura) or newer, on Apple Silicon or Intel. You may see a
"Background Items Added" notification — that's macOS telling you about the helper
that does the switching.

## Uninstall

```bash
curl -fsSL https://github.com/uzergit/MacOS-Adaptive-Natural-Scrolling/releases/latest/download/uninstall.sh | sudo bash
```

or, if it's installed:

```bash
sudo adaptive-scroll uninstall
```

Add `--purge` to also delete everyone's personal settings
(`... | sudo bash -s -- --purge`), or `--keep-config` to keep the all-users settings
for a later reinstall. Each user's natural scrolling is left however it was last set.

## Using it

There's nothing to do — it just works. For a look under the hood there's the
`adaptive-scroll` command:

| Command | What it does |
| --- | --- |
| `adaptive-scroll status` | What's connected, the current direction, whether the helper is running |
| `adaptive-scroll devices` | Every pointing device and whether it counts as a mouse (with its ID) |
| `adaptive-scroll apply` | Check devices and set the right direction now |
| `adaptive-scroll natural on\|off\|toggle` | Set it yourself (until the next mouse connects/disconnects) |
| `adaptive-scroll pause [30m\|2h\|1d]` | Stop switching automatically, for a while or until `resume` |
| `adaptive-scroll resume` | Start switching again |
| `adaptive-scroll config` | Show your settings and where they come from |
| `adaptive-scroll config edit` | Edit your own settings |
| `sudo adaptive-scroll config edit --system` | Edit the settings for all users |
| `adaptive-scroll config check` | Find mistakes in the settings files |
| `adaptive-scroll logs [--follow]` | See what it's been doing |
| `adaptive-scroll restart` | Restart the helper for your account |
| `sudo adaptive-scroll uninstall` | Remove it |

## Customizing

Settings live in a JSON file (comments allowed). Changes apply within a couple of
seconds — no restart.

| File | Applies to |
| --- | --- |
| `/Library/Application Support/AdaptiveNaturalScrolling/config.json` | Everyone (edit with `sudo adaptive-scroll config edit --system`) |
| `~/Library/Application Support/AdaptiveNaturalScrolling/config.json` | Just you — overrides the file above (`adaptive-scroll config edit`) |

| Setting | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | Turn automatic switching on or off |
| `naturalScrollingWithMouse` | `false` | Natural scrolling while a mouse is connected |
| `naturalScrollingWithoutMouse` | `true` | Natural scrolling with just the trackpad |
| `connectDelay` | `0.5` | Seconds to wait after a mouse connects |
| `disconnectDelay` | `2` | Seconds to wait after the last mouse disconnects (raise it if a Bluetooth mouse drops out when idle) |
| `transports` | `["USB", "Bluetooth"]` | Connection types that count as a mouse. Virtual pointers (Universal Control, Screen Sharing, Karabiner…) don't match |
| `externalTrackpadsCountAsMouse` | `false` | Treat a Magic Trackpad like a mouse |
| `ignoreDevices` | `[]` | Devices that never count — part of the name or `"vendorID:productID"` |
| `alwaysCountDevices` | `[]` | Devices that always count, same format |
| `applyAtLogin` | `true` | Set the right direction when you log in |
| `applyOnWake` | `true` | Check again after sleep |
| `enforce` | `false` | Undo manual changes made in System Settings |
| `enforceInterval` | `5` | How often (seconds) to check when `enforce` is on |
| `notifications` | `false` | Show a notification on every switch |
| `onChange` | `""` | Shell command to run on every switch (gets `ANS_NATURAL`, `ANS_MOUSE_CONNECTED`, `ANS_DEVICES`) |
| `logLevel` | `"info"` | `"quiet"`, `"info"` or `"debug"` |
| `excludedUsers` | `[]` | *All-users file only.* User names to leave alone |
| `allowUserConfig` | `true` | *All-users file only.* Let users override settings |

`adaptive-scroll config defaults` prints the full commented file.

### Examples

**A keyboard is being counted as a mouse** (some gaming keyboards do this) — find it
with `adaptive-scroll devices`, then:

```jsonc
"ignoreDevices": ["Gaming Keyboard", "0x1532:0x0084"]
```

**Your Bluetooth mouse naps and the direction flips back and forth:**

```jsonc
"disconnectDelay": 30
```

**You like it the other way round:**

```jsonc
"naturalScrollingWithMouse": true,
"naturalScrollingWithoutMouse": false
```

**Get told when it switches, and run something too:**

```jsonc
"notifications": true,
"onChange": "say \"$( [ $ANS_MOUSE_CONNECTED = 1 ] && echo mouse || echo trackpad ) mode\""
```

**Leave the guest account alone** (all-users file):

```jsonc
"excludedUsers": ["guest"]
```

## How it works

A small helper (`adaptive-scroll daemon`) runs in each logged-in user's session via a
LaunchAgent in `/Library/LaunchAgents`, which macOS starts for every user, new ones
included. It listens to the IOKit registry for HID devices appearing and
disappearing — reading device info only, so it needs no Input Monitoring or
Accessibility permission. When the set of mice changes it waits the configured delay,
checks again, and sets natural scrolling with the same system function System Settings
uses, so the change is immediate and saved as your normal preference.

What's installed:

```
/Library/Application Support/AdaptiveNaturalScrolling/   the program, uninstaller and settings
/Library/LaunchAgents/io.github.uzergit.adaptive-natural-scrolling.plist
/usr/local/bin/adaptive-scroll                           link to the command
```

## Troubleshooting

- **My mouse isn't detected / something else is.** Run `adaptive-scroll devices`. Add
  the device to `alwaysCountDevices` or `ignoreDevices`.
- **Notifications don't show up.** They're sent through AppleScript, so allow
  notifications for *Script Editor* in System Settings › Notifications.
- **Is it running?** `adaptive-scroll status`, then `adaptive-scroll logs`.
- **It stopped working after a macOS update.** The switch uses a private macOS function.
  If Apple removes it, the helper falls back to saving the preference (applied at next
  login) and says so in `adaptive-scroll logs` — please open an issue.

## Building from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/uzergit/MacOS-Adaptive-Natural-Scrolling.git
cd MacOS-Adaptive-Natural-Scrolling
sudo ./scripts/install.sh            # build from source and install
./scripts/build-release.sh           # build the release installer into dist/
```

## License

[MIT](LICENSE)
