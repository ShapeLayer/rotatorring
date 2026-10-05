import AppKit
import ApplicationServices
import os

let inputLog = Logger(subsystem: "com.shapelayer.rotatorring", category: "input")

/// Forwards clicks and key presses from the mirror view to the source window as they happen,
/// without activating the source app, raising its window, or moving the cursor (see `SkyLight`).
final class InputForwarder {
    /// Marks events we post, so they are never forwarded again if they land on the mirror.
    static let eventTag: Int64 = 0x524F_5441

    private let windowID: CGWindowID
    private let pid: pid_t
    private var eventNumber: Int64 = 0
    private static var didPromptForAccessibility = false

    init(windowID: CGWindowID, pid: pid_t) {
        self.windowID = windowID
        self.pid = pid
    }

    static func isOwnEvent(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == eventTag
    }

    /// Posting events to other apps needs the Accessibility permission; prompts once if missing.
    static func ensureTrusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        inputLog.error("Accessibility not trusted; events are not posted")
        if !didPromptForAccessibility {
            didPromptForAccessibility = true
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        return false
    }

    // MARK: Mouse

    /// `sourcePoint` is normalized (0...1, top-left origin) in the source window.
    func forwardMouse(_ event: NSEvent, sourcePoint: CGPoint) {
        guard let type = CGEventType(rawValue: UInt32(event.type.rawValue)),
              let bounds = currentBounds(ofWindow: windowID) else { return }
        let local = CGPoint(x: sourcePoint.x * bounds.width, y: sourcePoint.y * bounds.height)
        let screen = CGPoint(x: bounds.minX + local.x, y: bounds.minY + local.y)
        let button = CGMouseButton(rawValue: UInt32(event.buttonNumber)) ?? .left
        let clickState = event.cgEvent?.getIntegerValueField(.mouseEventClickState) ?? 1

        if type.isMouseDown {
            eventNumber += 1
            SkyLight.focusWithoutRaise(pid: pid, windowID: windowID)
            // Hover first so the target registers the pointer before the press.
            post(.mouseMoved, button: button, clickState: 0, screen: screen, local: local, flags: [])
        }
        post(type, button: button, clickState: clickState, screen: screen, local: local,
             flags: event.cgEvent?.flags ?? [])
    }

    private func post(_ type: CGEventType, button: CGMouseButton, clickState: Int64,
                      screen: CGPoint, local: CGPoint, flags: CGEventFlags) {
        guard let cg = CGEvent(mouseEventSource: nil, mouseType: type,
                               mouseCursorPosition: screen, mouseButton: button) else { return }
        cg.flags = flags
        cg.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        cg.setIntegerValueField(.mouseEventClickState, value: clickState)
        cg.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        SkyLight.stampMouse(cg, pid: pid, windowID: windowID, eventNumber: eventNumber,
                            screenPoint: screen, windowLocalPoint: local)
        SkyLight.post(cg, to: pid)
        inputLog.notice("post mouse type=\(type.rawValue) pid=\(self.pid) window=\(self.windowID)")
    }

    // MARK: Keyboard

    func forwardKey(_ event: NSEvent) {
        guard let cg = event.cgEvent?.copy() else { return }
        if event.type == .keyDown { SkyLight.focusWithoutRaise(pid: pid, windowID: windowID) }
        cg.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        SkyLight.post(cg, to: pid)
        inputLog.notice("post key type=\(cg.type.rawValue) pid=\(self.pid)")
    }
}

private extension CGEventType {
    var isMouseDown: Bool { self == .leftMouseDown || self == .rightMouseDown || self == .otherMouseDown }
}
