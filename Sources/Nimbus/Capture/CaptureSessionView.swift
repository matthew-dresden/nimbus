import AppKit

// Full-screen session overlay implementing the Lightshot interaction model:
//
//   selecting: dimmed screen, drag out a region (crosshair, size badge)
//   editing:   the region freezes a snapshot of itself and STAYS on screen -
//              movable by dragging inside, resizable via 8 handles, with the
//              full tool strip pinned beneath it. Everything lives in THIS
//              window; nothing floats off or vanishes until dismissed.
//
// Annotations are stored in IMAGE space (pixels of the frozen capture), so
// moving or resizing the selection never misplaces existing marks.
final class CaptureSessionView: NSView {

    enum Mode { case selecting, editing }

    private(set) var mode: Mode = .selecting

    var onSessionComplete: (() -> Void)?
    var onFreezeRequested: ((CGRect) -> Void)?

    // MARK: - Selection state

    private var startPoint: NSPoint?
    private var selectionRect: CGRect = .zero
    private var isDraggingSelection = false

    // MARK: - Edit state

    private var frozenImage: CGImage?
    private var imagePixelSize: CGSize = .zero   // backing pixels (retina-aware)
    private var imageSize: CGSize = .zero        // point size at capture time

    private var resizeEdge: Edge = .none
    private var resizeStartRect: CGRect = .zero
    private var resizeStartPoint: NSPoint = .zero
    private var moveOffset: CGPoint = .zero

    enum Edge { case none, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }

    // MARK: - Annotation state (image space)

    private(set) var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?

    var selectedTool: DrawingTool = SelectTool()
    var selectedColor: NSColor = .systemRed
    var lineWidthScale: CGFloat = 1 {
        didSet { baseLineWidth = 2 * lineWidthScale }
    }
    private var baseLineWidth: CGFloat = 2
    var fontSize: CGFloat { 16 * max(lineWidthScale, 0.5) }

    private var textEditor: NSTextField?
    private var textEditPoint: CGPoint = .zero   // view space

    // MARK: - Toolbar

    private var toolbar: NSView?
    private var buttonTools: [NSButton: DrawingTool] = [:]
    private var selectedToolButton: NSButton?

