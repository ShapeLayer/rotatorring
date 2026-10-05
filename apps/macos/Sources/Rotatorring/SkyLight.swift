import AppKit
import Darwin

/// Private SkyLight (WindowServer) calls for delivering input to a background window
/// without activating its app, raising it, or moving the cursor.
///
/// The recipe follows the open-source background computer-use drivers (cua-driver, Notch-Agent):
/// 1. Put the target window into a key/focused state for input routing, target side only, so
///    the user's frontmost app keeps its own focus ("focus without raise").
/// 2. Stamp each event with the target pid, window ID and window-local location.
/// 3. Attach a WindowServer authentication message and post it with `SLEventPostToPid`.
///    Apps such as iPhone Mirroring drop events posted with the public `CGEvent.postToPid`.
enum SkyLight {
    private typealias PostToPid = @convention(c) (pid_t, CGEvent) -> Void
    private typealias SetIntegerField = @convention(c) (CGEvent, UInt32, Int64) -> Void
    private typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Void
    private typealias SetAuthenticationMessage = @convention(c) (CGEvent, AnyObject) -> Void
    private typealias MakeAuthenticationMessage =
        @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer, Int32, UInt32) -> AnyObject?
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> OSStatus
    private typealias PostEventRecordTo = @convention(c) (UnsafeRawPointer, UnsafePointer<UInt8>) -> OSStatus

    private struct Symbols {
        let postToPid: PostToPid
        let setIntegerField: SetIntegerField
        let setWindowLocation: SetWindowLocation
        let setAuthenticationMessage: SetAuthenticationMessage?
        let makeAuthenticationMessage: MakeAuthenticationMessage?
        let authenticationMessageClass: AnyClass?
        let getProcessForPID: GetProcessForPID
        let postEventRecordTo: PostEventRecordTo
    }

    private static let symbols: Symbols? = {
        for path in ["/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                     "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices"] {
            guard dlopen(path, RTLD_LAZY) != nil else {
                inputLog.error("SkyLight: failed to load \(path, privacy: .public)")
                return nil
            }
        }
        let scope = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        func symbol<T>(_ name: String) -> T? {
            guard let pointer = dlsym(scope, name) else {
                inputLog.error("SkyLight: missing symbol \(name, privacy: .public)")
                return nil
            }
            return unsafeBitCast(pointer, to: T.self)
        }
        guard let postToPid: PostToPid = symbol("SLEventPostToPid"),
              let setIntegerField: SetIntegerField = symbol("SLEventSetIntegerValueField"),
              let setWindowLocation: SetWindowLocation = symbol("CGEventSetWindowLocation"),
              let getProcessForPID: GetProcessForPID = symbol("GetProcessForPID"),
              let postEventRecordTo: PostEventRecordTo = symbol("SLPSPostEventRecordTo")
        else { return nil }
        return Symbols(
            postToPid: postToPid, setIntegerField: setIntegerField, setWindowLocation: setWindowLocation,
            setAuthenticationMessage: symbol("SLEventSetAuthenticationMessage"),
            makeAuthenticationMessage: symbol("objc_msgSend"),
            authenticationMessageClass: NSClassFromString("SLSEventAuthenticationMessage"),
            getProcessForPID: getProcessForPID, postEventRecordTo: postEventRecordTo)
    }()

    static var isAvailable: Bool { symbols != nil }

    // MARK: Focus without raise

    /// Makes `windowID` the key window of its app for input routing without activating the app,
    /// raising the window, or taking focus from the frontmost app.
    static func focusWithoutRaise(pid: pid_t, windowID: CGWindowID) {
        guard let symbols else { return }
        var psn = [UInt32](repeating: 0, count: 2)
        let status = psn.withUnsafeMutableBytes { symbols.getProcessForPID(pid, $0.baseAddress!) }
        guard status == noErr else {
            inputLog.error("SkyLight: GetProcessForPID failed \(status)")
            return
        }

        var focus = eventRecord(windowID: windowID)
        focus[0x08] = 0x0d
        focus[0x8a] = 0x01

        var keyWindow = eventRecord(windowID: windowID)
        keyWindow[0x3a] = 0x10
        for offset in 0x20..<0x30 { keyWindow[offset] = 0xff }
        var keyBegin = keyWindow, keyEnd = keyWindow
        keyBegin[0x08] = 0x01
        keyEnd[0x08] = 0x02

        psn.withUnsafeBytes { psnBytes in
            for record in [focus, keyBegin, keyEnd] {
                _ = record.withUnsafeBufferPointer { symbols.postEventRecordTo(psnBytes.baseAddress!, $0.baseAddress!) }
            }
        }
    }

    private static func eventRecord(windowID: CGWindowID) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        withUnsafeBytes(of: UInt32(windowID).littleEndian) { raw in
            for (i, byte) in raw.enumerated() { bytes[0x3c + i] = byte }
        }
        return bytes
    }

    // MARK: Events

    /// Addresses a mouse event to a window: screen location, window-local location, pid and window ID.
    static func stampMouse(_ event: CGEvent, pid: pid_t, windowID: CGWindowID, eventNumber: Int64,
                           screenPoint: CGPoint, windowLocalPoint: CGPoint) {
        guard let symbols else { return }
        let window = Int64(windowID)
        event.location = screenPoint
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: window)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: window)
        symbols.setWindowLocation(event, windowLocalPoint)
        symbols.setIntegerField(event, 0, eventNumber) // mouse event number
        symbols.setIntegerField(event, 40, Int64(pid)) // target pid
        symbols.setIntegerField(event, 51, window)     // window number
        symbols.setIntegerField(event, 91, window)
        symbols.setIntegerField(event, 92, window)
    }

    /// Posts to `pid` with a WindowServer authentication message attached when possible.
    static func post(_ event: CGEvent, to pid: pid_t) {
        guard let symbols else {
            event.postToPid(pid)
            return
        }
        event.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        var authenticated = false
        if let makeMessage = symbols.makeAuthenticationMessage,
           let setMessage = symbols.setAuthenticationMessage,
           let messageClass = symbols.authenticationMessageClass,
           let record = eventRecordPointer(of: event),
           let message = makeMessage(messageClass as AnyObject,
                                     NSSelectorFromString("messageWithEventRecord:pid:version:"),
                                     record, pid, 0) {
            setMessage(event, message)
            authenticated = true
        }
        symbols.postToPid(pid, event)
        inputLog.notice("SkyLight post authenticated=\(authenticated)")
    }

    /// The SLSEventRecord inside a CGEvent sits at one of a few known offsets.
    private static func eventRecordPointer(of event: CGEvent) -> UnsafeMutableRawPointer? {
        let base = Unmanaged.passUnretained(event).toOpaque()
        for offset in [24, 32, 16] {
            if let pointer = base.advanced(by: offset).load(as: UnsafeMutableRawPointer?.self) {
                return pointer
            }
        }
        return nil
    }
}
