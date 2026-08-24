import XCTest
@testable import Nimbus

/// Regression tests for the drawing tools. The original upstream code lost the
/// anchor point for Rectangle/Ellipse (NSBezierPath(rect: .zero) is empty, so
/// the update guard bailed and nothing could ever be drawn).
final class DrawingToolTests: XCTestCase {

    private let red = NSColor.red
    private let width: CGFloat = 2

    func testRectangleAnchorsAtStartPoint() {
        var annotation = RectangleTool().startPath(at: CGPoint(x: 100, y: 200), color: red, lineWidth: width)
        RectangleTool().updatePath(&annotation, to: CGPoint(x: 250, y: 320))

        let bounds = annotation.path.bounds
        XCTAssertEqual(bounds.origin.x, 100, accuracy: 0.5)
        XCTAssertEqual(bounds.origin.y, 200, accuracy: 0.5)
        XCTAssertEqual(bounds.width, 150, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 120, accuracy: 0.5)
    }

    func testRectangleDrawsInReverseDirection() {
        var annotation = RectangleTool().startPath(at: CGPoint(x: 250, y: 320), color: red, lineWidth: width)
        RectangleTool().updatePath(&annotation, to: CGPoint(x: 100, y: 200))

        let bounds = annotation.path.bounds
        XCTAssertEqual(bounds.origin.x, 100, accuracy: 0.5)
        XCTAssertEqual(bounds.origin.y, 200, accuracy: 0.5)
        XCTAssertEqual(bounds.width, 150, accuracy: 0.5)
    }

    func testEllipseAnchorsAtStartPoint() {
        var annotation = EllipseTool().startPath(at: CGPoint(x: 40, y: 60), color: red, lineWidth: width)
        EllipseTool().updatePath(&annotation, to: CGPoint(x: 140, y: 160))

        let bounds = annotation.path.bounds
        XCTAssertEqual(bounds.origin.x, 40, accuracy: 0.5)
        XCTAssertEqual(bounds.width, 100, accuracy: 0.5)
        XCTAssertFalse(annotation.path.isEmpty)
    }

    func testLineConnectsStartToEnd() {
        var annotation = LineTool().startPath(at: CGPoint(x: 10, y: 10), color: red, lineWidth: width)
        LineTool().updatePath(&annotation, to: CGPoint(x: 90, y: 90))

        XCTAssertEqual(annotation.path.bounds.minX, 10, accuracy: 0.5)
        XCTAssertEqual(annotation.path.bounds.maxX, 90, accuracy: 0.5)
        XCTAssertEqual(annotation.startPoint, CGPoint(x: 10, y: 10))
    }

    func testArrowIncludesHeadGeometry() {
        var annotation = ArrowTool().startPath(at: .zero, color: red, lineWidth: width)
        ArrowTool().updatePath(&annotation, to: CGPoint(x: 100, y: 0))

        // Shaft + two head strokes = bounding height spans the head angle
        XCTAssertGreaterThan(annotation.path.bounds.height, 5)
        XCTAssertEqual(annotation.path.bounds.maxX, 100, accuracy: 0.5)
    }

    func testMarkerMultipliesLineWidth() {
        let annotation = MarkerTool().startPath(at: .zero, color: red, lineWidth: width)
        XCTAssertEqual(annotation.lineWidth, width * 4)
    }

    func testPencilFollowsDrag() {
        var annotation = PencilTool().startPath(at: .zero, color: red, lineWidth: width)
        PencilTool().updatePath(&annotation, to: CGPoint(x: 50, y: 50))
        PencilTool().updatePath(&annotation, to: CGPoint(x: 80, y: 20))

        XCTAssertEqual(annotation.path.bounds.maxX, 80, accuracy: 0.5)
        XCTAssertEqual(annotation.path.bounds.minY, 0, accuracy: 0.5)
        XCTAssertEqual(annotation.path.bounds.maxY, 50, accuracy: 0.5)
    }
}
