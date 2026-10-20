import AppKit
import SwiftUI

/// Apply the opening size after SwiftUI has attached the content and restored the window.
struct OpeningWindowSize: NSViewRepresentable {
    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ nsView: SizingView, context: Context) {}

    final class SizingView: NSView {
        private weak var sizedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== sizedWindow else { return }
            sizedWindow = window
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window,
                      let screen = window.screen ?? NSScreen.main else { return }
                // Respect the display's menu bar and Dock; the window remains resizable.
                window.setFrame(screen.visibleFrame, display: true)
            }
        }
    }
}
