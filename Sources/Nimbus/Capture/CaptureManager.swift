import AppKit

final class CaptureManager {

    private var captureWindow: CaptureWindow?

    func startCapture() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showOverlay()
        }
    }

    private func showOverlay() {
        // Capture on the screen the cursor is currently on (multi-monitor support).
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        captureWindow = CaptureWindow(screen: screen)
        captureWindow?.onSelectionComplete = { [weak self] rect in
            self?.captureRegion(rect, on: screen)
        }
        captureWindow?.onCancelled = { [weak self] in
            self?.captureWindow = nil
        }
        captureWindow?.makeKeyAndOrderFront(nil)
        captureWindow?.makeFirstResponder(captureWindow?.contentView)
    }

    private func captureRegion(_ selectionRect: CGRect, on screen: NSScreen) {
        captureWindow?.close()
        captureWindow = nil

        // Wait for overlay to fully disappear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Convert NSView coords (bottom-left origin) to CGWindowListCreateImage coords
            let cgRect = CGRect(
                x: selectionRect.origin.x + screen.frame.origin.x,
                y: screen.frame.height - selectionRect.origin.y - selectionRect.height,
                width: selectionRect.width,
                height: selectionRect.height
            )

            guard let cgImage = CGWindowListCreateImage(
                cgRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution
            ) else {
                // Screen Recording permission not granted
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Screen Recording Permission Required"
                    alert.informativeText = "Go to System Settings → Privacy & Security → Screen Recording and enable Nimbus."
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                }
                return
            }

            let image = NSImage(cgImage: cgImage, size: selectionRect.size)
            AnnotationWindowController.show(screenshot: image, at: selectionRect, on: screen)
        }
    }
}
