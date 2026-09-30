import AppKit

// MARK: - Toegankelijkheid-hulpjes

private func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

private func string(_ el: AXUIElement, _ name: String) -> String {
    (attr(el, name) as? String) ?? ""
}

private func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

/// Diepte-eerst zoeken naar het eerste element dat aan `match` voldoet.
private func find(_ el: AXUIElement, depth: Int = 0, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    if match(el) { return el }
    guard depth < 40 else { return nil }
    for c in children(el) {
        if let f = find(c, depth: depth + 1, match) { return f }
    }
    return nil
}

/// Herhaalt `block` tot er iets uitkomt of de tijd om is.
private func waitFor<T>(timeout: TimeInterval = 5, _ block: () -> T?) -> T? {
    let end = Date().addingTimeInterval(timeout)
    repeat {
        if let v = block() { return v }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < end
    return nil
}

private func press(_ el: AXUIElement) {
    AXUIElementPerformAction(el, kAXPressAction as CFString)
}

private func app(_ bundleID: String) -> AXUIElement? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first.map {
        let el = AXUIElementCreateApplication($0.processIdentifier)
        // Niet blijven hangen als de app een modaal venster/menu openhoudt
        AXUIElementSetMessagingTimeout(el, 1.5)
        return el
    }
}

private func withoutSoftHyphen(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{00AD}", with: "")
}

enum CastError: Error, CustomStringConvertible {
    case noAccess, notFound(String), noChrome, chromeScreenCapture, unsupported(String)
    var description: String {
        switch self {
        case .noAccess: return "Geef CastBar toegang bij Toegankelijkheid"
        case .notFound(let what): return "\(what) niet gevonden"
        case .noChrome: return "Google Chrome niet gevonden"
        case .chromeScreenCapture: return "Mislukt: zet Chrome aan bij Schermopname"
        case .unsupported(let name): return "\(name) kan geen scherm ontvangen"
        }
    }
}

// MARK: - Mirroring

/// Start en stopt schermsynchronisatie:
///  - AirPlay via het menu "Synchrone weergave" van Bedieningscentrum
///  - Chromecast via Chrome: Weergave > Casten… > Bronnen > Scherm casten
final class Mirroring {
    /// Onthouden over herstarts heen (anders ontbreekt de Stop-knop na een herstart van CastBar)
    private(set) var connected: Device? = Mirroring.loadConnected() {
        didSet {
            let d = UserDefaults.standard
            if let c = connected {
                d.set(["kind": c.kind == .airplay ? "airplay" : "chromecast", "service": c.serviceName, "name": c.name],
                      forKey: "connected")
            } else {
                d.removeObject(forKey: "connected")
            }
        }
    }

    private static func loadConnected() -> Device? {
        guard let c = UserDefaults.standard.dictionary(forKey: "connected") as? [String: String],
              let service = c["service"], let name = c["name"] else { return nil }
        return Device(kind: c["kind"] == "airplay" ? .airplay : .chromecast, serviceName: service, name: name)
    }
    /// Het beeldscherm dat macOS aanmaakt voor een AirPlay-verbinding
    private var airplayDisplay: CGDirectDisplayID?
    private let queue = DispatchQueue(label: "nl.atmin.castbar.mirroring")

    static func ensureAccess() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    /// true als de ingeklapte Control Strip zichtbaar is maar ons icoon er niet in staat.
    /// Uitgeklapt heeft de strip geen (leesbare) knoppen; dan niets doen, anders klapt hij in.
    static func controlStripMissesItem(named name: String) -> Bool {
        guard AXIsProcessTrusted(), let strip = app("com.apple.controlstrip"),
              let row = children(strip).first else { return false }
        let buttons = children(row).flatMap { [$0] + children($0) + children($0).flatMap(children) }
            .filter { string($0, kAXRoleAttribute) == "AXButton" }
        return !buttons.isEmpty && !buttons.contains { string($0, kAXDescriptionAttribute) == name }
    }

    func isAirPlayDisplay(_ id: CGDirectDisplayID) -> Bool { id == airplayDisplay }

    /// Merkt op als een AirPlay-verbinding van buitenaf is verbroken (tv uit, via menubalk gestopt).
    func pollState() {
        guard connected?.kind == .airplay, let display = airplayDisplay else { return }
        if !onlineDisplays().contains(display) {
            connected = nil
            airplayDisplay = nil
        }
    }

