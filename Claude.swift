import AppKit

/// Claude-knop in de Control Strip: opent Claude Code in Terminal, in de map van het voorste Finder-venster.
enum ClaudeLauncher {
    /// Claude-"spark" (oranje stervorm), getekend zodat er geen afbeelding nodig is
    static func logo() -> NSImage {
        let img = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            let lengths: [CGFloat] = [10, 8.5, 10.5, 9, 10, 8, 10.5, 9.5, 10, 8.5, 10.5, 9]
            let path = NSBezierPath()
            for (i, len) in lengths.enumerated() {
                let a = CGFloat(i) / CGFloat(lengths.count) * 2 * .pi + 0.13
                let perp = a + .pi / 2
                let w: CGFloat = 1.3, tip: CGFloat = 0.6
                func pt(_ r: CGFloat, _ off: CGFloat) -> NSPoint {
                    NSPoint(x: c.x + cos(a) * r + cos(perp) * off, y: c.y + sin(a) * r + sin(perp) * off)
                }
                path.move(to: pt(0, w))
                path.line(to: pt(len, tip))
                path.line(to: pt(len, -tip))
                path.line(to: pt(0, -w))
                path.close()
            }
            NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1).setFill()  // #D97757
            path.fill()
            return true
        }
        img.accessibilityDescription = "Claude"
        return img
    }

    static func open() {
        let dir = finderFolder() ?? FileManager.default.homeDirectoryForCurrentUser.path
        let claude = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
        // .command-bestand via Terminal openen: geen Automation-recht voor Terminal nodig
        let script = """
        #!/bin/zsh -l
        cd -- \(quote(dir)) && clear
        \(quote(claude))
        exec zsh -l
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-\(UUID().uuidString).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        // Opruimen nadat Terminal het heeft ingelezen
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { try? FileManager.default.removeItem(at: url) }
    }

    /// Map van het voorste Finder-venster als Finder vooraan staat (zonder venster: het bureaublad), anders nil
    private static func finderFolder() -> String? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return nil }
        let src = #"tell application "Finder" to return POSIX path of (insertion location as alias)"#
        var err: NSDictionary?
        let path = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue
        if let err { FileHandle.standardError.write("\(Date()) Finder-map ophalen mislukt: \(err)\n".data(using: .utf8)!) }
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    private static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
