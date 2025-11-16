import SwiftUI
import AppKit

struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            updateWindow(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            updateWindow(nsView.window)
        }
    }

    private func updateWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }
}
