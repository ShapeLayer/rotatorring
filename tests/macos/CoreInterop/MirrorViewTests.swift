import XCTest
import AppKit
import QuartzCore
@testable import Rotatorring

final class MirrorViewTests: XCTestCase {
    @MainActor
    func testRotatedContentCannotBleedPastMirrorBounds() async throws {
        let view = MirrorView(frame: CGRect(x: 20, y: 20, width: 100, height: 160))
        view.sourceSize = CGSize(width: 100, height: 160)
        view.orientation = Orientation(quarterTurns: 3)
        view.showMessage(nil)
        view.layoutSubtreeIfNeeded()
        let root = try XCTUnwrap(view.layer)
        let video = try XCTUnwrap(root.sublayers?.first)
        XCTAssertTrue(view.clipsToBounds)
        XCTAssertTrue(root.masksToBounds)

        // Reproduce the resize transition: the source layer is still larger than
        // its newly shrunken viewport. Render with space above the view to detect
        // white video pixels escaping into the toolbar region.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = CGRect(x: 20, y: 60, width: 100, height: 80)
        video.backgroundColor = NSColor.white.cgColor
        video.bounds = CGRect(x: 0, y: 0, width: 160, height: 160)
        video.position = CGPoint(x: 50, y: 40)
        let parent = CALayer()
        parent.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        parent.backgroundColor = NSColor.black.cgColor
        parent.addSublayer(root)
        CATransaction.commit()
        defer { root.removeFromSuperlayer() }

        var pixels = [UInt8](repeating: 0, count: 200 * 200 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 200, height: 200,
                bitsPerComponent: 8, bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let bytes = buffer.bindMemory(to: UInt8.self)
            parent.render(in: context)
            // Outside the viewport, including its top edge, remains black.
            for y in [45, 150] {
                let index = (y * 200 + 70) * 4
                XCTAssertEqual(bytes[index], 0)
                XCTAssertEqual(bytes[index + 1], 0)
                XCTAssertEqual(bytes[index + 2], 0)
            }
            XCTAssertEqual(bytes[(100 * 200 + 70) * 4], 255, "Video must actually render inside the viewport")
            // Negative control: without the fix, the same geometry leaks white.
            root.masksToBounds = false
            parent.render(in: context)
            XCTAssertEqual(bytes[(150 * 200 + 70) * 4], 255)
            root.masksToBounds = true
        }
    }
}
