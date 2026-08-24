import AppKit

// Fullscreen transparent overlay window hosting a CaptureSessionView.
final class CaptureWindow: NSWindow {

    let sessionView: CaptureSessionView

    var windowNumberValue: Int { windowNumber }

    init(screen: NSScreen) {
        sessionView = CaptureSessionView(frame: screen.frame)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = sessionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
