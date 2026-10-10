import Foundation

let usage = """
\(App.name) \(App.version)
Turns natural scrolling off while a mouse is connected and back on when it's just the trackpad.

Usage: adaptive-scroll <command>

  status                  What's connected, the current direction, and whether the agent is running
  devices                 Every pointing device and whether it counts as a mouse (with IDs)
  apply                   Check devices and set the right direction right now
  natural on|off|toggle   Set natural scrolling yourself (until the next mouse change; see pause)
  pause [duration]        Stop switching automatically, e.g. pause 30m / 2h / 1d (default: until resume)
  resume                  Start switching automatically again

  config                  Show your effective settings and where they come from
  config edit             Edit your own settings (override the all-users ones)
  config edit --system    Edit the settings for all users (run with sudo)
  config check            Check the settings files for mistakes
  config defaults         Print the default settings file
  config reset            Delete your own settings file

  logs [--follow]         Show recent activity (or keep watching with --follow)
  restart                 Restart the background agent for your account
  uninstall               Remove \(App.name) (asks for your password)
  version                 Print the version

\(App.repo)
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

func onOff(_ b: Bool) -> String { b ? "on" : "off" }

func agentStatus() -> String {
    let result = run("/bin/launchctl", ["print", "gui/\(getuid())/\(App.label)"])
    guard result.status == 0 else { return "not running" }
    if let line = result.output.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("pid = ") }) {
        return "running (pid \(line.split(separator: "=").last!.trimmingCharacters(in: .whitespaces)))"
    }
    return "loaded, not running"
}

func parseDuration(_ s: String) -> TimeInterval? {
    let units: [Character: Double] = ["s": 1, "m": 60, "h": 3600, "d": 86400]
    if let unit = s.last, let mult = units[unit], let n = Double(s.dropLast()), n > 0 { return n * mult }
    if let n = Double(s), n > 0 { return n * 60 }  // bare number = minutes
    return nil
}

func time(_ d: Date) -> String {
    let sameDay = Calendar.current.isDateInToday(d)
    return DateFormatter.localizedString(from: d, dateStyle: sameDay ? .none : .short, timeStyle: .short)
}

func openEditor(_ path: String, system: Bool) {
    if let editor = ProcessInfo.processInfo.environment["EDITOR"], !editor.isEmpty {
        run("/bin/sh", ["-c", "\(editor) \"$0\"", path], capture: false)
    } else if system {
        run("/usr/bin/nano", [path], capture: false)
    } else {
        run("/usr/bin/open", ["-t", path])
        print("Opened \(path) in your text editor.")
    }
    print("Saved changes apply within a couple of seconds. Check them with: adaptive-scroll config check")
}

func showConfig() {
    let loaded = ConfigLoader.load()
    let c = loaded.config
    let sysExists = FileManager.default.fileExists(atPath: App.systemConfig)
    print("All users:  \(App.systemConfig)\(sysExists ? "" : "  (missing, using defaults)")")
    if c.allowUserConfig {
        print("Just you:   \(App.userConfig)\(loaded.userFileUsed ? "" : "  (not created; run: adaptive-scroll config edit)")")
    } else {
        print("Just you:   turned off by the all-users file (\"allowUserConfig\": false)")
    }
    print("""

    enabled                        \(c.enabled)
    naturalScrollingWithMouse      \(c.naturalScrollingWithMouse)
    naturalScrollingWithoutMouse   \(c.naturalScrollingWithoutMouse)
    connectDelay                   \(c.connectDelay)s
    disconnectDelay                \(c.disconnectDelay)s
    transports                     \(c.transports.joined(separator: ", "))
    externalTrackpadsCountAsMouse  \(c.externalTrackpadsCountAsMouse)
    ignoreDevices                  \(c.ignoreDevices.isEmpty ? "-" : c.ignoreDevices.joined(separator: ", "))
    alwaysCountDevices             \(c.alwaysCountDevices.isEmpty ? "-" : c.alwaysCountDevices.joined(separator: ", "))
    applyAtLogin                   \(c.applyAtLogin)
    applyOnWake                    \(c.applyOnWake)
    enforce                        \(c.enforce)\(c.enforce ? " (every \(c.enforceInterval)s)" : "")
    notifications                  \(c.notifications)
    onChange                       \(c.onChange.isEmpty ? "-" : c.onChange)
    logLevel                       \(c.logLevel.rawValue)
    excludedUsers                  \(c.excludedUsers.isEmpty ? "-" : c.excludedUsers.joined(separator: ", "))
    allowUserConfig                \(c.allowUserConfig)
    """)
    if !loaded.problems.isEmpty {
        print("\nProblems:")
        loaded.problems.forEach { print("  • \($0)") }
    }
}

// MARK: - Commands

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "help" : args.removeFirst()

switch command {
case "daemon":
    Agent().start()

case "status":
    let loaded = ConfigLoader.load()
    let c = loaded.config
    let pause = PauseState.load()
    let mice = Devices.connectedMice(c)
    let expected = mice.isEmpty ? c.naturalScrollingWithoutMouse : c.naturalScrollingWithMouse

    let switching: String
    if !c.enabled { switching = "off (\"enabled\": false in settings)" }
    else if c.excludedUsers.contains(NSUserName()) { switching = "off for \(NSUserName()) (excludedUsers)" }
    else if pause.isActive { switching = "paused" + (pause.until.map { " until \(time($0))" } ?? " (run: adaptive-scroll resume)") }
    else { switching = "on" }

    print("""
    \(App.name) \(App.version)
    Agent:               \(agentStatus())
    Automatic switching: \(switching)
    Mouse connected:     \(mice.isEmpty ? "no" : "yes — " + mice.map { "\($0.name) (\($0.transport))" }.joined(separator: ", "))
    Natural scrolling:   \(onOff(Scrolling.natural))\(Scrolling.natural == expected ? "" : "  (settings say \(onOff(expected)))")
    """)
    if !loaded.problems.isEmpty { print("\nSettings problems — run: adaptive-scroll config check") }

case "devices", "list", "--list":
    let c = ConfigLoader.load().config
    let all = Devices.pointing()
    if all.isEmpty { print("No pointing devices found.") }
    for d in all {
        let reason = Devices.exclusionReason(d, c)
        print("\(reason == nil ? "✓ mouse  " : "  ignored") \(d.name)")
        print("          id \(d.id) · \(d.transport.isEmpty ? "no transport" : d.transport)\(reason.map { " · \($0)" } ?? "")")
    }
    print("\nTo ignore or always count a device, add its name or id to ignoreDevices / alwaysCountDevices (adaptive-scroll config edit).")

case "apply":
    let loaded = ConfigLoader.load()
    let c = loaded.config
    if PauseState.load().isActive { fail("Paused — run: adaptive-scroll resume") }
    if !c.enabled { fail("Automatic switching is turned off in settings (\"enabled\": false)") }
    let mice = Devices.connectedMice(c)
    let want = mice.isEmpty ? c.naturalScrollingWithoutMouse : c.naturalScrollingWithMouse
    Scrolling.set(natural: want)
    print("Natural scrolling \(onOff(want)) — \(mice.isEmpty ? "no mouse connected" : mice.map(\.name).joined(separator: ", "))")

case "natural":
    let current = Scrolling.natural
    let want: Bool
    switch args.first {
    case "on", "true", "1": want = true
    case "off", "false", "0": want = false
    case "toggle": want = !current
    case nil: print("Natural scrolling is \(onOff(current))"); exit(0)
    default: fail("Usage: adaptive-scroll natural on|off|toggle")
    }
    Scrolling.set(natural: want)
    print("Natural scrolling \(onOff(want)).")
    if !PauseState.load().isActive {
        print("It will switch automatically again the next time a mouse connects or disconnects. To keep it, run: adaptive-scroll pause")
    }

case "pause":
    var state = PauseState(paused: true)
    if let arg = args.first {
        guard let seconds = parseDuration(arg) else { fail("Couldn't read \"\(arg)\". Try 30m, 2h or 1d.") }
        state.until = Date().addingTimeInterval(seconds)
    }
    do { try state.save() } catch { fail("Couldn't save: \(error.localizedDescription)") }
    print("Paused" + (state.until.map { " until \(time($0))." } ?? ". Run adaptive-scroll resume to start again."))

case "resume":
    do { try PauseState().save() } catch { fail("Couldn't save: \(error.localizedDescription)") }
    print("Resumed. The right direction will be set in a moment.")

case "config":
    switch args.first {
    case nil, "show":
        showConfig()
    case "edit":
        if args.contains("--system") {
            guard getuid() == 0 else { fail("Editing the all-users settings needs admin rights: sudo adaptive-scroll config edit --system") }
            if !FileManager.default.fileExists(atPath: App.systemConfig) {
                try? FileManager.default.createDirectory(atPath: App.systemDir, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: App.systemConfig, contents: Data(ConfigLoader.defaultText.utf8))
            }
            openEditor(App.systemConfig, system: true)
        } else {
            if !FileManager.default.fileExists(atPath: App.userConfig) {
                try? FileManager.default.createDirectory(atPath: App.userDir, withIntermediateDirectories: true)
                let base = (try? String(contentsOfFile: App.systemConfig, encoding: .utf8)) ?? ConfigLoader.defaultText
                let header = "// Your personal settings. They override the all-users file for your account only.\n// Delete a line to fall back to the all-users value. (excludedUsers and allowUserConfig are ignored here.)\n\n"
                FileManager.default.createFile(atPath: App.userConfig, contents: Data((header + base).utf8))
            }
            openEditor(App.userConfig, system: false)
        }
    case "check":
        let loaded = ConfigLoader.load()
        if loaded.problems.isEmpty { print("Settings look good.") } else {
            loaded.problems.forEach { print("• \($0)") }
            exit(1)
        }
    case "defaults":
        print(ConfigLoader.defaultText, terminator: "")
    case "reset":
        if FileManager.default.fileExists(atPath: App.userConfig) {
            do { try FileManager.default.removeItem(atPath: App.userConfig) } catch { fail(error.localizedDescription) }
            print("Removed your settings file; the all-users settings apply again.")
        } else {
            print("You don't have a personal settings file.")
        }
    default:
        fail("Unknown config command. Try: config, config edit, config check, config defaults, config reset")
    }

case "logs":
    let predicate = "subsystem == \"\(App.label)\""
    if args.contains("--follow") || args.contains("-f") {
        run("/usr/bin/log", ["stream", "--style", "compact", "--level", "default", "--predicate", predicate], capture: false)
    } else {
        run("/usr/bin/log", ["show", "--last", "24h", "--style", "compact", "--predicate", predicate], capture: false)
    }

case "restart":
    let result = run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(App.label)"])
    if result.status == 0 { print("Restarted.") } else {
        let plist = "/Library/LaunchAgents/\(App.label).plist"
        let boot = run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plist])
        if boot.status == 0 { print("Started.") } else { fail("Couldn't start the agent. Is it installed? (\(plist))") }
    }

case "uninstall":
    guard FileManager.default.fileExists(atPath: App.uninstaller) else { fail("Uninstaller not found at \(App.uninstaller)") }
    let args = getuid() == 0 ? [App.uninstaller] + args : ["/bin/bash", App.uninstaller] + args
    exit(run(getuid() == 0 ? "/bin/bash" : "/usr/bin/sudo", args, capture: false).status)

case "version", "--version", "-v":
    print(App.version)

case "help", "--help", "-h":
    print(usage)

default:
    fail("Unknown command \"\(command)\".\n\n\(usage)")
}
