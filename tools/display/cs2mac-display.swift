// cs2mac-display WxH: switch a display to the WxH mode and make it the main display (where Wine puts
// the game) for as long as CS2 runs. The change is made for this process only
// (CGConfigureOption.forAppOnly), so macOS restores the old mode and arrangement when this exits,
// crash or not.
//
// CS2MAC_DISPLAY picks the display: "external" (default; the first non built-in, else the built-in)
// or "builtin". Only 1x modes (pixels == points) are used, so the game renders at exactly WxH and the
// monitor scales it to the panel: 4:3 stretched on a 16:9 monitor set to full-screen aspect.
import CoreGraphics
import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("cs2mac-display: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 2, let x = args[1].firstIndex(of: "x"),
      let w = Int(args[1][..<x]), let h = Int(args[1][args[1].index(after: x)...]) else {
    fail("usage: cs2mac-display WxH")
}

var count: UInt32 = 0
var ids = [CGDirectDisplayID](repeating: 0, count: 16)
guard CGGetActiveDisplayList(16, &ids, &count) == .success else { fail("cannot list displays") }
let displays = Array(ids.prefix(Int(count)))
let external = displays.first { CGDisplayIsBuiltin($0) == 0 }
let builtin = displays.first { CGDisplayIsBuiltin($0) != 0 }
let target: CGDirectDisplayID
switch ProcessInfo.processInfo.environment["CS2MAC_DISPLAY"] ?? "external" {
case "external": target = external ?? CGMainDisplayID()
case "builtin": guard let b = builtin else { fail("no built-in display") }; target = b
case let other: fail("CS2MAC_DISPLAY=\(other): use external or builtin")
}

let opts = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(target, opts) as? [CGDisplayMode] ?? [])
    .filter { $0.width == w && $0.height == h && $0.pixelWidth == w && $0.pixelHeight == h && $0.isUsableForDesktopGUI() }
guard let mode = modes.max(by: { $0.refreshRate < $1.refreshRate }) else {
    let sizes = Set((CGDisplayCopyAllDisplayModes(target, opts) as? [CGDisplayMode] ?? [])
        .filter { $0.pixelWidth == $0.width && $0.isUsableForDesktopGUI() }.map { "\($0.width)x\($0.height)" })
    fail("display \(target) has no \(w)x\(h) mode; it has: \(sizes.sorted().joined(separator: " "))")
}

var config: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&config) == .success else { fail("cannot configure displays") }
CGConfigureDisplayWithDisplayMode(config, target, mode, nil)
if CGDisplayIsMain(target) == 0 {
    // the display at (0,0) is the main one; line the others up to its left
    CGConfigureDisplayOrigin(config, target, 0, 0)
    var left: Int32 = 0
    for d in displays where d != target {
        left -= Int32(CGDisplayPixelsWide(d))
        CGConfigureDisplayOrigin(config, d, left, 0)
    }
}
guard CGCompleteDisplayConfiguration(config, .forAppOnly) == .success else { fail("display change refused") }
print("display \(target) at \(w)x\(h) \(Int(mode.refreshRate)) Hz until CS2 exits")
fflush(stdout)

signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }

func cs2Running() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-f", "cs2\\.exe"]
    p.standardOutput = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus == 0
}

// wait up to two minutes for CS2 to start, then until it exits
var waited = 0
while !cs2Running() {
    if waited >= 120 { fail("CS2 did not start; display restored") }
    sleep(1); waited += 1
}
while cs2Running() { sleep(2) }
