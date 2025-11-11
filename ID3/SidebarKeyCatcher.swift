import SwiftUI

struct SidebarKeyCatcher: NSViewRepresentable {
    let toggleSearch: () -> Void

    func makeNSView(context: Context) -> SidebarKeyView {
        let view = SidebarKeyView()
        view.toggleSearch = toggleSearch
        return view
    }

    func updateNSView(_ nsView: SidebarKeyView, context: Context) {}
}

final class SidebarKeyView: NSView {
    var toggleSearch: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
            toggleSearch?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
