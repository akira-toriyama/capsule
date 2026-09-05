// capsule-ax-dump — raw AXUIElement tree dump of one app's windows.
//
// WHY THIS EXISTS (measured 2026-08-04, facet SwiftUI tree): peekaboo
// 3.9.4 `inspect-ui` cannot descend into SwiftUI's accessibility
// containers — an NSHostingView subtree surfaces as a single opaque
// "system dialog" element with zero children, while the app's real AX
// tree (this walker, VoiceOver, Accessibility Inspector) has the whole
// hierarchy: AXGroup/AXHostingView → AXScrollArea →
// AXOpaqueProviderGroup/AXOpaqueProviderList → AXHeading rows. Every
// SwiftUI app in the family (facet's tree since PR #448, prism) is
// invisible to the peekaboo AX tier, so capsule ships its own walker.
//
// Compiled on the HOST by bake.sh (the guest is toolchain-free) and
// shipped to /Users/admin/capsule-helpers/capsule-ax-dump. It runs in
// the guest as an SSH child, inheriting the baked sshd-keygen-wrapper
// Accessibility grant.
//
//   usage: capsule-ax-dump <app-name|pid>
//   output: one line per element, indent = depth —
//     AXHeading title="…" value="…" desc="…" at (x,y) WxH
//   (only non-empty text attributes are printed; drivers grep for the
//   fixture's labels, quoted, e.g. `grep '"Alpha"'`)
//   exit: 0 dumped · 1 app not found or AX unreadable · 2 usage
//
// Menus and menu extras are deliberately NOT walked: verify drivers
// assert panel/window content, and the menu bar is ~50 lines of noise
// (measured: peekaboo's dump of facet was 53 menu items + 3 menus).

import AppKit
import ApplicationServices
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: capsule-ax-dump <app-name|pid>\n".utf8))
    exit(2)
}
let target = CommandLine.arguments[1]

// Name matching keeps peekaboo's loose `--app` contract (localized
// name, bundle name or executable, case-insensitive) so a driver passes
// the same argument to either tool.
let pid: pid_t
if let n = Int32(target) {
    pid = n
} else {
    let t = target.lowercased()
    let hit = NSWorkspace.shared.runningApplications.first {
        $0.localizedName?.lowercased() == t
            || $0.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() == t
            || $0.executableURL?.lastPathComponent.lowercased() == t
    }
    guard let hit else {
        FileHandle.standardError.write(Data("capsule-ax-dump: no running app matches '\(target)'\n".utf8))
        exit(1)
    }
    pid = hit.processIdentifier
}

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func frame(_ el: AXUIElement) -> String {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attr(el, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(el, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    // NaN-safe: an AX element can report a non-finite frame — SwiftUI's
    // AXOpaqueProviderList does exactly that before its first layout pass —
    // and `Int(CGFloat.nan)` TRAPS. The walker then died mid-dump with
    // SIGTRAP and a driver read the empty file as "the app has no AX tree"
    // (measured 2026-08-11 against facet's tree, twice).
    let f = { (v: CGFloat) -> String in v.isFinite ? String(Int(v)) : "NaN" }
    return "at (\(f(p.x)),\(f(p.y))) \(f(s.width))x\(f(s.height))"
}

// Runaway guards, not tuning knobs: a verify-sized panel is tens of
// elements; a walker that prints 20k lines is walking the wrong thing.
let maxDepth = 50
let maxElements = 5000
var printed = 0

func walk(_ el: AXUIElement, depth: Int) {
    guard depth <= maxDepth, printed < maxElements else { return }
    let role = (attr(el, kAXRoleAttribute) as? String) ?? "?"
    let sub = (attr(el, kAXSubroleAttribute) as? String).map { "/\($0)" } ?? ""
    var line = String(repeating: "  ", count: depth) + role + sub
    for (key, name) in [(kAXTitleAttribute, "title"), (kAXValueAttribute, "value"),
                        (kAXDescriptionAttribute, "desc")] {
        if let s = attr(el, key) as? String, !s.isEmpty { line += " \(name)=\"\(s)\"" }
    }
    print(line + " " + frame(el))
    printed += 1
    for kid in (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        walk(kid, depth: depth + 1)
    }
}

let app = AXUIElementCreateApplication(pid)
guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement] else {
    FileHandle.standardError.write(Data("capsule-ax-dump: pid \(pid) has no readable AXWindows (no AX grant, or no UI)\n".utf8))
    exit(1)
}
print("capsule-ax-dump pid=\(pid) windows=\(windows.count)")
for w in windows { walk(w, depth: 0) }
