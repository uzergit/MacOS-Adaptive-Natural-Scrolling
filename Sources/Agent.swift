import AppKit
import IOKit

/// The background watcher launchd runs in each user's session.
final class Agent {
    private var config = Config()
    private var pause = PauseState()
    private var configStamps: [Date?] = []
    private var pauseStamp: Date?
    private var wasActive = false
    private var pending: DispatchWorkItem?
    private var lastEnforce = Date.distantPast
    private var ioIterators: [io_iterator_t] = []
    private var loadedOnce = false

    private var userExcluded: Bool { config.excludedUsers.contains(NSUserName()) }
    private var active: Bool { config.enabled && !userExcluded && !pause.isActive }

    func start() -> Never {
        reloadConfig()
        pause = PauseState.load()
        pauseStamp = modificationDate(App.stateFile)
        wasActive = active
        Log.info("\(App.name) \(App.version) started for \(NSUserName())\(Scrolling.canApplyLive ? "" : " (live switching unavailable)")")
        logInactiveReason()

        watchDevices()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [unowned self] _ in
            if config.applyOnWake { schedule("woke from sleep") }
        }
        // Devices may have changed while another user was using the Mac.
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [unowned self] _ in
            schedule("switched back to this user")
        }

        let timer = Timer(timeInterval: 2, repeats: true) { [unowned self] _ in tick() }
        RunLoop.main.add(timer, forMode: .common)

        if config.applyAtLogin { schedule("startup", delay: 0) }
        RunLoop.main.run()
        exit(0)
    }

    // MARK: Device events

    private func watchDevices() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            Log.error("Couldn't watch for devices")
            exit(1)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { ctx, iter in
            drain(iter)
            Unmanaged<Agent>.fromOpaque(ctx!).takeUnretainedValue().schedule("devices changed")
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iter: io_iterator_t = 0
            IOServiceAddMatchingNotification(port, type, IOServiceMatching(kIOHIDDeviceKey), callback, context, &iter)
            drain(iter)  // arms the notification
            ioIterators.append(iter)
        }
    }

    /// Waits (connectDelay / disconnectDelay) and then applies. Re-checks when the
    /// timer fires, so a mouse that drops and comes back inside the window changes nothing.
    func schedule(_ reason: String, delay: Double? = nil) {
        guard active else { return }
        let mouse = !Devices.connectedMice(config).isEmpty
        // Small floor: one device appears as several HID interfaces in a burst.
        let wait = delay ?? max(mouse ? config.connectDelay : config.disconnectDelay, 0.2)
        pending?.cancel()
        let work = DispatchWorkItem { [unowned self] in
            pending = nil
            apply(reason)
        }
        pending = work
        Log.debug("\(reason); checking in \(wait)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    private func apply(_ reason: String) {
        guard active else { return }
        let mice = Devices.connectedMice(config)
        let want = mice.isEmpty ? config.naturalScrollingWithoutMouse : config.naturalScrollingWithMouse
        guard Scrolling.natural != want else {
            Log.debug("\(reason): already \(want ? "natural" : "standard")")
            return
        }
        Scrolling.set(natural: want)

        let names = mice.map(\.name).joined(separator: ", ")
        let summary = "Natural scrolling \(want ? "on" : "off") — " + (mice.isEmpty ? "no mouse connected" : names)
        Log.info("\(summary) (\(reason))")
        if config.notifications { notify(summary) }
        if !config.onChange.isEmpty { runHook(natural: want, mice: names) }
    }

    // MARK: Periodic checks: config/pause changes, pause expiry, enforce

    private func tick() {
        let stamps = [modificationDate(App.systemConfig), modificationDate(App.userConfig)]
        if stamps != configStamps {
            reloadConfig()
            Log.info("Settings reloaded")
            if active { schedule("settings changed", delay: 0.2) }
        }

        let stamp = modificationDate(App.stateFile)
        if stamp != pauseStamp {
            pauseStamp = stamp
            pause = PauseState.load()
        }

        let isActive = active
        if isActive != wasActive {
            wasActive = isActive
            if isActive {
                Log.info("Automatic switching resumed")
                schedule("resumed", delay: 0)
            } else {
                pending?.cancel()
                logInactiveReason()
            }
        }

        if isActive && config.enforce && pending == nil && Date().timeIntervalSince(lastEnforce) >= config.enforceInterval {
            lastEnforce = Date()
            apply("enforce")
        }
    }

    private func reloadConfig() {
        configStamps = [modificationDate(App.systemConfig), modificationDate(App.userConfig)]
        let loaded = ConfigLoader.load()
        for problem in loaded.problems { Log.error(problem) }
        if loaded.hasParseError && loadedOnce {
            Log.error("Keeping the previous settings until the file is fixed")
            return
        }
        config = loaded.config
        loadedOnce = true
        Log.level = config.logLevel
    }

    private func logInactiveReason() {
        if !config.enabled { Log.info("Automatic switching is turned off in settings (\"enabled\": false)") }
        else if userExcluded { Log.info("\(NSUserName()) is in excludedUsers; doing nothing") }
        else if pause.isActive {
            Log.info("Paused" + (pause.until.map { " until \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))" } ?? ""))
        }
    }

    // MARK: Feedback

    private func notify(_ text: String) {
        let script = "display notification \(appleScriptString(text)) with title \(appleScriptString(App.name))"
        DispatchQueue.global().async { run("/usr/bin/osascript", ["-e", script]) }
    }

    private func runHook(natural: Bool, mice: String) {
        var env = ProcessInfo.processInfo.environment
        env["ANS_NATURAL"] = natural ? "1" : "0"
        env["ANS_MOUSE_CONNECTED"] = mice.isEmpty ? "0" : "1"
        env["ANS_DEVICES"] = mice
        let command = config.onChange
        DispatchQueue.global().async {
            let result = run("/bin/sh", ["-c", command], env: env)
            if result.status != 0 { Log.error("onChange command exited with \(result.status): \(result.output.prefix(300))") }
        }
    }
}

private func drain(_ iter: io_iterator_t) {
    while case let s = IOIteratorNext(iter), s != 0 { IOObjectRelease(s) }
}

private func appleScriptString(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
