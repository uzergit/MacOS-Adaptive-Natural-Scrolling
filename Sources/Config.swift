import Foundation

struct Config {
    var enabled = true
    var naturalScrollingWithMouse = false
    var naturalScrollingWithoutMouse = true
    var connectDelay = 0.5
    var disconnectDelay = 2.0
    var transports = ["USB", "Bluetooth"]
    var externalTrackpadsCountAsMouse = false
    var ignoreDevices: [String] = []
    var alwaysCountDevices: [String] = []
    var applyAtLogin = true
    var applyOnWake = true
    var enforce = false
    var enforceInterval = 5.0
    var notifications = false
    var onChange = ""
    var logLevel = LogLevel.info
    // System-wide file only
    var excludedUsers: [String] = []
    var allowUserConfig = true

    static let systemOnlyKeys: Set<String> = ["excludedUsers", "allowUserConfig"]

    /// Applies one config file's values on top of this config. Returns problems found.
    mutating func merge(_ dict: [String: Any], file: String, isUserFile: Bool) -> [String] {
        var problems: [String] = []
        func bad(_ key: String, _ expected: String) { problems.append("\(file): \"\(key)\" should be \(expected)") }

        for (key, value) in dict {
            // Personal files start as a copy of the all-users file, so these are expected there.
            if isUserFile && Config.systemOnlyKeys.contains(key) { continue }
            switch key {
            case "enabled":                       if let v = value as? Bool { enabled = v } else { bad(key, "true or false") }
            case "naturalScrollingWithMouse":     if let v = value as? Bool { naturalScrollingWithMouse = v } else { bad(key, "true or false") }
            case "naturalScrollingWithoutMouse":  if let v = value as? Bool { naturalScrollingWithoutMouse = v } else { bad(key, "true or false") }
            case "connectDelay":                  if let v = number(value), v >= 0 { connectDelay = v } else { bad(key, "a number of seconds") }
            case "disconnectDelay":               if let v = number(value), v >= 0 { disconnectDelay = v } else { bad(key, "a number of seconds") }
            case "transports":                    if let v = value as? [String] { transports = v } else { bad(key, "a list of strings") }
            case "externalTrackpadsCountAsMouse": if let v = value as? Bool { externalTrackpadsCountAsMouse = v } else { bad(key, "true or false") }
            case "ignoreDevices":                 if let v = value as? [String] { ignoreDevices = v } else { bad(key, "a list of strings") }
            case "alwaysCountDevices":            if let v = value as? [String] { alwaysCountDevices = v } else { bad(key, "a list of strings") }
            case "applyAtLogin":                  if let v = value as? Bool { applyAtLogin = v } else { bad(key, "true or false") }
            case "applyOnWake":                   if let v = value as? Bool { applyOnWake = v } else { bad(key, "true or false") }
            case "enforce":                       if let v = value as? Bool { enforce = v } else { bad(key, "true or false") }
            case "enforceInterval":               if let v = number(value), v >= 1 { enforceInterval = v } else { bad(key, "a number of seconds (1 or more)") }
            case "notifications":                 if let v = value as? Bool { notifications = v } else { bad(key, "true or false") }
            case "onChange":                      if let v = value as? String { onChange = v } else { bad(key, "a string") }
            case "logLevel":                      if let s = value as? String, let v = LogLevel(rawValue: s) { logLevel = v } else { bad(key, "\"quiet\", \"info\" or \"debug\"") }
            case "excludedUsers":                 if let v = value as? [String] { excludedUsers = v } else { bad(key, "a list of strings") }
            case "allowUserConfig":               if let v = value as? Bool { allowUserConfig = v } else { bad(key, "true or false") }
            default:                              problems.append("\(file): unknown setting \"\(key)\" (typo?)")
            }
        }
        return problems
    }

    private func number(_ value: Any) -> Double? {
        // JSONSerialization hands back booleans as NSNumber too; don't accept them as numbers.
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }
}

struct LoadedConfig {
    var config: Config
    var problems: [String]
    /// True when a file exists but couldn't be parsed at all.
    var hasParseError: Bool
    var userFileUsed: Bool
}

enum ConfigLoader {
    /// nil when the file doesn't exist.
    static func read(_ path: String) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var text = try String(contentsOfFile: path, encoding: .utf8)
        // TextEdit likes to "smarten" quotes, which breaks JSON.
        text = text.replacingOccurrences(of: "\u{201C}", with: "\"")
                   .replacingOccurrences(of: "\u{201D}", with: "\"")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        let obj = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.json5Allowed])
        guard let dict = obj as? [String: Any] else {
            throw NSError(domain: App.label, code: 1, userInfo: [NSLocalizedDescriptionKey: "the top level must be { ... }"])
        }
        return dict
    }

    static func load() -> LoadedConfig {
        var result = LoadedConfig(config: Config(), problems: [], hasParseError: false, userFileUsed: false)

        func apply(_ path: String, isUserFile: Bool) {
            do {
                guard let dict = try read(path) else { return }
                result.problems += result.config.merge(dict, file: path, isUserFile: isUserFile)
                if isUserFile { result.userFileUsed = true }
            } catch {
                result.hasParseError = true
                let detail = (error as NSError).userInfo["NSDebugDescription"] as? String ?? error.localizedDescription
                result.problems.append("\(path): can't be read — \(detail)")
            }
        }

        apply(App.systemConfig, isUserFile: false)
        if result.config.allowUserConfig {
            apply(App.userConfig, isUserFile: true)
        }
        return result
    }

    static let defaultText = #"""
