import AppKit

// MARK: - Private DFRFoundation-functies (Control Strip)

private let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

private func setControlStripPresence(_ id: NSTouchBarItem.Identifier, _ present: Bool) {
    typealias Fn = @convention(c) (CFString, Bool) -> Void
    guard let sym = dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier") else { return }
    unsafeBitCast(sym, to: Fn.self)(id.rawValue as CFString, present)
}

// Private NSTouchBar/NSTouchBarItem-klassemethodes, via de runtime aangeroepen
private func callClass(_ cls: AnyClass, _ sel: String, _ obj: AnyObject) {
    typealias Fn = @convention(c) (AnyClass, Selector, AnyObject) -> Void
    let s = NSSelectorFromString(sel)
    guard let m = class_getClassMethod(cls, s) else { return }
    unsafeBitCast(method_getImplementation(m), to: Fn.self)(cls, s, obj)
}

private func presentSystemModal(_ bar: NSTouchBar, placement: Int64, tray: NSTouchBarItem.Identifier) {
    typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString) -> Void
    let s = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
    guard let m = class_getClassMethod(NSTouchBar.self, s) else { return }
    unsafeBitCast(method_getImplementation(m), to: Fn.self)(NSTouchBar.self, s, bar, placement, tray.rawValue as NSString)
}

// MARK: - Apparaten

struct Device: Hashable {
    enum Kind { case airplay, chromecast }
    let kind: Kind
    let serviceName: String   // Bonjour-naam; AirPlay gebruikt die ook in Bedieningscentrum
    let name: String          // weergavenaam
}

