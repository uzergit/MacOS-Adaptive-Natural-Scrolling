import Foundation
import os

enum App {
    static let name = "Adaptive Natural Scrolling"
    static let version = "1.0.0"
    static let label = "io.github.uzergit.adaptive-natural-scrolling"
    static let repo = "https://github.com/uzergit/MacOS-Adaptive-Natural-Scrolling"

    static let systemDir = "/Library/Application Support/AdaptiveNaturalScrolling"
    static let systemConfig = systemDir + "/config.json"
    static let uninstaller = systemDir + "/uninstall.sh"

    static var userDir: String { NSHomeDirectory() + "/Library/Application Support/AdaptiveNaturalScrolling" }
    static var userConfig: String { userDir + "/config.json" }
    static var stateFile: String { userDir + "/state.json" }
}

// MARK: - Logging (unified log, plus stderr when run in a terminal)

enum LogLevel: String { case quiet, info, debug }

enum Log {
    static var level: LogLevel = .info
    private static let logger = Logger(subsystem: App.label, category: "agent")
    private static let toTerminal = isatty(STDERR_FILENO) == 1

    static func info(_ message: String) {
        guard level != .quiet else { return }
        emit(message)
    }

    static func debug(_ message: String) {
        guard level == .debug else { return }
        emit(message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        if toTerminal { FileHandle.standardError.write(Data("error: \(message)\n".utf8)) }
    }

    private static func emit(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        if toTerminal { FileHandle.standardError.write(Data("\(message)\n".utf8)) }
    }
}

// MARK: - Small helpers

@discardableResult
func run(_ path: String, _ args: [String], capture: Bool = true, env: [String: String]? = nil) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    if let env { p.environment = env }
    let pipe = Pipe()
    if capture {
        p.standardOutput = pipe
        p.standardError = pipe
    }
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func modificationDate(_ path: String) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
}
