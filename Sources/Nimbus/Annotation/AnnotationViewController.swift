import AppKit

// MARK: - Window Controller (keeps window alive)

final class AnnotationWindowController: NSWindowController, NSWindowDelegate {

    static var current: AnnotationWindowController?
    private var didAutoSave = false
    var annotationVC: AnnotationViewController?

    static func show(screenshot: NSImage, at rect: CGRect, on screen: NSScreen) {
        current = nil // release previous

        // Window is bigger than the screenshot to fit the toolbar below
        let toolbarH: CGFloat = 46
        let winRect = CGRect(
            x: rect.origin.x,
            y: rect.origin.y - toolbarH - 4,
            width: max(rect.width, 580),
            height: rect.height + toolbarH + 4
        )

        let win = NSPanel(
            contentRect: winRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Use screenSaver-1 so it appears above normal windows but doesn't fight the overlay
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        // Never let the panel land off-screen (small selections near screen edges)
        let visible = screen.visibleFrame
        win.setFrameOrigin(CGPoint(
            x: min(max(winRect.origin.x, visible.minX + 4), visible.maxX - winRect.width - 4),
            y: min(max(winRect.origin.y, visible.minY + 4), visible.maxY - winRect.height - 4)
        ))
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let vc = AnnotationViewController(screenshot: screenshot, screenshotSize: rect.size, toolbarHeight: toolbarH)
        win.contentViewController = vc

        let wc = AnnotationWindowController(window: win)
        wc.annotationVC = vc
        win.delegate = wc
        current = wc             // assign BEFORE showWindow so it's retained
        wc.showWindow(nil)
        win.makeKeyAndOrderFront(nil)
        // NOTE: do NOT call NSApp.activate() — it kills the menu bar icon on LSUIElement apps
    }

    func dismiss() {
        // NSColorPanel does not retain its target - detach before the VC dies
        // so a later color-panel interaction can never hit freed memory.
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        close()
        AnnotationWindowController.current = nil
    }

    func windowWillClose(_ notification: Notification) {
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        defer { AnnotationWindowController.current = nil }
        guard !didAutoSave, let vc = annotationVC else { return }
        didAutoSave = true

        // Auto-save honors Preferences > "Auto-save screenshot to folder".
        guard PreferencesManager.shared.autoSave else { return }
        let folder = PreferencesManager.shared.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = folder.appendingPathComponent("Screenshot \(f.string(from: Date())).png")
        guard let tiff = vc.canvasImage().tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

// MARK: - View Controller

final class AnnotationViewController: NSViewController {

    private let screenshot: NSImage
    private let screenshotSize: CGSize
    private let toolbarHeight: CGFloat

    private var canvas: DrawingCanvas!
    private var selectedToolButton: NSButton?
    private var buttonTools: [NSButton: DrawingTool] = [:]

    func canvasImage() -> NSImage { canvas.renderedImage() }

    init(screenshot: NSImage, screenshotSize: CGSize, toolbarHeight: CGFloat) {
        self.screenshot = screenshot
        self.screenshotSize = screenshotSize
        self.toolbarHeight = toolbarHeight
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let totalHeight = screenshotSize.height + toolbarHeight + 4
        view = NSView(frame: CGRect(origin: .zero, size: CGSize(width: screenshotSize.width, height: totalHeight)))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackground()
        setupCanvas()
        setupToolbar()
    }

    // MARK: - Setup

    private func setupBackground() {
        // White border around screenshot
        let border = NSView(frame: CGRect(
            x: -1, y: toolbarHeight + 3,
            width: screenshotSize.width + 2, height: screenshotSize.height + 2
        ))
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor.white.cgColor
        view.addSubview(border)
    }

    private func setupCanvas() {
        canvas = DrawingCanvas(frame: CGRect(
            origin: CGPoint(x: 0, y: toolbarHeight + 4),
            size: screenshotSize
        ))
        canvas.screenshot = screenshot
        view.addSubview(canvas)
    }

    private func setupToolbar() {
        // Toolbar background
        let barWidth = max(view.bounds.width, 580)
        let bar = NSView(frame: CGRect(x: 0, y: 0, width: barWidth, height: toolbarHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.15, alpha: 0.95).cgColor
        bar.layer?.cornerRadius = 6
        view.addSubview(bar)

        // --- Draw tools (left side) ---
        let drawTools: [(String, DrawingTool, String)] = [
            ("arrow.up.right",      ArrowTool(),     "Arrow"),
            ("rectangle",           RectangleTool(), "Rect"),
            ("circle",              EllipseTool(),   "Ellipse"),
            ("line.diagonal",       LineTool(),      "Line"),
            ("pencil",              PencilTool(),    "Pencil"),
            ("highlighter",         MarkerTool(),    "Marker"),
            ("character.cursor.ibeam", TextTool(),   "Text"),
        ]

        var x: CGFloat = 6
        for (icon, tool, tip) in drawTools {
            let btn = toolbarButton(icon: icon, tooltip: tip, size: 30)
            btn.frame = CGRect(x: x, y: 5, width: 30, height: 30)
            btn.action = #selector(selectDrawTool(_:))
            btn.target = self
            buttonTools[btn] = tool
            bar.addSubview(btn)
            x += 33
        }

        // Color picker
        let colorBtn = toolbarButton(icon: "paintpalette", tooltip: "Color", size: 30)
        colorBtn.frame = CGRect(x: x + 4, y: 5, width: 30, height: 30)
        colorBtn.action = #selector(pickColor)
        colorBtn.target = self
        bar.addSubview(colorBtn)
        x += 38

        // Stroke/text size control (S / M / L)
        let sizeControl = NSSegmentedControl(
            labels: ["S", "M", "L"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(strokeSizeChanged(_:))
        )
        sizeControl.selectedSegment = 1
        sizeControl.frame = CGRect(x: x + 4, y: 6, width: 92, height: 26)
        bar.addSubview(sizeControl)
        x += 102

        // Undo
        let undoBtn = toolbarButton(icon: "arrow.uturn.backward", tooltip: "Undo", size: 30)
        undoBtn.frame = CGRect(x: x + 4, y: 5, width: 30, height: 30)
        undoBtn.action = #selector(undoAction)
        undoBtn.target = self
        bar.addSubview(undoBtn)

        // --- Action buttons (right side) ---
        let rightActions: [(String, String, Selector)] = [
            ("xmark",                 "Close",  #selector(closeAction)),
            ("checkmark.circle",      "Save + Copy", #selector(saveAndCopyAction)),
            ("square.and.arrow.down", "Save",   #selector(saveAction)),
            ("doc.on.clipboard",      "Copy",   #selector(copyAction)),
            ("arrow.up.to.line",      "Upload", #selector(uploadAction)),
        ]

        var rx: CGFloat = barWidth - 6
        for (icon, tip, sel) in rightActions {
            rx -= 33
            let btn = toolbarButton(icon: icon, tooltip: tip, size: 30)
            btn.frame = CGRect(x: rx, y: 5, width: 30, height: 30)
            btn.action = sel
            btn.target = self
            bar.addSubview(btn)
        }
    }

    private func toolbarButton(icon: String, tooltip: String, size: CGFloat) -> NSButton {
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
        // Hover highlight
        btn.layer?.backgroundColor = NSColor.clear.cgColor
        return btn
    }

    // MARK: - Actions

    @objc private func selectDrawTool(_ sender: NSButton) {
        if let tool = buttonTools[sender] {
            canvas.selectedTool = tool
        }
        selectedToolButton?.layer?.backgroundColor = NSColor.clear.cgColor
        sender.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        selectedToolButton = sender
    }

    @objc private func strokeSizeChanged(_ sender: NSSegmentedControl) {
        // S / M / L -> 0.6x / 1.0x / 1.8x stroke width and text size
        let scales: [CGFloat] = [0.6, 1.0, 1.8]
        canvas.lineWidthScale = scales[sender.selectedSegment]
    }

    @objc private func pickColor() {
        NSColorPanel.shared.makeKeyAndOrderFront(nil)
        NSColorPanel.shared.setTarget(self)
        NSColorPanel.shared.setAction(#selector(colorChanged(_:)))
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        canvas.selectedColor = sender.color
    }

    @objc private func undoAction() { canvas.undo() }

    @objc private func copyAction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([canvas.renderedImage()])
        showToast("Copied!")
    }

    @objc private func saveAction() {
        let folder = PreferencesManager.shared.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = folder.appendingPathComponent("Screenshot \(f.string(from: Date())).png")
        guard let tiff = canvas.renderedImage().tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        showToast("Saved!")
    }

    @objc private func uploadAction() {
        showToast("Uploading…")
        UploadService.shared.upload(image: canvas.renderedImage()) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    self?.showToast("Link copied! 🎉")
                case .failure(let error):
                    self?.showToast(error.localizedDescription)
                }
            }
        }
    }

    @objc private func saveAndCopyAction() {
        let png = renderedPNG()
        let folder = PreferencesManager.shared.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        try? png.write(to: folder.appendingPathComponent("Screenshot \(f.string(from: Date())).png"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([canvas.renderedImage()])
        showToast("Saved + Copied!")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            (self?.view.window?.windowController as? AnnotationWindowController)?.dismiss()
        }
    }

    private func renderedPNG() -> NSData {
        let img = canvas.renderedImage()
        guard let tiff = img.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else {
            return NSData()
        }
        return png as NSData
    }

    @objc private func closeAction() {
        (view.window?.windowController as? AnnotationWindowController)?.dismiss()
    }

    // MARK: - Toast

    private func showToast(_ msg: String) {
        let label = NSTextField(labelWithString: " \(msg) ")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        label.isBezeled = false; label.isEditable = false
        label.wantsLayer = true; label.layer?.cornerRadius = 4
        label.sizeToFit()
        label.frame.origin = CGPoint(
            x: view.bounds.midX - label.frame.width/2,
            y: toolbarHeight + 8
        )
        view.addSubview(label)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            label.removeFromSuperview()
        }
    }
}