/// Zoekt AirPlay- en Chromecast-apparaten en houdt alleen apparaten over die een scherm kunnen tonen.
final class Discovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private var browsers: [NetServiceBrowser] = []
    private var pending: [NetService] = []
    private var found: [String: Device] = [:]   // sleutel: type + servicenaam
    var onChange: (() -> Void)?

    func start() {
        for type in ["_airplay._tcp.", "_googlecast._tcp."] {
            let b = NetServiceBrowser()
            b.delegate = self
            b.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(b)
        }
    }

    var sorted: [Device] {
        found.values.filter { !Mirroring.unsupported.contains($0.name) }.sorted { ($0.kind == .airplay ? 0 : 1, $0.name) < ($1.kind == .airplay ? 0 : 1, $1.name) }
    }

    private func key(_ s: NetService) -> String { s.type + s.name }

    func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
        s.delegate = self
        pending.append(s)
        s.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ b: NetServiceBrowser, didRemove s: NetService, moreComing: Bool) {
        if found.removeValue(forKey: key(s)) != nil { onChange?() }
    }

    func netServiceDidResolveAddress(_ s: NetService) {
        pending.removeAll { $0 === s }
        let txt = NetService.dictionary(fromTXTRecord: s.txtRecordData() ?? Data())
            .mapValues { String(decoding: $0, as: UTF8.self) }
        if s.type.hasPrefix("_airplay") {
            // features bit 7 = schermsynchronisatie (Apple TV ja, HomePod nee)
            let features = txt["features"]?.split(separator: ",").first.flatMap { UInt64($0.dropFirst(2), radix: 16) } ?? 0
            guard features & 0x80 != 0 else { return }
            let name = s.name.replacingOccurrences(of: "\u{00AD}", with: "") // zacht afbreekstreepje
            found[key(s)] = Device(kind: .airplay, serviceName: s.name, name: name)
        } else {
            // ca bit 0 = video-uitvoer (tv ja, Google Home Mini nee)
            guard let ca = txt["ca"].flatMap({ Int($0) }), ca & 1 != 0 else { return }
            found[key(s)] = Device(kind: .chromecast, serviceName: s.name, name: txt["fn"] ?? s.name)
        }
        onChange?()
    }

    func netService(_ s: NetService, didNotResolve errorDict: [String: NSNumber]) {
        pending.removeAll { $0 === s }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    static let trayID = NSTouchBarItem.Identifier("nl.atmin.castbar.tray")
    static let listID = NSTouchBarItem.Identifier("nl.atmin.castbar.list")

    let discovery = Discovery()
    let mirroring = Mirroring()
    var trayItem: NSCustomTouchBarItem!
    var bar: NSTouchBar!
    let stack = NSStackView()
    var isPresented = false
    /// Apparaat waarmee nu verbonden/gestopt wordt (tikken wordt dan genegeerd)
    var busy: Device?
    var status: String?
    var lastAutoShowCondition = false

    func applicationDidFinishLaunching(_ note: Notification) {
        let trusted = Mirroring.ensureAccess()
        FileHandle.standardError.write("\(Date()) CastBar gestart, toegankelijkheid: \(trusted)\n".data(using: .utf8)!)
        stack.orientation = .horizontal
        stack.spacing = 8

        trayItem = NSCustomTouchBarItem(identifier: Self.trayID)
        // Atnovix-logo (zwarte A wit gemaakt voor de zwarte Touch Bar), anders het AirPlay-symbool
        let logo = Bundle.main.image(forResource: "atnovix")
            ?? NSImage(systemSymbolName: "airplayvideo", accessibilityDescription: nil)!
        logo.size = NSSize(width: 22, height: 22)
        logo.accessibilityDescription = "Casten"
        let trayButton = NSButton(image: logo, target: self, action: #selector(toggle))
        trayButton.imageScaling = .scaleProportionallyDown
        // Claude-logo rechts naast het Atnovix-logo: opent Claude Code in Terminal.
        // Zelfde item, want de Control Strip toont maar één systeemknop per app.
        // Het vakje in de Control Strip is maar één knop breed: randloze knoppen van 24 pt passen er samen in.
        let claudeButton = NSButton(image: ClaudeLauncher.logo(), target: self, action: #selector(openClaude))
        claudeButton.imageScaling = .scaleProportionallyDown
        for b in [trayButton, claudeButton] {
            b.isBordered = false
            b.widthAnchor.constraint(equalToConstant: 24).isActive = true
        }
        let trayStack = NSStackView(views: [trayButton, claudeButton])
        trayStack.spacing = 4
        trayItem.view = trayStack
        showTrayItem()

        bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.listID]

        discovery.onChange = { [weak self] in self?.refresh() }
        discovery.start()

        NotificationCenter.default.addObserver(self, selector: #selector(checkAutoShow),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.mirroring.pollState()
            // Na uitklappen/inklappen of een herstart van de Control Strip is het icoon weg
            if self?.isPresented == false,
               Mirroring.controlStripMissesItem(named: "Casten"), Mirroring.controlStripMissesItem(named: "Claude") {
                self?.showTrayItem()
            }
            self?.refresh()
            self?.checkAutoShow()
        }
        // Even wachten tot de eerste apparaten binnen zijn
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.checkAutoShow() }
    }

    // Geen externe monitor en niks verbonden -> apparatenlijst tonen
    @objc func checkAutoShow() {
        let externalMonitor = NSScreen.screens.contains { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            return !mirroring.isAirPlayDisplay(id)
        }
        let condition = !externalMonitor && mirroring.connected == nil
        if condition && !lastAutoShowCondition { present() }
        lastAutoShowCondition = condition
    }

    // De lijst heeft zelf een sluitknop; het systeem kan hem ook sluiten zonder dat wij het merken
    @objc func toggle() { present() }

    @objc func openClaude() { ClaudeLauncher.open() }

    /// macOS haalt het icoon uit de Control Strip zodra de lijst gesloten wordt; zet het terug.
    func showTrayItem() {
        callClass(NSTouchBarItem.self, "removeSystemTrayItem:", trayItem)
        callClass(NSTouchBarItem.self, "addSystemTrayItem:", trayItem)
        setControlStripPresence(Self.trayID, true)
    }

    func present() {
        refresh()
        presentSystemModal(bar, placement: 1, tray: Self.trayID)
        isPresented = true
    }

    @objc func dismiss() {
        callClass(NSTouchBar.self, "minimizeSystemModalTouchBar:", bar)
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showTrayItem() }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard id == Self.listID else { return nil }
        let item = NSCustomTouchBarItem(identifier: id)
        let scroll = NSScrollView()
        scroll.documentView = stack
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        item.view = scroll
        return item
    }

    func refresh() {
        var views: [NSView] = []

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Sluiten")!,
                             target: self, action: #selector(dismiss))
        views.append(close)

        if let connected = mirroring.connected {
            let stop = NSButton(title: "Stop \(connected.name)", target: self, action: #selector(stopTapped))
            stop.bezelColor = .systemRed
            views.append(stop)
        }

        if let status { views.append(NSTextField(labelWithString: status)) }

        let devices = discovery.sorted
        if devices.isEmpty { views.append(NSTextField(labelWithString: "Zoeken naar schermen…")) }
        for (i, d) in devices.enumerated() {
            let b = NSButton(title: d.name, target: self, action: #selector(deviceTapped(_:)))
            b.tag = i
            b.image = NSImage(systemSymbolName: d.kind == .airplay ? "airplayvideo" : "tv", accessibilityDescription: nil)
            b.imagePosition = .imageLeading
            if d == busy { b.bezelColor = .systemOrange }
            else if d == mirroring.connected { b.bezelColor = .systemBlue }
            views.append(b)
        }

        stack.setViews(views, in: .leading)
        stack.frame.size = stack.fittingSize
        stack.frame.size.height = 30
    }

    @objc func deviceTapped(_ sender: NSButton) {
        let devices = discovery.sorted
        guard sender.tag < devices.count, busy == nil else { return }
        let d = devices[sender.tag]
        // Nogmaals tikken op het verbonden apparaat stopt het casten
        if d == mirroring.connected { return stopTapped() }
        busy = d
        show("Verbinden met \(d.name)…")
        mirroring.connect(d) { [weak self] error in
            self?.busy = nil
            self?.show(error)
            if error == nil { self?.dismiss() }
        }
    }

    @objc func stopTapped() {
        guard busy == nil, let d = mirroring.connected else { return }
        busy = d
        show("Stoppen…")
        mirroring.stop { [weak self] error in
            self?.busy = nil
            self?.show(error)
        }
    }

    func show(_ message: String?) {
        status = message
        refresh()
        if message != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                if self?.status == message { self?.status = nil; self?.refresh() }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
