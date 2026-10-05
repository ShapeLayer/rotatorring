import XCTest
import QuartzCore
@testable import Rotatorring

final class OrientationTests: XCTestCase {
    func testCoreGeometryAndLayerCoordinateConversion() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1),
                      CGPoint(x: 1, y: 1), CGPoint(x: 0.2, y: 0.7)]
        for turns in 0..<4 {
            for horizontal in [false, true] {
                for vertical in [false, true] {
                    let o = Orientation(quarterTurns: turns, flipHorizontal: horizontal, flipVertical: vertical)
                    XCTAssertEqual(o.swapsAxes, turns % 2 == 1)
                    XCTAssertEqual(o.displayedSize(for: CGSize(width: 80, height: 120)),
                                   turns % 2 == 1 ? CGSize(width: 120, height: 80) : CGSize(width: 80, height: 120))
                    for p in points {
                        var expected: CGPoint
                        switch turns {
                        case 0: expected = p
                        case 1: expected = CGPoint(x: 1 - p.y, y: p.x)
                        case 2: expected = CGPoint(x: 1 - p.x, y: 1 - p.y)
                        default: expected = CGPoint(x: p.y, y: 1 - p.x)
                        }
                        if horizontal { expected.x = 1 - expected.x }
                        if vertical { expected.y = 1 - expected.y }
                        let source = o.sourcePoint(fromDisplayed: expected)
                        XCTAssertEqual(source.x, p.x, accuracy: 1e-10)
                        XCTAssertEqual(source.y, p.y, accuracy: 1e-10)
                        let m = o.transform
                        let x = p.x - 0.5, y = 0.5 - p.y
                        XCTAssertEqual(m.m11 * x + m.m21 * y + 0.5, expected.x, accuracy: 1e-10)
                        XCTAssertEqual(0.5 - (m.m12 * x + m.m22 * y), expected.y, accuracy: 1e-10)
                    }
                }
            }
        }
    }

    func testFitAndRotationWrap() {
        var o = Orientation()
        o.rotateCounterClockwise()
        XCTAssertEqual(o.quarterTurns, 3)
        o.rotateClockwise()
        XCTAssertTrue(o.isIdentity)
        let rect = o.imageRect(source: CGSize(width: 80, height: 120), viewport: CGSize(width: 320, height: 320))
        XCTAssertEqual(rect.width, 640.0 / 3, accuracy: 1e-10)
        let zoomed = o.contentSize(source: CGSize(width: 80, height: 120), zoom: 2, viewport: CGSize(width: 100, height: 100))
        XCTAssertEqual(zoomed.width, 200.0 / 3, accuracy: 1e-10)
        XCTAssertEqual(zoomed.height, 100)
        XCTAssertEqual(rect.height, 320)
        XCTAssertEqual(rect.minY, 0)
        XCTAssertEqual(o.imageRect(source: .zero, viewport: CGSize(width: 320, height: 320)), .zero)
    }
}
