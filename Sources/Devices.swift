import Foundation
import IOKit
import IOKit.hid

/// A HID device that reports a Generic Desktop / Mouse usage. Read straight from
/// the IOKit registry, so no Input Monitoring permission is needed.
struct PointingDevice {
    let name: String
    let transport: String
    let vendorID: Int
    let productID: Int
    let builtIn: Bool

    var id: String { String(format: "0x%04x:0x%04x", vendorID, productID) }
}

enum Devices {
    static func pointing() -> [PointingDevice] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOHIDDeviceKey), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }

        var result: [PointingDevice] = []
        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }
            guard isMouse(service) else { continue }
            let builtInValue = prop(service, kIOHIDBuiltInKey)
            result.append(PointingDevice(
                name: prop(service, kIOHIDProductKey) as? String ?? "(unnamed device)",
                transport: prop(service, kIOHIDTransportKey) as? String ?? "",
                vendorID: prop(service, kIOHIDVendorIDKey) as? Int ?? 0,
                productID: prop(service, kIOHIDProductIDKey) as? Int ?? 0,
                builtIn: (builtInValue as? Bool) ?? ((builtInValue as? Int) == 1)))
        }
        return result
    }

    /// nil = counts as a mouse; otherwise why it doesn't.
    static func exclusionReason(_ d: PointingDevice, _ config: Config) -> String? {
        if config.alwaysCountDevices.contains(where: { matches($0, d) }) { return nil }
        if let rule = config.ignoreDevices.first(where: { matches($0, d) }) { return "in ignoreDevices (\"\(rule)\")" }
        if d.builtIn { return "built-in" }
        let name = d.name.lowercased()
        if (name.contains("trackpad") || name.contains("touchpad")) && !config.externalTrackpadsCountAsMouse {
            return "trackpad"
        }
        let transport = d.transport.lowercased()
        if !config.transports.contains(where: { !$0.isEmpty && transport.contains($0.lowercased()) }) {
            return "connection type \"\(d.transport.isEmpty ? "none" : d.transport)\" isn't in transports"
        }
        return nil
    }

    static func connectedMice(_ config: Config) -> [PointingDevice] {
        var seen = Set<String>()
        // A single mouse often shows up as several HID interfaces; report it once.
        return pointing().filter { exclusionReason($0, config) == nil && seen.insert("\($0.id)|\($0.name)").inserted }
    }

    /// A rule is either "vendorID:productID" in hex or part of the device name.
    static func matches(_ rule: String, _ d: PointingDevice) -> Bool {
        let r = rule.trimmingCharacters(in: .whitespaces).lowercased()
        guard !r.isEmpty else { return false }
        let parts = r.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, let v = hex(parts[0]), let p = hex(parts[1]) {
            return v == d.vendorID && p == d.productID
        }
        return d.name.lowercased().contains(r)
    }

    private static func hex(_ s: Substring) -> Int? {
        let digits = s.hasPrefix("0x") ? s.dropFirst(2) : s
        return digits.isEmpty ? nil : Int(digits, radix: 16)
    }

    private static func isMouse(_ service: io_service_t) -> Bool {
        if let pairs = prop(service, kIOHIDDeviceUsagePairsKey) as? [[String: Any]] {
            return pairs.contains {
                ($0[kIOHIDDeviceUsagePageKey] as? Int) == kHIDPage_GenericDesktop &&
                ($0[kIOHIDDeviceUsageKey] as? Int) == kHIDUsage_GD_Mouse
            }
        }
        return (prop(service, kIOHIDPrimaryUsagePageKey) as? Int) == kHIDPage_GenericDesktop &&
               (prop(service, kIOHIDPrimaryUsageKey) as? Int) == kHIDUsage_GD_Mouse
    }

    private static func prop(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

// MARK: - Natural scrolling
// setSwipeScrollDirection is what System Settings uses: it applies immediately
// and saves com.apple.swipescrolldirection.

enum Scrolling {
    private typealias SetFn = @convention(c) (Bool) -> Void
    private typealias GetFn = @convention(c) () -> Bool

    private static let framework = dlopen("/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/Versions/A/PreferencePanesSupport", RTLD_LAZY)
    private static let setter = dlsym(framework, "setSwipeScrollDirection").map { unsafeBitCast($0, to: SetFn.self) }
    private static let getter = dlsym(framework, "swipeScrollDirection").map { unsafeBitCast($0, to: GetFn.self) }

    static var canApplyLive: Bool { setter != nil }

    static var natural: Bool {
        if let getter { return getter() }
        return CFPreferencesCopyValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool ?? true
    }

    static func set(natural on: Bool) {
        if let setter {
            setter(on)
            return
        }
        // Fallback if Apple ever removes the private function: save the preference.
        // It then only takes effect for newly opened apps / at next login.
        CFPreferencesSetValue("com.apple.swipescrolldirection" as CFString, on as CFBoolean,
                              kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        Log.error("Live switching isn't available on this macOS version; saved the preference instead")
    }
}
