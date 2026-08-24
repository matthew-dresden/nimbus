import AppKit

// NSView that renders the captured screenshot + live annotation layers,
// including inline text editing for the text tool.
final class DrawingCanvas: NSView {

    var screenshot: NSImage?
    private(set) var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?

    var selectedTool: DrawingTool = ArrowTool()
    var selectedColor: NSColor = .systemRed

    // Scales stroke width and text size. Driven by the toolbar S/M/L control.
    var lineWidthScale: CGFloat = 1 {
        didSet { baseLineWidth = 2 * lineWidthScale }
    }
    private var baseLineWidth: CGFloat = 2

    private var textEditor: NSTextField?
    private var textEditPoint: CGPoint = .zero

    var canUndo: Bool {
        textEditor == nil ? !annotations.isEmpty : false
    }

    var fontSize: CGFloat { 16 * max(lineWidthScale, 0.5) }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Screenshot background
        screenshot?.draw(in: bounds)

        // Committed annotations
        for annotation in annotations {
            draw(annotation)
        }

        // In-progress annotation
        if let current = currentAnnotation {
            draw(current)
        }
    }

    private func draw(_ annotation: Annotation) {
        NSGraphicsContext.current?.saveGraphicsState()
        annotation.path.lineWidth = annotation.lineWidth
        annotation.path.lineCapStyle = .round
        annotation.path.lineJoinStyle = .round

        switch annotation.tool {
        case .marker:
            annotation.color.withAlphaComponent(0.4).setStroke()
        case .text(let string):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: annotation.fontSize),
                .foregroundColor: annotation.color
            ]
            string.draw(at: annotation.path.currentPoint, withAttributes: attrs)
            NSGraphicsContext.current?.restoreGraphicsState()
            return
        default:
            annotation.color.setStroke()
        }

        annotation.path.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        commitTextEditor()

        let point = convert(event.locationInWindow, from: nil)

        if selectedTool is TextTool {
            beginTextEditing(at: point)
            return
        }

        currentAnnotation = selectedTool.startPath(
            at: point, color: selectedColor, lineWidth: baseLineWidth
        )
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard currentAnnotation != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        selectedTool.updatePath(&currentAnnotation!, to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let annotation = currentAnnotation {
            annotations.append(annotation)
            currentAnnotation = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, textEditor != nil { // Escape cancels text edit
            cancelTextEditor()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Text editing

    private func beginTextEditing(at point: CGPoint) {
        commitTextEditor()
        textEditPoint = point

        let field = NSTextField(frame: CGRect(
            x: point.x, y: point.y - fontSize,
            width: bounds.width - point.x - 4, height: fontSize * 1.4
        ))
        field.font = .systemFont(ofSize: fontSize, weight: .semibold)
        field.textColor = selectedColor
        field.backgroundColor = NSColor.white.withAlphaComponent(0.85)
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .exterior
        field.target = self
        field.action = #selector(textFieldSubmitted(_:))
        field.delegate = self
        addSubview(field)
        field.becomeFirstResponder()
        textEditor = field
    }

    @objc private func textFieldSubmitted(_ sender: NSTextField) {
        commitTextEditor()
    }

    private func commitTextEditor() {
        guard let field = textEditor else { return }
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let point = textEditPoint
        field.removeFromSuperview()
        textEditor = nil

        guard !string.isEmpty else { return }
        let path = NSBezierPath()
        path.move(to: point)
        annotations.append(Annotation(
            tool: .text(string),
            startPoint: point,
            path: path,
            color: selectedColor,
            lineWidth: baseLineWidth,
            fontSize: fontSize
        ))
        needsDisplay = true
    }

    private func cancelTextEditor() {
        textEditor?.removeFromSuperview()
        textEditor = nil
    }

    // MARK: - Actions

    func undo() {
        if textEditor != nil {
            cancelTextEditor()
            return
        }
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    func renderedImage() -> NSImage {
        commitTextEditor()
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        draw(bounds)
        image.unlockFocus()
        return image
    }

    override var acceptsFirstResponder: Bool { true }
}

extension DrawingCanvas: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        // Live-width the editor so long text stays visible.
        if let field = textEditor {
            field.frame.size.width = min(bounds.width - textEditPoint.x - 4,
                                         field.intrinsicContentSize.width + 8)
        }
    }
}
