import AppKit
import ScreenCaptureKit

final class CaptureManager {

    private var captureWindow: CaptureWindow?
    private var sessionActive = false

    func startCapture() {
        guard !sessionActive else { return } // ignore hotkey mid-session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showOverlay()
        }
    }

    private func showOverlay() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        sessionActive = true

        let window = CaptureWindow(screen: screen)
        captureWindow = window

        window.sessionView.onSessionComplete = { [weak self, weak window] in
            self?.endSession(window)
        }
        window.sessionView.onFreezeRequested = { [weak self, weak window] rect in
            guard let self, let window else { return }
            Task { @MainActor in
                do {
                    let shot = try await self.captureRegionImage(
                        rect: rect, screen: screen, excluding: window
                    )
                    window.sessionView.beginEditing(
                        image: shot.cgImage,
                        pixelSize: shot.pixelSize,
                        pointSize: rect.size
                    )
                } catch {
                    self.endSession(window)
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Capture failed"
                        alert.informativeText = error.localizedDescription
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.sessionView)
    }

    private func endSession(_ window: CaptureWindow?) {
        sessionActive = false
        window?.close()
        if captureWindow === window { captureWindow = nil }
    }

    // MARK: - Region capture

    private struct FrozenShot {
        let cgImage: CGImage
        let pixelSize: CGSize
    }

    /// Captures the selected region, excluding Nimbus' own overlay windows,
    /// via ScreenCaptureKit. Falls back to the legacy CGWindowList API if SCK
    /// fails (deprecated but still functional).
    private func captureRegionImage(
        rect: CGRect, screen: NSScreen, excluding window: CaptureWindow
    ) async throws -> FrozenShot {
        let scale = screen.backingScaleFactor

        // Convert the selection from AppKit's bottom-left global coordinates
        // to CG's top-left global coordinates.
        let menuBarHeight = NSScreen.screens.first?.frame.height ?? 0
        let globalRect = CGRect(
            x: rect.minX + screen.frame.minX,
            y: rect.minY + screen.frame.minY,
            width: rect.width,
            height: rect.height
        )
        let cgRect = CGRect(
            x: globalRect.minX,
            y: menuBarHeight - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: {
                $0.frame.intersects(cgRect) || $0.frame.contains(cgRect.origin)
            }), let scWindow = content.windows.first(where: {
                $0.windowID == window.windowNumber
            }) else {
                throw NSError(
                    domain: "com.matthewdresden.nimbus", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Display or window not found"]
                )
            }

            let filter = SCContentFilter(display: display, excludingWindows: [scWindow])
            let config = SCStreamConfiguration()
            config.width = Int(display.frame.width * scale)
            config.height = Int(display.frame.height * scale)
            config.showsCursor = false

            let full = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )

            // Crop the full-resolution display shot down to the region.
            let crop = CGRect(
                x: cgRect.minX * scale,
                y: cgRect.minY * scale,
                width: cgRect.width * scale,
                height: cgRect.height * scale
            )
            guard let cropped = full.cropping(to: crop) else {
                throw NSError(
                    domain: "com.matthewdresden.nimbus", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to crop capture"]
                )
            }
            return FrozenShot(
                cgImage: cropped,
                pixelSize: CGSize(width: crop.width, height: crop.height)
            )
        } catch let err as NSError where err.domain != "com.matthewdresden.nimbus" || err.code != 1 {
            // SCK failure - fall back to legacy capture before giving up.
        } catch {
            throw error
        }

        guard let legacy = CGWindowListCreateImage(
            cgRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution
        ) else {
            throw NSError(
                domain: "com.matthewdresden.nimbus", code: 3,
                userInfo: [NSLocalizedDescriptionKey: """
                    Screen capture unavailable. Grant Screen Recording permission in \
                    System Settings > Privacy & Security > Screen Recording, then retry.
                    """
                ]
            )
        }
        return FrozenShot(
            cgImage: legacy,
            pixelSize: CGSize(width: rect.width * scale, height: rect.height * scale)
        )
    }
}
