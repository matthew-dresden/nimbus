import AppKit

// Represents a single annotation stroke/shape drawn on the canvas.
struct Annotation {
    enum Tool {
        case arrow, rectangle, ellipse, line, pencil, marker, text(String)
    }
    var tool: Tool
    var startPoint: CGPoint
    var path: NSBezierPath
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat = 16
}

// Protocol all drawing tools conform to.
protocol DrawingTool {
    var cursor: NSCursor { get }
    func startPath(at point: CGPoint, color: NSColor, lineWidth: CGFloat) -> Annotation
    func updatePath(_ annotation: inout Annotation, to point: CGPoint)
}

// MARK: - Tool Implementations

struct ArrowTool: DrawingTool {
    var cursor: NSCursor { .crosshair }

    func startPath(at point: CGPoint, color: NSColor, lineWidth: CGFloat) -> Annotation {
        Annotation(tool: .arrow, startPoint: point, path: NSBezierPath(), color: color, lineWidth: lineWidth)
    }

    func updatePath(_ annotation: inout Annotation, to point: CGPoint) {
        annotation.path = arrowPath(from: annotation.startPoint, to: point, lineWidth: annotation.lineWidth)
    }

    private func arrowPath(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = lineWidth * 5 + 10
        let headAngle: CGFloat = .pi / 6

        path.move(to: start)
        path.line(to: end)

        path.move(to: end)
        path.line(to: CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        ))
        path.move(to: end)
        path.line(to: CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        ))
        return path
    }
}

struct RectangleTool: DrawingTool {
    var cursor: NSCursor { .crosshair }

    func startPath(at point: CGPoint, color: NSColor, lineWidth: CGFloat) -> Annotation {
        Annotation(tool: .rectangle, startPoint: point, path: NSBezierPath(), color: color, lineWidth: lineWidth)
    }

    func updatePath(_ annotation: inout Annotation, to point: CGPoint) {
        let rect = CGRect(
            x: min(annotation.startPoint.x, point.x), y: min(annotation.startPoint.y, point.y),
            width: abs(point.x - annotation.startPoint.x), height: abs(point.y - annotation.startPoint.y)
        )
        guard rect.width > 0, rect.height > 0 else {
            annotation.path = NSBezierPath()
            return
        }
        annotation.path = NSBezierPath(rect: rect)
    }
}

struct EllipseTool: DrawingTool {
    var cursor: NSCursor { .crosshair }

    func startPath(at point: CGPoint, color: NSColor, lineWidth: CGFloat) -> Annotation {
        Annotation(tool: .ellipse, startPoint: point, path: NSBezierPath(), color: color, lineWidth: lineWidth)
    }

    func updatePath(_ annotation: inout Annotation, to point: CGPoint) {
        let rect = CGRect(
            x: min(annotation.startPoint.x, point.x), y: min(annotation.startPoint.y, point.y),
            width: abs(point.x - annotation.startPoint.x), height: abs(point.y - annotation.startPoint.y)
        )
        guard rect.width > 0, rect.height > 0 else {
            annotation.path = NSBezierPath()
            return
        }
        annotation.path = NSBezierPath(ovalIn: rect)
    }
}

struct PencilTool: DrawingTool {
    var cursor: NSCursor { .arrow }

    func startPath(at point: CGPoint, color: NSColor, lineWidth: CGFloat) -> Annotation {
        let path = NSBezierPath()
        path.move(to: point)
        return Annotation(tool: .pencil, startPoint: point, path: path, color: color, lineWidth: lineWidth)
    }

    func updatePath(_ annotation: inout Annotation, to point: CGPoint) {
        annotation.path.line(to: point)
    }
}

struct MarkerTool: DrawingTool {
    var cursor: NSCursor { .arrow }

    func startPath(at point: CGPoint, color: NSColor, lineWidth: CGFloat) -> Annotation {
        let path = NSBezierPath()
        path.move(to: point)
        return Annotation(tool: .marker, startPoint: point, path: path, color: color, lineWidth: lineWidth * 4)
    }

    func updatePath(_ annotation: inout Annotation, to point: CGPoint) {
        annotation.path.line(to: point)
    }
}

// Marker for the text tool. The canvas special-cases it with an inline editor;
// the committed annotation carries the string inside tool.
struct TextTool: DrawingTool {
    var cursor: NSCursor { .crosshair }

    func startPath(at point: CGPoint, color: NSColor, lineWidth: CGFloat) -> Annotation {
        let path = NSBezierPath()
        path.move(to: point)
        return Annotation(tool: .text(""), startPoint: point, path: path, color: color, lineWidth: lineWidth)
    }

    func updatePath(_ annotation: inout Annotation, to point: CGPoint) {}
}

struct LineTool: DrawingTool {
    var cursor: NSCursor { .crosshair }

    func startPath(at point: CGPoint, color: NSColor, lineWidth: CGFloat) -> Annotation {
        let path = NSBezierPath()
        path.move(to: point)
        return Annotation(tool: .line, startPoint: point, path: path, color: color, lineWidth: lineWidth)
    }

    func updatePath(_ annotation: inout Annotation, to point: CGPoint) {
        annotation.path.removeAllPoints()
        annotation.path.move(to: annotation.startPoint)
        annotation.path.line(to: point)
    }
}
