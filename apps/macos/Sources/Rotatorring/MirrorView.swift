import AppKit
import QuartzCore

protocol MirrorViewInputDelegate: AnyObject {
    /// `point` is normalized (0...1, top-left origin) in the displayed image. Returns true if handled.
    func mirrorView(_ view: MirrorView, mouseEvent event: NSEvent, at point: CGPoint) -> Bool
    func mirrorView(_ view: MirrorView, keyEvent event: NSEvent) -> Bool
}

/// Displays captured frames, rotated/flipped and aspect-fitted to the view.
final class MirrorView: NSView {
    var sourceSize: CGSize = .zero { didSet { needsLayout = true } }
    var orientation = Orientation() { didSet { needsLayout = true } }
    weak var inputDelegate: MirrorViewInputDelegate?

    /// Where the displayed image sits in the view.
    private(set) var imageRect: CGRect = .zero
    /// Set while a press that started on the image is held, so drags outside it are still delivered.
    private var isTrackingPress = false

    private let contentLayer = CALayer()
    private let messageLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        // AppKit no longer clips NSViews by default. A rotated layer can cross
        // the toolbar boundary while the window and layer sizes are changing.
        clipsToBounds = true
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor

        contentLayer.contentsGravity = .resize
        contentLayer.magnificationFilter = .linear
        contentLayer.minificationFilter = .linear
        let noAnimation = NSNull()
        contentLayer.actions = ["contents": noAnimation, "bounds": noAnimation,
                                "position": noAnimation, "transform": noAnimation]
        layer?.addSublayer(contentLayer)

        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
        ])
        showMessage("원본 창 캡처를 시작하는 중…")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func display(surface: IOSurface) {
        if !messageLabel.isHidden { showMessage(nil) }
        contentLayer.contents = surface
    }

    func showMessage(_ message: String?) {
        messageLabel.stringValue = message ?? ""
        messageLabel.isHidden = message == nil
        contentLayer.isHidden = message != nil
    }

    override func layout() {
        super.layout()
        guard sourceSize.width > 0, sourceSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }

        // Aspect-fit the rotated image into the view, then size the (unrotated) layer to match.
        imageRect = orientation.imageRect(source: sourceSize, viewport: bounds.size)
        imageRect.origin.x += bounds.minX
        imageRect.origin.y += bounds.minY
        let fitted = imageRect.size
        let layerSize = orientation.swapsAxes ? CGSize(width: fitted.height, height: fitted.width) : fitted

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.transform = CATransform3DIdentity
        contentLayer.bounds = CGRect(origin: .zero, size: layerSize)
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        contentLayer.transform = orientation.transform
        CATransaction.commit()
    }

    // MARK: Input

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Normalized point in the displayed image; nil if outside it (unless `clamped`).
    private func imagePoint(for event: NSEvent, clamped: Bool) -> CGPoint? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let x = (p.x - imageRect.minX) / imageRect.width
        let y = (imageRect.maxY - p.y) / imageRect.height
        if clamped { return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1)) }
        return (0...1).contains(x) && (0...1).contains(y) ? CGPoint(x: x, y: y) : nil
    }

    private func handlePress(_ event: NSEvent) -> Bool {
        guard !InputForwarder.isOwnEvent(event), let delegate = inputDelegate,
              let point = imagePoint(for: event, clamped: false) else { return false }
        isTrackingPress = delegate.mirrorView(self, mouseEvent: event, at: point)
        return isTrackingPress
    }

    private func handleDrag(_ event: NSEvent) -> Bool {
        guard isTrackingPress, let point = imagePoint(for: event, clamped: true) else { return false }
        return inputDelegate?.mirrorView(self, mouseEvent: event, at: point) ?? false
    }

    private func handleRelease(_ event: NSEvent) -> Bool {
        guard isTrackingPress, let point = imagePoint(for: event, clamped: true) else { return false }
        isTrackingPress = false
        return inputDelegate?.mirrorView(self, mouseEvent: event, at: point) ?? false
    }

    override func mouseDown(with event: NSEvent) { if !handlePress(event) { super.mouseDown(with: event) } }
    override func rightMouseDown(with event: NSEvent) { if !handlePress(event) { super.rightMouseDown(with: event) } }
    override func otherMouseDown(with event: NSEvent) { if !handlePress(event) { super.otherMouseDown(with: event) } }
    override func mouseDragged(with event: NSEvent) { if !handleDrag(event) { super.mouseDragged(with: event) } }
    override func rightMouseDragged(with event: NSEvent) { if !handleDrag(event) { super.rightMouseDragged(with: event) } }
    override func otherMouseDragged(with event: NSEvent) { if !handleDrag(event) { super.otherMouseDragged(with: event) } }
    override func mouseUp(with event: NSEvent) { if !handleRelease(event) { super.mouseUp(with: event) } }
    override func rightMouseUp(with event: NSEvent) { if !handleRelease(event) { super.rightMouseUp(with: event) } }
    override func otherMouseUp(with event: NSEvent) { if !handleRelease(event) { super.otherMouseUp(with: event) } }

    override func keyDown(with event: NSEvent) { if !handleKey(event) { super.keyDown(with: event) } }
    override func keyUp(with event: NSEvent) { if !handleKey(event) { super.keyUp(with: event) } }
    override func flagsChanged(with event: NSEvent) { if !handleKey(event) { super.flagsChanged(with: event) } }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard !InputForwarder.isOwnEvent(event) else { return true }
        return inputDelegate?.mirrorView(self, keyEvent: event) ?? false
    }
}
