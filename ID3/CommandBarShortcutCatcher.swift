import SwiftUI

struct CommandBarShortcutCatcher: NSViewRepresentable {
    let activate: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(activate: activate)
    }

    func makeNSView(context: Context) -> NSView {
        let view = ShortcutView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        let activate: () -> Void
        init(activate: @escaping () -> Void) {
            self.activate = activate
        }
    }

    final class ShortcutView: NSView {
        weak var coordinator: Coordinator?

        override var acceptsFirstResponder: Bool { true }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "l" {
                coordinator?.activate()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}
