import QuartzCore
import RotatorringCore

/// How the mirrored image is transformed: rotate first, then flip in screen space.
struct Orientation: Equatable {
    /// Clockwise quarter turns, 0...3.
    var quarterTurns = 0
    var flipHorizontal = false
    var flipVertical = false

    var degrees: Int { quarterTurns * 90 }
    var swapsAxes: Bool { rr_swaps_axes(native) != 0 }
    var isIdentity: Bool { self == Orientation() }

    private var native: rr_orientation {
        rr_orientation(quarter_turns: Int32(quarterTurns), flip_horizontal: flipHorizontal ? 1 : 0,
                       flip_vertical: flipVertical ? 1 : 0)
    }
    mutating func rotateClockwise() { quarterTurns = Int(rr_rotate(native, 1).quarter_turns) }
    mutating func rotateCounterClockwise() { quarterTurns = Int(rr_rotate(native, -1).quarter_turns) }

    /// Size of the image after rotation.
    func displayedSize(for size: CGSize) -> CGSize {
        let result = rr_displayed_size(native, rr_size(width: Double(size.width), height: Double(size.height)))
        return CGSize(width: result.width, height: result.height)
    }

    /// Layer transform (y-up layer space, so clockwise is a negative angle).
    var transform: CATransform3D {
        let t = rr_centered_transform(native)
        // Convert the core's y-down matrix into Core Animation's y-up space.
        var result = CATransform3DIdentity
        result.m11 = CGFloat(t.a)
        result.m12 = -CGFloat(t.b)
        result.m21 = -CGFloat(t.c)
        result.m22 = CGFloat(t.d)
        return result
    }

    func sourcePoint(fromDisplayed p: CGPoint) -> CGPoint {
        let result = rr_source_point(native, rr_point(x: Double(p.x), y: Double(p.y)))
        return CGPoint(x: result.x, y: result.y)
    }

    func imageRect(source: CGSize, viewport: CGSize) -> CGRect {
        let displayed = displayedSize(for: source)
        let result = rr_aspect_fit(rr_size(width: Double(displayed.width), height: Double(displayed.height)),
                                   rr_size(width: Double(viewport.width), height: Double(viewport.height)))
        return CGRect(x: result.x, y: result.y, width: result.width, height: result.height)
    }

    func contentSize(source: CGSize, zoom: CGFloat, viewport: CGSize) -> CGSize {
        let displayed = displayedSize(for: source)
        let result = rr_zoomed_size(rr_size(width: Double(displayed.width), height: Double(displayed.height)),
                                   Double(zoom), rr_size(width: Double(viewport.width), height: Double(viewport.height)))
        return CGSize(width: result.width, height: result.height)
    }

    var summary: String {
        var parts: [String] = []
        if quarterTurns != 0 { parts.append("\(degrees)°") }
        if flipHorizontal { parts.append("좌우 반전") }
        if flipVertical { parts.append("상하 반전") }
        return parts.isEmpty ? "원본 방향" : parts.joined(separator: " · ")
    }
}