// Adaptive Natural Scrolling — settings
//
// JSON with comments. Saved changes are picked up within ~2 seconds, no restart needed.
//
//   All users:      /Library/Application Support/AdaptiveNaturalScrolling/config.json
//   Just one user:  ~/Library/Application Support/AdaptiveNaturalScrolling/config.json
//
// Anything in a user's own file overrides the all-users file for that user.
// Check your edits with:  adaptive-scroll config check
{
  // Turn automatic switching on or off.
  "enabled": true,

  // ── What to switch to ─────────────────────────────────────────────
  // Natural scrolling while at least one mouse is connected.
  "naturalScrollingWithMouse": false,
  // Natural scrolling when no mouse is connected (trackpad only).
  "naturalScrollingWithoutMouse": true,

  // ── Timing ────────────────────────────────────────────────────────
  // Seconds to wait after a mouse connects before switching.
  "connectDelay": 0.5,
  // Seconds to wait after the last mouse disconnects before switching back.
  // Raise this if your Bluetooth mouse drops out for a moment when idle.
  "disconnectDelay": 2,

  // ── What counts as a mouse ────────────────────────────────────────
  // Connection types that count. "USB" covers wired mice and wireless USB
  // receivers; "Bluetooth" also covers Bluetooth Low Energy. Virtual pointers
  // (Universal Control, Screen Sharing, Karabiner, ...) are never counted
  // unless you add their transport here or list them in alwaysCountDevices.
  "transports": ["USB", "Bluetooth"],

  // Count an external trackpad (like a Magic Trackpad) as a mouse.
  "externalTrackpadsCountAsMouse": false,

  // Devices that should never count as a mouse. Each entry is either part of
  // the device's name (not case-sensitive) or "vendorID:productID" in hex.
  // Run  adaptive-scroll devices  to see names and IDs.
  // Example: ["Gaming Keyboard", "0x046d:0xc52b"]
  "ignoreDevices": [],

  // Devices that should always count as a mouse, even if something above
  // would exclude them. Same format as ignoreDevices.
  "alwaysCountDevices": [],

  // ── When to act ───────────────────────────────────────────────────
  // Set the right direction as soon as you log in.
  "applyAtLogin": true,
  // Check again after the Mac wakes from sleep.
  "applyOnWake": true,
  // If you flip natural scrolling yourself in System Settings, flip it back.
  // When false, a manual change sticks until a mouse connects or disconnects.
  "enforce": false,
  // How often (in seconds) to check when "enforce" is on.
  "enforceInterval": 5,

  // ── Feedback ──────────────────────────────────────────────────────
  // Show a notification each time the direction switches.
  "notifications": false,
  // A shell command to run each time the direction switches. It receives:
  //   ANS_NATURAL=1 or 0, ANS_MOUSE_CONNECTED=1 or 0, ANS_DEVICES="Mouse A, Mouse B"
  // Example: "say \"mouse mode\""
  "onChange": "",
  // "quiet", "info" or "debug". View with:  adaptive-scroll logs
  "logLevel": "info",

  // ── All-users file only (ignored in a user's own file) ────────────
  // Short user names to leave alone, e.g. ["guest", "kiosk"].
  "excludedUsers": [],
  // Let each user override these settings with their own file.
  "allowUserConfig": true
}

"""#
}

// MARK: - Pause state (per user)

struct PauseState {
    var paused = false
    var until: Date?

    var isActive: Bool {
        guard paused else { return false }
        if let until { return until > Date() }
        return true
    }

    static func load() -> PauseState {
        guard let data = FileManager.default.contents(atPath: App.stateFile),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return PauseState() }
        var s = PauseState()
        s.paused = dict["paused"] as? Bool ?? false
        if let t = dict["until"] as? Double { s.until = Date(timeIntervalSince1970: t) }
        return s
    }

    func save() throws {
        try FileManager.default.createDirectory(atPath: App.userDir, withIntermediateDirectories: true)
        if !paused {
            try? FileManager.default.removeItem(atPath: App.stateFile)
            return
        }
        var dict: [String: Any] = ["paused": true]
        if let until { dict["until"] = until.timeIntervalSince1970 }
        try JSONSerialization.data(withJSONObject: dict).write(to: URL(fileURLWithPath: App.stateFile))
    }
}
