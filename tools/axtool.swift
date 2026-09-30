// Verkenningshulp: axtool dump <bundle-id> [maxdiepte]
//                  axtool press <bundle-id> <description-of-titel-bevat>
import AppKit

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func str(_ el: AXUIElement, _ name: String) -> String {
    guard let v = attr(el, name) else { return "" }
    return "\(v)".replacingOccurrences(of: "\n", with: "⏎")
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func dump(_ el: AXUIElement, _ depth: Int, _ max: Int) {
    let role = str(el, kAXRoleAttribute)
    let d = str(el, kAXDescriptionAttribute), t = str(el, kAXTitleAttribute), v = str(el, kAXValueAttribute)
    let id = str(el, "AXIdentifier")
    if !(role == "AXGroup" && d.isEmpty && t.isEmpty && id.isEmpty) {
        print(String(repeating: " ", count: depth) + "\(role) d=\(d) t=\(t) v=\(v.prefix(40)) id=\(id)")
    }
    if depth < max { children(el).forEach { dump($0, depth + 1, max) } }
}

func find(_ el: AXUIElement, _ needle: String) -> AXUIElement? {
    for key in [kAXDescriptionAttribute, kAXTitleAttribute, "AXIdentifier"] where str(el, key).contains(needle) {
        return el
    }
    for c in children(el) { if let f = find(c, needle) { return f } }
    return nil
}

let args = CommandLine.arguments
guard args.count >= 3, let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).first else {
    print("gebruik: axtool dump|press <bundle-id> ..."); exit(1)
}
let root = AXUIElementCreateApplication(app.processIdentifier)
switch args[1] {
case "dump":
    dump(root, 0, args.count > 3 ? Int(args[3])! : 40)
case "press":
    guard let el = find(root, args[3]) else { print("niet gevonden"); exit(1) }
    print("druk:", AXUIElementPerformAction(el, kAXPressAction as CFString).rawValue)
default:
    print("onbekend commando")
}
