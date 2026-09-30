// WakeGuard: zorgt dat de MacBook (zonder scherm) vergrendeld niet wakker blijft, bijv. in je tas.
//
// Zolang hij vergrendeld én wakker is, krijgt hij een beperkte tijd om ontgrendeld te worden:
//  - net vergrendeld                         -> 10 s
//  - gewekt door de Touch ID-knop            -> 15 s (tijd om Touch ID nog eens te proberen)
//  - gewekt door toetsenbord/trackpad/klep   -> 3 s
// Daarna: slapen. Toetsen indrukken terwijl hij al wakker is verlengt dat niet.
// Alleen met een monitor aangesloten mag je je wachtwoord typen (reserve als Touch ID faalt):
// zolang er getypt wordt wacht hij dan, maximaal 45 s.
//
// Het ontwaken zelf blokkeren kan niet: dat regelt de T2-chip voordat macOS draait.
// Wekredenen: Touch ID-knop = EC.PowerButton, toetsen/trackpad = EC.KeyboardTouchpad.
import AppKit

func log(_ message: String) {
    FileHandle.standardError.write("\(Date()) \(message)\n".data(using: .utf8)!)
}

func isLocked() -> Bool {
    (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
}

func wakeReason() -> String {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    defer { IOObjectRelease(root) }
    return IORegistryEntryCreateCFProperty(root, "Wake Reason" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? String ?? ""
}

/// Seconden sinds de laatste toetsaanslag of trackpadbeweging
func hidIdleSeconds() -> Double {
    let hid = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    defer { IOObjectRelease(hid) }
    let ns = IORegistryEntryCreateCFProperty(hid, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? NSNumber
    return (ns?.doubleValue ?? .infinity) / 1_000_000_000
}

/// Het ingebouwde scherm is weg, dus elk beeldscherm is een externe monitor
func hasDisplay() -> Bool {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    return count > 0
}

/// Lopende periode "vergrendeld en wakker"; nil = niets te bewaken (bijv. na een onderhouds-wake)
var window: (since: Date, allowed: TimeInterval, why: String)?
var lastSleepRequest = Date.distantPast

func arm(_ allowed: TimeInterval, _ why: String) {
    window = (Date(), allowed, why)
}

func check() {
    guard let w = window else { return }
    guard isLocked() else { window = nil; return }   // ontgrendeld: klaar
    let elapsed = Date().timeIntervalSince(w.since)
    if hasDisplay(), hidIdleSeconds() < 3, elapsed < 45 { return }   // wachtwoord typen op de monitor
    guard elapsed >= w.allowed, Date().timeIntervalSince(lastSleepRequest) > 10 else { return }
    log("slapen: \(w.why), \(Int(elapsed)) s niet ontgrendeld")
    lastSleepRequest = Date()
    window = nil
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["sleepnow"]
    try? p.run()
}

DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"),
                                                    object: nil, queue: .main) { _ in
    arm(10, "vergrendeld")
}

// Alleen bij een volledige wake (niet bij onderhouds-wakes in het donker)
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                  object: nil, queue: .main) { _ in
    let reason = wakeReason()
    log("wakker: \(reason)")
    guard isLocked() else { return }
    arm(reason.contains("PowerButton") ? 15 : 3, "gewekt door \(reason)")
}

Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in check() }
if isLocked() { arm(10, "vergrendeld bij start") }
log("WakeGuard gestart")
RunLoop.main.run()
