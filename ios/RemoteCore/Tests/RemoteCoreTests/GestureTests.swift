import Foundation
@testable import RemoteCore

/// O tato do comando: os mesmos números que o Android (contracts/gestures.json).
extension CoreTests {
    static func gestures() throws {
        let g = try Contracts.object("gestures.json")
        let touch = g["touch"] as? [String: Any] ?? [:]
        try expect(touch["stepDistance"] as? Int, Gestures.Touch.stepDistance)
        try expect(touch["holdMs"] as? Int, Gestures.Touch.holdMs)
        try expect(touch["repeatAfterMs"] as? Int, Gestures.Touch.repeatAfterMs)
        try expect(touch["repeatStartMs"] as? Int, Gestures.Touch.repeatStartMs)
        try expect(touch["repeatMinMs"] as? Int, Gestures.Touch.repeatMinMs)
        try expect(touch["repeatStepMs"] as? Int, Gestures.Touch.repeatStepMs)
        let dpad = g["dpad"] as? [String: Any] ?? [:]
        try expect(dpad["centreHoldMs"] as? Int, Gestures.Dpad.centreHoldMs)
        try expect(dpad["repeatAfterMs"] as? Int, Gestures.Dpad.repeatAfterMs)
        try expect(dpad["repeatStartMs"] as? Int, Gestures.Dpad.repeatStartMs)
        try expect(dpad["repeatMinMs"] as? Int, Gestures.Dpad.repeatMinMs)
        try expect(dpad["repeatStepMs"] as? Int, Gestures.Dpad.repeatStepMs)
        try expect(dpad["okRadius"] as? Double, Gestures.Dpad.okRadius)
        try expect(dpad["litMinMs"] as? Int, Gestures.Dpad.litMinMs)
        try expect(dpad["fadeMs"] as? Int, Gestures.Dpad.fadeMs)
        let key = g["key"] as? [String: Any] ?? [:]
        try expect(key["holdMs"] as? Int, Gestures.Key.holdMs)
        try expect(key["litMinMs"] as? Int, Gestures.Key.litMinMs)
        try expect(g["volumeHudMs"] as? Int, Gestures.volumeHudMs)
    }
}