    // MARK: - Setup

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NSCursor.crosshair.set()
    }

    override var acceptsFirstResponder: Bool { true }



    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything outside the selection
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        switch mode {
        case .selecting:
            guard isDraggingSelection, selectionRect.width > 0, selectionRect.height > 0 else { return }
            NSGraphicsContext.current?.cgContext.clear(selectionRect)
            strokeSelectionBorder()
            drawHandles()
            drawSizeBadge()
        case .editing:
            guard !selectionRect.isEmpty else { return }
            NSGraphicsContext.current?.cgContext.clear(selectionRect)

            if let cg = frozenImage {
                NSGraphicsContext.current?.cgContext.saveGState()
                NSGraphicsContext.current?.cgContext.clip(to: selectionRect)
                NSImage(cgImage: cg, size: imageSize).draw(in: selectionRect)
                NSGraphicsContext.current?.cgContext.restoreGState()
            }

            for annotation in annotations {
                drawMapped(annotation)
            }
            if let current = currentAnnotation {
                drawMapped(current)
            }

            strokeSelectionBorder(strong: true)
            drawHandles()
        }
    }

    private func strokeSelectionBorder(strong: Bool = false) {
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = strong ? 2 : 1.5
        (strong ? NSColor.systemPurple : NSColor.white.withAlphaComponent(0.9)).setStroke()
        border.stroke()
    }

    private func drawHandles() {
        let size: CGFloat = 7
        NSColor.white.setFill()
        NSColor.systemPurple.setStroke()
        for corner in handlePoints() {
            let dot = CGRect(x: corner.x - size/2, y: corner.y - size/2, width: size, height: size)
            let p = NSBezierPath(ovalIn: dot)
            p.fill()
            p.stroke()
        }
    }

    private func handlePoints() -> [CGPoint] {
        [
            CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            CGPoint(x: selectionRect.midX, y: selectionRect.minY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.minY),
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.minX, y: selectionRect.midY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.midY),
        ]
    }

    private func drawSizeBadge() {
        let text = "\(Int(selectionRect.width)) x \(Int(selectionRect.height))"
        drawBadge(text, at: CGPoint(x: selectionRect.midX, y: selectionRect.maxY + 10))
    }

    private func drawBadge(_ text: String, at center: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 6
        let badgeRect = CGRect(
            x: center.x - size.width/2 - padding,
            y: center.y,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: CGPoint(x: badgeRect.minX + padding, y: badgeRect.minY + padding / 2),
            withAttributes: attrs
        )
    }

    // MARK: - Image-space mapping

    private func mapViewToImage(_ p: CGPoint) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let fx = (p.x - selectionRect.minX) / selectionRect.width
        let fy = (p.y - selectionRect.minY) / selectionRect.height
        return CGPoint(x: fx * imageSize.width, y: fy * imageSize.height)
    }

    private func drawMapped(_ annotation: Annotation) {
        NSGraphicsContext.current?.saveGraphicsState()

        // Map image space to current view rect
        let sx = selectionRect.width / max(imageSize.width, 1)
        let sy = selectionRect.height / max(imageSize.height, 1)
        var t = AffineTransform(scaleByX: sx, byY: sy)
        let transformed = NSBezierPath()
        transformed.append(annotation.path)
        transformed.transform(using: t)
        transformed.transform(using: AffineTransform(translationByX: selectionRect.minX,
                                                     byY: selectionRect.minY))

        transformed.lineWidth = annotation.lineWidth * ((sx + sy) / 2)
        transformed.lineCapStyle = .round
        transformed.lineJoinStyle = .round

        switch annotation.tool {
        case .marker:
            annotation.color.withAlphaComponent(0.4).setStroke()
        case .text(let string):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: annotation.fontSize * sy),
                .foregroundColor: annotation.color
            ]
            let origin = CGPoint(x: selectionRect.minX + annotation.startPoint.x * sx,
                                 y: selectionRect.minY + annotation.startPoint.y * sy)
            string.draw(at: origin, withAttributes: attrs)
            NSGraphicsContext.current?.restoreGraphicsState()
            return
        default:
            annotation.color.setStroke()
        }

        transformed.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: - Selection phase events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if mode == .editing {
            handleEditMouseDown(point)
            return
        }

        startPoint = point
        selectionRect = .zero
        isDraggingSelection = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if mode == .editing {
            handleEditDrag(point)
            return
        }

        guard let start = startPoint else { return }
        isDraggingSelection = true
        selectionRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if mode == .editing {
            handleEditMouseUp(point)
            return
        }

        guard isDraggingSelection, selectionRect.width > 5, selectionRect.height > 5 else {
            onSessionComplete?()
            return
        }
        isDraggingSelection = false
        onFreezeRequested?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            if textEditor != nil {
                cancelTextEditor()
            } else {
                onSessionComplete?()
            }
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Editing interactions

    private enum Interaction { case none, moving, resizing }
    private var interaction: Interaction = .none

    private func handleEditMouseDown(_ point: CGPoint) {
        commitTextEditor()

        let edge = edgeAt(point)
        if edge != .none {
            resizeEdge = edge
            resizeStartRect = selectionRect
            resizeStartPoint = point
            interaction = .resizing
            return
        }
        if selectionRect.contains(point) {
            if selectedTool is SelectTool {
                moveOffset = CGPoint(x: point.x - selectionRect.origin.x,
                                     y: point.y - selectionRect.origin.y)
                interaction = .moving
                return
            }
            // Draw with the active tool, in image space.
            let imgPoint = mapViewToImage(point)
            currentAnnotation = selectedTool.startPath(
                at: imgPoint, color: selectedColor, lineWidth: baseLineWidth
            )
            needsDisplay = true
            return
        }
        onSessionComplete?()   // click outside the selection ends the session
    }

    private func handleEditDrag(_ point: CGPoint) {
        switch interaction {
        case .resizing:
            selectionRect = resizedRect(from: resizeStartRect,
                                        start: resizeStartPoint,
                                        current: point,
                                        edge: resizeEdge)
            needsDisplay = true
        case .moving:
            selectionRect.origin = CGPoint(
                x: point.x - moveOffset.x,
                y: point.y - moveOffset.y
            )
            positionToolbar()
            needsDisplay = true
        case .none:
            guard currentAnnotation != nil else { return }
            let imgPoint = mapViewToImage(point)
            selectedTool.updatePath(&currentAnnotation!, to: imgPoint)
            needsDisplay = true
        }
    }

    private func handleEditMouseUp(_ point: CGPoint) {
        if interaction == .none, let annotation = currentAnnotation {
            annotations.append(annotation)
            currentAnnotation = nil
            needsDisplay = true
        }
        interaction = .none
    }

    // MARK: - Resize / move helpers

    private let handleRadius: CGFloat = 9
    private let borderSlack: CGFloat = 5

    private func edgeAt(_ p: CGPoint) -> Edge {
        let r = selectionRect
        guard r.contains(p) || r.insetBy(dx: -borderSlack, dy: -borderSlack).contains(p) else {
            return .none
        }
        let nearLeft = abs(p.x - r.minX) <= handleRadius + borderSlack
        let nearRight = abs(p.x - r.maxX) <= handleRadius + borderSlack
        let nearBottom = abs(p.y - r.minY) <= handleRadius + borderSlack
        let nearTop = abs(p.y - r.maxY) <= handleRadius + borderSlack

        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _):  return .topLeft
        case (_, true, true, _):  return .topRight
        case (true, _, _, true):  return .bottomLeft
        case (_, true, _, true):  return .bottomRight
        case (true, _, _, _):     return .left
        case (_, true, _, _):     return .right
        case (_, _, true, _):     return .top
        case (_, _, _, true):     return .bottom
        default:                  return .none
        }
    }

    private func resizedRect(from base: CGRect, start: CGPoint, current: CGPoint, edge: Edge) -> CGRect {
        var r = base
        let dx = current.x - start.x
        let dy = current.y - start.y
        let minWidth: CGFloat = 60, minHeight: CGFloat = 60

        switch edge {
        case .left:   r.origin.x = base.minX + dx; r.size.width = base.width - dx
        case .right:  r.size.width = base.width + dx
        case .bottom: r.origin.y = base.minY + dy; r.size.height = base.height - dy
        case .top:    r.size.height = base.height + dy
        case .topLeft:
            r.origin.x = base.minX + dx; r.size.width = base.width - dx
            r.size.height = base.height + dy
        case .topRight:
            r.size.width = base.width + dx
            r.size.height = base.height + dy
        case .bottomLeft:
            r.origin.x = base.minX + dx; r.size.width = base.width - dx
            r.origin.y = base.minY + dy; r.size.height = base.height - dy
        case .bottomRight:
            r.size.width = base.width + dx
            r.origin.y = base.minY + dy; r.size.height = base.height - dy
        case .none: break
        }

        if r.width < minWidth {
            if r.origin.x != base.minX { r.origin.x = base.maxX - minWidth }
            r.size.width = minWidth
        }
        if r.height < minHeight {
            if r.origin.y != base.minY { r.origin.y = base.maxY - minHeight }
            r.size.height = minHeight
        }
        return r
    }

    // MARK: - Session transitions (called by CaptureManager)

    /// Freeze: enter editing mode with the freshly captured region image.
    /// Called while the overlay is still on screen; the capture excludes this
    /// window so the image is the clean desktop beneath the dim.
    func beginEditing(image: CGImage, pixelSize: CGSize, pointSize: CGSize) {
        mode = .editing
        frozenImage = image
        imagePixelSize = pixelSize
        imageSize = pointSize

        setupToolbar()
        positionToolbar()
        NSCursor.pointingHand.set()
        needsDisplay = true
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        let barWidth: CGFloat = 600
        let bar = NSView(frame: CGRect(x: 0, y: 0, width: barWidth, height: 44))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.15, alpha: 0.96).cgColor
        bar.layer?.cornerRadius = 8
        toolbar = bar

        let drawTools: [(String, DrawingTool, String)] = [
            ("hand.raised",            SelectTool(),    "Move"),
            ("arrow.up.right",         ArrowTool(),     "Arrow"),
            ("rectangle",              RectangleTool(), "Rectangle"),
            ("circle",                 EllipseTool(),   "Ellipse"),
            ("line.diagonal",          LineTool(),      "Line"),
            ("pencil",                 PencilTool(),    "Pen"),
            ("highlighter",            MarkerTool(),    "Marker"),
            ("character.cursor.ibeam", TextTool(),      "Text"),
        ]

        var x: CGFloat = 8
        for (icon, tool, tip) in drawTools {
            let btn = toolbarButton(icon: icon, tooltip: tip)
            btn.frame = CGRect(x: x, y: 7, width: 30, height: 30)
            btn.action = #selector(selectDrawTool(_:))
            btn.target = self
            buttonTools[btn] = tool
            bar.addSubview(btn)
            x += 33
        }

        let colorBtn = toolbarButton(icon: "paintpalette", tooltip: "Color")
        colorBtn.frame = CGRect(x: x + 4, y: 7, width: 30, height: 30)
        colorBtn.action = #selector(pickColor)
        colorBtn.target = self
        bar.addSubview(colorBtn)
        x += 38

        let sizeControl = NSSegmentedControl(labels: ["S", "M", "L"],
                                             trackingMode: .selectOne,
                                             target: self,
                                             action: #selector(strokeSizeChanged(_:)))
        sizeControl.selectedSegment = 1
        sizeControl.frame = CGRect(x: x + 4, y: 8, width: 92, height: 26)
        bar.addSubview(sizeControl)
        x += 104

        let undoBtn = toolbarButton(icon: "arrow.uturn.backward", tooltip: "Undo")
        undoBtn.frame = CGRect(x: x + 4, y: 7, width: 30, height: 30)
        undoBtn.action = #selector(undoAction)
        undoBtn.target = self
        bar.addSubview(undoBtn)

        var rx: CGFloat = barWidth - 8
        let rightActions: [(String, String, Selector)] = [
            ("xmark",                 "Close (Esc)",       #selector(closeAction)),
            ("arrow.up.to.line",      "Upload",            #selector(uploadAction)),
            ("checkmark.circle",      "Save + Copy",       #selector(saveAndCopyAction)),
            ("square.and.arrow.down", "Save",              #selector(saveAction)),
            ("doc.on.clipboard",      "Copy",              #selector(copyAction)),
        ]
        for (icon, tip, sel) in rightActions {
            rx -= 33
            let btn = toolbarButton(icon: icon, tooltip: tip)
            btn.frame = CGRect(x: rx, y: 7, width: 30, height: 30)
            btn.action = sel
            btn.target = self
            bar.addSubview(btn)
            rx -= 2
        }

        addSubview(bar)
        if let first = buttonTools.keys.first(where: { buttonTools[$0] is SelectTool }) {
            selectDrawTool(first)
        } else if let btn = bar.subviews.compactMap({ $0 as? NSButton }).first {
            selectDrawTool(btn)
        }
    }

    private func positionToolbar() {
        guard let bar = toolbar else { return }
        let y = selectionRect.minY - bar.frame.height - 8
        let clampedY = max(bounds.minY + 6, y >= bounds.minY ? y : selectionRect.maxY + 8)
        let x = min(max(selectionRect.minX, bounds.minX + 6),
                    bounds.maxX - bar.frame.width - 6)
        bar.frame.origin = CGPoint(x: x, y: clampedY)
    }

    private func toolbarButton(icon: String, tooltip: String) -> NSButton {
        let btn = NSButton(frame: .zero)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        btn.image?.isTemplate = true
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 5
        btn.contentTintColor = .white
        btn.toolTip = tooltip
        return btn
    }

    @objc private func selectDrawTool(_ sender: NSButton) {
        if let tool = buttonTools[sender] {
            selectedTool = tool
        }
        selectedToolButton?.layer?.backgroundColor = NSColor.clear.cgColor
        sender.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        selectedToolButton = sender
    }

    @objc private func pickColor() {
        NSColorPanel.shared.makeKeyAndOrderFront(nil)
        NSColorPanel.shared.setTarget(self)
        NSColorPanel.shared.setAction(#selector(colorChanged(_:)))
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        selectedColor = sender.color
    }

    @objc private func strokeSizeChanged(_ sender: NSSegmentedControl) {
        let scales: [CGFloat] = [0.6, 1.0, 1.8]
        lineWidthScale = scales[sender.selectedSegment]
    }

    @objc private func undoAction() {
        if textEditor != nil {
            cancelTextEditor()
            return
        }
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    @objc private func closeAction() {
        onSessionComplete?()
    }

    @objc private func copyAction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([composedImage()])
        drawBadge("Copied!", at: CGPoint(x: bounds.midX, y: selectionRect.minY - 28))
    }

    @objc private func saveAction() {
        writeComposedPNG()
        drawBadge("Saved!", at: CGPoint(x: bounds.midX, y: selectionRect.minY - 28))
    }

    @objc private func saveAndCopyAction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([composedImage()])
        writeComposedPNG()
        drawBadge("Saved + Copied!", at: CGPoint(x: bounds.midX, y: selectionRect.minY - 28))
    }

    @objc private func uploadAction() {
        let image = composedImage()
        UploadService.shared.upload(image: image) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let url):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    self.drawBadge("Link copied!", at: CGPoint(x: self.bounds.midX, y: self.selectionRect.minY - 28))
                case .failure(let error):
                    self.drawBadge(error.localizedDescription, at: CGPoint(x: self.bounds.midX, y: self.selectionRect.minY - 28))
                }
            }
        }
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
        field.backgroundColor = NSColor.white.withAlphaComponent(0.9)
        field.drawsBackground = true
        field.isBordered = false
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
        let viewPoint = textEditPoint
        field.removeFromSuperview()
        textEditor = nil

        guard !string.isEmpty else { return }
        let imgPoint = mapViewToImage(viewPoint)
        let path = NSBezierPath()
        path.move(to: imgPoint)
        annotations.append(Annotation(
            tool: .text(string),
            startPoint: imgPoint,
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

    // MARK: - Output composition

    func composedImage() -> NSImage {
        commitTextEditor()
        let size = imageSize == .zero ? bounds.size : imageSize
        let image = NSImage(size: size)
        image.lockFocus()
        if let cg = frozenImage {
            NSImage(cgImage: cg, size: imageSize).draw(in: NSRect(origin: .zero, size: size))
        }
        for annotation in annotations {
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
                continue
            default:
                annotation.color.setStroke()
            }
            annotation.path.stroke()
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        image.unlockFocus()
        return image
    }

    private func writeComposedPNG() {
        let folder = PreferencesManager.shared.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = folder.appendingPathComponent("Screenshot \(f.string(from: Date())).png")
        guard let tiff = composedImage().tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

extension CaptureSessionView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let field = textEditor {
            field.frame.size.width = min(bounds.width - textEditPoint.x - 4,
                                         field.intrinsicContentSize.width + 8)
        }
    }
}

// MARK: - Select (move) tool

struct SelectTool: DrawingTool {
    var cursor: NSCursor { .pointingHand }

    func startPath(at point: CGPoint, color: NSColor, lineWidth: CGFloat) -> Annotation {
        let path = NSBezierPath()
        path.move(to: point)
        return Annotation(tool: .line, startPoint: point, path: path, color: color, lineWidth: lineWidth)
    }

    func updatePath(_ annotation: inout Annotation, to point: CGPoint) {}
}
