import AppKit
import QuartzCore
import ScreenCaptureKit

/// One mirror window showing a transformed live view of a target window.
///
/// By default the window follows the source window's size at `zoom` (1.0 = same size).
/// Resizing the window by hand changes `zoom`; turning off "follow source" allows a free size.
final class MirrorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, NSToolbarDelegate,
    MirrorViewInputDelegate {
    var onClose: ((MirrorWindowController) -> Void)?

    private let target: SCWindow
    private let targetName: String
    private let mirrorView = MirrorView()
    private let capture = WindowCapture()
    private var input: InputForwarder!
    private var pollTimer: Timer?
    private var isProgrammaticResize = false

    private var sourceSize: CGSize
    private var orientation = Orientation() {
        didSet {
            // Commit the new window size and transformed layer geometry together.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mirrorView.orientation = orientation
            applyWindowSize()
            mirrorView.layoutSubtreeIfNeeded()
            CATransaction.commit()
            updateSubtitle()
        }
    }
    private var zoom: CGFloat = 1.0
    private var followsSource = true

    private static let zoomSteps: [CGFloat] = [0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    init(target: SCWindow) {
        self.target = target
        self.targetName = target.owningApplication?.applicationName ?? "창"
        self.sourceSize = target.frame.size

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: target.frame.size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.minSize = NSSize(width: 120, height: 120)
        super.init(window: window)

        let title = target.title.flatMap { $0.isEmpty ? nil : $0 }
        window.title = title.map { "\(targetName) — \($0)" } ?? targetName
        window.delegate = self
        window.contentView = mirrorView
        window.toolbar = makeToolbar()
        window.toolbarStyle = .unifiedCompact

        mirrorView.sourceSize = sourceSize
        mirrorView.menu = MainMenu.makeTransformMenu(title: "")
        mirrorView.inputDelegate = self
        input = InputForwarder(windowID: target.windowID, pid: target.owningApplication?.processID ?? 0)

        capture.onFrame = { [weak self] surface in self?.mirrorView.display(surface: surface) }
        capture.onStop = { [weak self] error in
            self?.stopPolling()
            self?.mirrorView.showMessage("캡처가 중단되었습니다.\n\(error?.localizedDescription ?? "")")
        }
        updateSubtitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start() {
        guard let window else { return }
        applyWindowSize()
        window.center()
        showWindow(nil)
        window.makeFirstResponder(mirrorView)
        Task { @MainActor in
            do {
                try await capture.start(window: target)
                startPolling()
            } catch {
                mirrorView.showMessage("캡처를 시작할 수 없습니다.\n\(error.localizedDescription)")
            }
        }
    }

    // MARK: Source size tracking

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollSourceBounds() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollSourceBounds() {
        guard let bounds = currentBounds(ofWindow: target.windowID) else {
            stopPolling()
            capture.stop()
            mirrorView.showMessage("원본 창이 닫혔습니다.")
            return
        }
        let size = bounds.size
        guard size.width > 1, size.height > 1,
              abs(size.width - sourceSize.width) > 0.5 || abs(size.height - sourceSize.height) > 0.5
        else { return }
        sourceSize = size
        mirrorView.sourceSize = size
        capture.update(pointSize: size)
        applyWindowSize()
        updateSubtitle()
    }

    /// Resize the mirror window to (rotated source size × zoom), keeping its top-left corner fixed.
    private func applyWindowSize() {
        guard followsSource, let window, sourceSize.width > 0, sourceSize.height > 0 else { return }
        let displayed = orientation.displayedSize(for: sourceSize)
        var content = CGSize(width: displayed.width * zoom, height: displayed.height * zoom)

        // Never grow past the screen; shrink proportionally instead (zoom is left unchanged).
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let maxContent = window.contentRect(forFrameRect: visible).size
            content = orientation.contentSize(source: sourceSize, zoom: zoom, viewport: maxContent)
        }

        window.contentAspectRatio = displayed
        let old = window.frame
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin = NSPoint(x: old.minX, y: old.maxY - frame.height)
        guard frame != old else { return }
        isProgrammaticResize = true
        window.setFrame(frame, display: true, animate: false)
        isProgrammaticResize = false
    }

    private func updateSubtitle() {
        let size = "\(Int(sourceSize.width))×\(Int(sourceSize.height))"
        let scale = followsSource ? "\(Int((zoom * 100).rounded()))%" : "자유 크기"
        let permission = AXIsProcessTrusted() ? "" : " · 손쉬운 사용 권한 없음"
        window?.subtitle = "\(orientation.summary) · \(scale) · 원본 \(size)\(permission)"
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard !isProgrammaticResize, followsSource, let window, window.inLiveResize,
              let content = window.contentView?.bounds.size else { return }
        let displayed = orientation.displayedSize(for: sourceSize)
        guard displayed.width > 0 else { return }
        zoom = content.width / displayed.width
        updateSubtitle()
    }

    func windowWillClose(_ notification: Notification) {
        stopPolling()
        capture.stop()
        onClose?(self)
    }

    // MARK: Actions (reached through the responder chain via the window delegate)

    @objc func rotateRight(_ sender: Any?) { orientation.rotateClockwise() }
    @objc func rotateLeft(_ sender: Any?) { orientation.rotateCounterClockwise() }
    @objc func flipHorizontal(_ sender: Any?) { orientation.flipHorizontal.toggle() }
    @objc func flipVertical(_ sender: Any?) { orientation.flipVertical.toggle() }
    @objc func resetTransform(_ sender: Any?) { orientation = Orientation() }

    @objc func actualSize(_ sender: Any?) { setZoom(1) }
    @objc func zoomIn(_ sender: Any?) {
        setZoom(Self.zoomSteps.first { $0 > zoom + 0.001 } ?? Self.zoomSteps.last!)
    }
    @objc func zoomOut(_ sender: Any?) {
        setZoom(Self.zoomSteps.last { $0 < zoom - 0.001 } ?? Self.zoomSteps.first!)
    }

    @objc func toggleFollowSource(_ sender: Any?) {
        followsSource.toggle()
        if followsSource {
            applyWindowSize()
        } else {
            window?.contentResizeIncrements = NSSize(width: 1, height: 1) // clears the aspect lock
        }
        updateSubtitle()
    }

    @objc func toggleFloating(_ sender: Any?) {
        guard let window else { return }
        window.level = window.level == .floating ? .normal : .floating
    }

    private func setZoom(_ value: CGFloat) {
        zoom = value
        if !followsSource { followsSource = true }
        applyWindowSize()
        updateSubtitle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleFollowSource(_:)):
            menuItem.state = followsSource ? .on : .off
        case #selector(toggleFloating(_:)):
            menuItem.state = window?.level == .floating ? .on : .off
        case #selector(flipHorizontal(_:)):
            menuItem.state = orientation.flipHorizontal ? .on : .off
        case #selector(flipVertical(_:)):
            menuItem.state = orientation.flipVertical ? .on : .off
        case #selector(resetTransform(_:)):
            return !orientation.isIdentity
        default:
            break
        }
        return true
    }

    // MARK: MirrorViewInputDelegate

    func mirrorView(_ view: MirrorView, mouseEvent event: NSEvent, at point: CGPoint) -> Bool {
        guard InputForwarder.ensureTrusted() else { return false }
        input.forwardMouse(event, sourcePoint: orientation.sourcePoint(fromDisplayed: point))
        return true
    }

    func mirrorView(_ view: MirrorView, keyEvent event: NSEvent) -> Bool {
        guard InputForwarder.ensureTrusted() else { return false }
        input.forwardKey(event)
        return true
    }

    // MARK: Toolbar

    private enum ToolbarID {
        static let rotateLeft = NSToolbarItem.Identifier("rotateLeft")
        static let rotateRight = NSToolbarItem.Identifier("rotateRight")
        static let flipH = NSToolbarItem.Identifier("flipH")
        static let flipV = NSToolbarItem.Identifier("flipV")
        static let reset = NSToolbarItem.Identifier("reset")
        static let floating = NSToolbarItem.Identifier("floating")
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MirrorToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarID.rotateLeft, ToolbarID.rotateRight, ToolbarID.flipH, ToolbarID.flipV,
         ToolbarID.reset, ToolbarID.floating]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let spec: (String, String, Selector)
        switch id {
        case ToolbarID.rotateLeft: spec = ("왼쪽으로 회전", "rotate.left", #selector(rotateLeft(_:)))
        case ToolbarID.rotateRight: spec = ("오른쪽으로 회전", "rotate.right", #selector(rotateRight(_:)))
        case ToolbarID.flipH: spec = ("좌우 반전", "arrow.left.and.right.righttriangle.left.righttriangle.right", #selector(flipHorizontal(_:)))
        case ToolbarID.flipV: spec = ("상하 반전", "arrow.up.and.down.righttriangle.up.righttriangle.down", #selector(flipVertical(_:)))
        case ToolbarID.reset: spec = ("원래대로", "arrow.counterclockwise", #selector(resetTransform(_:)))
        case ToolbarID.floating: spec = ("항상 위에 표시", "pin", #selector(toggleFloating(_:)))
        default: return nil
        }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = spec.0
        item.toolTip = spec.0
        item.image = NSImage(systemSymbolName: spec.1, accessibilityDescription: spec.0)
        item.action = spec.2
        item.target = self
        item.isBordered = true
        return item
    }
}
