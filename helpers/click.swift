// Minimal CGEvent click poster for the t-k4hf GUI acceptance run.
// peekaboo has --right but no middle-click, and wand's tome trigger IS
// middle-click, so the acceptance table can't be driven without this.
//
// usage: click <x> <y> [middle|right|left]
// Coords are CG GLOBAL (origin top-left, Y grows DOWN) — the same space
// wand's event tap reads from `CGEvent.location`.

import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3,
      let x = Double(args[1]), let y = Double(args[2]) else {
    FileHandle.standardError.write(
        "usage: click <x> <y> [middle|right|left]\n".data(using: .utf8)!)
    exit(2)
}
let button = args.count > 3 ? args[3] : "middle"
let pt = CGPoint(x: x, y: y)
let src = CGEventSource(stateID: .hidSystemState)

func post(_ type: CGEventType, _ mouseButton: CGMouseButton, _ number: Int64) {
    guard let e = CGEvent(mouseEventSource: src, mouseType: type,
                          mouseCursorPosition: pt, mouseButton: mouseButton)
    else {
        FileHandle.standardError.write("CGEvent create failed\n".data(using: .utf8)!)
        exit(3)
    }
    e.setIntegerValueField(.mouseEventButtonNumber, value: number)
    e.post(tap: .cghidEventTap)
}

// Move first: wand anchors on the cursor position at button-down, and a
// bare down at a point the cursor never visited is not the flow we want
// to verify.
if let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                      mouseCursorPosition: pt, mouseButton: .left) {
    move.post(tap: .cghidEventTap)
}
usleep(120_000)

switch button {
case "middle":
    post(.otherMouseDown, .center, 2)
    usleep(40_000)
    post(.otherMouseUp, .center, 2)
case "right":
    post(.rightMouseDown, .right, 1)
    usleep(40_000)
    post(.rightMouseUp, .right, 1)
case "left":
    post(.leftMouseDown, .left, 0)
    usleep(40_000)
    post(.leftMouseUp, .left, 0)
case "move":
    break   // the move above is the whole action
default:
    FileHandle.standardError.write("unknown button \(button)\n".data(using: .utf8)!)
    exit(2)
}