    /// Apparaten die alleen "specifieke videosites" afspelen (geen schermsynchronisatie)
    static var unsupported: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "unsupported") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "unsupported") }
    }

    func connect(_ device: Device, completion: @escaping (String?) -> Void) {
        run(completion) { [self] in
            if let current = connected, current != device { try toggle(current, on: false) }
            let before = onlineDisplays()
            try toggle(device, on: true)
            connected = device
            if device.kind == .airplay {
                airplayDisplay = waitFor(timeout: 10) { onlineDisplays().subtracting(before).first }
            }
        }
    }

    func stop(completion: @escaping (String?) -> Void) {
        guard let device = connected else { return completion(nil) }
        run(completion) { [self] in
            try toggle(device, on: false)
            connected = nil
            airplayDisplay = nil
        }
    }

    private func run(_ completion: @escaping (String?) -> Void, _ work: @escaping () throws -> Void) {
        queue.async {
            var message: String?
            do {
                guard AXIsProcessTrusted() else { throw CastError.noAccess }
                try work()
            } catch {
                message = "\(error)"
                self.log("fout: \(error)")
                if case CastError.unsupported(let name) = error { Mirroring.unsupported.insert(name) }
            }
            DispatchQueue.main.async { completion(message) }
        }
    }

    private func toggle(_ device: Device, on: Bool) throws {
        switch device.kind {
        case .airplay: try airplay(device, on: on)
        case .chromecast: try chromecast(device, on: on)
        }
    }

    private func onlineDisplays() -> Set<CGDirectDisplayID> {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return Set(ids.prefix(Int(count)))
    }

    // MARK: AirPlay

    private func airplay(_ device: Device, on: Bool) throws {
        guard let cc = app("com.apple.controlcenter") else { throw CastError.notFound("Bedieningscentrum") }
        let extras = attr(cc, "AXExtrasMenuBar") as! AXUIElement? ?? cc
        guard let item = find(extras, { string($0, "AXIdentifier") == "com.apple.menuextra.screen-mirroring" }) else {
            throw CastError.notFound("Synchrone weergave in menubalk")
        }
        press(item)
        defer { closeMenu(item) }

        let id = withoutSoftHyphen("screen-mirroring-device-\(device.serviceName)")
        guard let toggle = waitFor({ find(cc) { withoutSoftHyphen(string($0, "AXIdentifier")) == id } }) else {
            throw CastError.notFound(device.name)
        }
        let isOn = (attr(toggle, kAXValueAttribute) as? Int ?? 0) == 1
        if isOn != on { press(toggle) }
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func closeMenu(_ item: AXUIElement) {
        // Escape sluit het menu van Bedieningscentrum
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Chromecast (via Chrome)

    private static let chromeID = "com.google.Chrome"

    private func chromecast(_ device: Device, on: Bool) throws {
        let chrome = try launchChrome()
        var dialog = try openCastDialog(chrome)
        log("cast-venster: \(string(dialog, kAXTitleAttribute))")

        if !on {
            // Tijdens het casten staat er een knop "<Tabblad|Scherm> casten naar <naam> stoppen"
            guard let stop = find(dialog, {
                string($0, kAXRoleAttribute) == "AXButton"
                    && string($0, kAXDescriptionAttribute).hasSuffix("naar \(device.name) stoppen")
            }) else {
                // Al gestopt (tv uit, of via Chrome zelf); alleen de status opruimen
                log("\(device.name) castte al niet meer")
                closeAndHide(dialog)
                return
            }
            press(stop)
            log("gestopt: \(device.name)")
            closeAndHide(dialog)
            return
        }

        // Bron op "Scherm casten" zetten (standaard staat hij op "Tabblad casten")
        if string(dialog, kAXTitleAttribute) != "Scherm casten" {
            guard let sources = find(dialog, { string($0, kAXDescriptionAttribute) == "Bronnen" }) else {
                throw CastError.notFound("Knop Bronnen")
            }
            press(sources)
            guard let screen = waitFor({ find(chrome) {
                string($0, kAXRoleAttribute) == "AXMenuItem" && string($0, kAXTitleAttribute) == "Scherm casten"
            } }) else { throw CastError.notFound("Scherm casten in Bronnen") }
            press(screen)
            // Pas verder als Chrome de bron echt heeft omgezet, anders cast hij alleen een tabblad
            guard let updated = waitFor({ children(chrome).first {
                string($0, kAXRoleAttribute) == "AXWindow" && string($0, kAXTitleAttribute) == "Scherm casten"
            } }) else { throw CastError.notFound("Bron Scherm casten (bleef op tabblad)") }
            dialog = updated
            log("bron: Scherm casten")
        }

        // Apparaatknoppen heten "<naam>\n<status>"
        guard let button = waitFor({ find(dialog) {
            string($0, kAXRoleAttribute) == "AXButton"
                && string($0, kAXDescriptionAttribute).hasPrefix(device.name + "\n")
        } }) else { throw CastError.notFound(device.name) }
        if string(button, kAXDescriptionAttribute).contains("specifieke videosites") {
            closeAndHide(dialog)
            throw CastError.unsupported(device.name)
        }
        press(button)

        // Chrome vraagt daarna "Je volledige scherm delen": Volledig scherm kiezen, geluid mee, Delen
        let isStopButton: (AXUIElement) -> Bool = {
            string($0, kAXDescriptionAttribute).hasSuffix("naar \(device.name) stoppen")
        }
        let picker: () -> AXUIElement? = {
            children(chrome).first { string($0, kAXTitleAttribute).hasPrefix("Je volledige scherm delen") }
        }
        _ = waitFor(timeout: 10) { () -> AXUIElement? in picker() ?? find(chrome, isStopButton) }
        if let window = picker() {
            log("deelvenster van Chrome")
            // Het schermvoorbeeld laadt even; zonder selectie doet Delen niets
            if let screen = waitFor({ find(window) {
                string($0, kAXRoleAttribute) == "AXButton" && string($0, kAXDescriptionAttribute) == "Volledig scherm"
            } }) {
                press(screen)
            }
            Thread.sleep(forTimeInterval: 0.5)
            if let audio = find(window, { string($0, kAXRoleAttribute) == "AXCheckBox" }),
               (attr(audio, kAXValueAttribute) as? Int) == 0 {
                press(audio)
            }
            // Delen indrukken tot het venster dicht is
            let shared = waitFor(timeout: 8) { () -> Bool? in
                if picker() == nil { return true }
                if let share = find(window, { string($0, kAXRoleAttribute) == "AXButton"
                                              && string($0, kAXDescriptionAttribute) == "Delen" }),
                   (attr(share, kAXEnabledAttribute) as? Bool) == true {
                    press(share)
                    Thread.sleep(forTimeInterval: 0.8)
                }
                return nil
            }
            if shared == nil {
                if let cancel = find(window, { string($0, kAXDescriptionAttribute) == "Annuleren" }) { press(cancel) }
                throw CastError.notFound("Knop Delen (deelvenster bleef open)")
            }
            log("gedeeld: volledig scherm")
        }

        // Gelukt als er een stopknop verschijnt; zonder schermopname-rechten gebeurt er niets
        var started = waitFor(timeout: 6) { find(chrome, isStopButton) }
        if started == nil, let reopened = try? openCastDialog(chrome) {
            // Het cast-venster kan dicht zijn gegaan door het deelvenster; opnieuw kijken
            dialog = reopened
            started = waitFor(timeout: 3) { find(dialog, isStopButton) }
        }
        closeAndHide(dialog)
        guard started != nil else {
            log("casten naar \(device.name) niet gestart")
            throw CastError.chromeScreenCapture
        }
        log("casten gestart naar \(device.name)")
    }

    private func closeAndHide(_ dialog: AXUIElement) {
        if let close = find(dialog, { string($0, kAXDescriptionAttribute) == "Sluiten" }) { press(close) }
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeID).first?.hide()
    }

    private func log(_ message: String) {
        FileHandle.standardError.write("\(Date()) \(message)\n".data(using: .utf8)!)
    }

    private func launchChrome() throws -> AXUIElement {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.chromeID) else {
            throw CastError.noChrome
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeID).isEmpty {
            let done = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in done.signal() }
            done.wait()
        }
        guard let chrome = waitFor(timeout: 10, { app(Self.chromeID) }) else { throw CastError.noChrome }
        // Casten werkt alleen met een open browservenster
        if (attr(chrome, kAXWindowsAttribute) as? [AXUIElement] ?? []).isEmpty {
            try menuItem(chrome, "Archief", "Nieuw venster")
            _ = waitFor { (attr(chrome, kAXWindowsAttribute) as? [AXUIElement])?.first }
        }
        return chrome
    }

    /// Het cast-venster van Chrome sluit zichzelf zodra Chrome niet meer vooraan staat.
    private func bringToFront(_ chrome: AXUIElement) {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeID).first?.unhide()
        // Via LaunchServices activeren; een app op de achtergrond mag dat sinds macOS 14 niet meer direct
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.chromeID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        AXUIElementSetAttributeValue(chrome, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let front = waitFor(timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.chromeID ? true : nil
        }
        log("chrome vooraan: \(front ?? false), voorste app: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")")
    }

    private func openCastDialog(_ chrome: AXUIElement) throws -> AXUIElement {
        bringToFront(chrome)
        let isCastWindow: (AXUIElement) -> Bool = {
            string($0, kAXRoleAttribute) == "AXWindow" && string($0, kAXTitleAttribute).hasSuffix(" casten")
        }
        if let open = children(chrome).first(where: isCastWindow) { return open }
        try menuItem(chrome, "Weergave", "Casten…")
        log("menu Casten… ingedrukt, vensters: \(children(chrome).map { string($0, kAXTitleAttribute) })")
        guard let dialog = waitFor(timeout: 8, { children(chrome).first(where: isCastWindow) }) else {
            throw CastError.notFound("Cast-venster van Chrome")
        }
        return dialog
    }

    private func menuItem(_ app: AXUIElement, _ menu: String, _ item: String) throws {
        guard let bar = attr(app, kAXMenuBarAttribute) as! AXUIElement?,
              let top = children(bar).first(where: { string($0, kAXTitleAttribute) == menu }),
              let el = find(top, { string($0, kAXRoleAttribute) == "AXMenuItem" && string($0, kAXTitleAttribute) == item })
        else { throw CastError.notFound("Menu \(menu) > \(item)") }
        press(el)
    }
}
