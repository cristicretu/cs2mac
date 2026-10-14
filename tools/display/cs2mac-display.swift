// cs2mac-display: make a display the main one (where Wine puts the game) for as long as CS2 runs.
// The change is made for this process only (CGConfigureOption.forAppOnly), so macOS restores the old
// arrangement when this exits, crash or not.
//
// CS2MAC_DISPLAY picks the display: "external" (default; the first non built-in, else the built-in)
// or "builtin". The display mode is left alone: on Apple Silicon macOS drives external monitors at
// their native timing and scales lower modes itself, keeping the aspect ratio, so a 4:3 mode would
// only add black bars. 4:3 stretched comes from Wine's emulated display modes instead (see cs2mac).
import CoreGraphics
import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("cs2mac-display: \(msg)\n".data(using: .utf8)!)
    exit(1)
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

if CGDisplayIsMain(target) == 0 {
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { fail("cannot configure displays") }
    // the display at (0,0) is the main one; line the others up to its left
    CGConfigureDisplayOrigin(config, target, 0, 0)
    var left: Int32 = 0
    for d in displays where d != target {
        left -= Int32(CGDisplayPixelsWide(d))
        CGConfigureDisplayOrigin(config, d, left, 0)
    }
    guard CGCompleteDisplayConfiguration(config, .forAppOnly) == .success else { fail("display change refused") }
}
let b = CGDisplayBounds(target)
print("display \(target) (\(Int(b.width))x\(Int(b.height))) is the main display until CS2 exits")
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
