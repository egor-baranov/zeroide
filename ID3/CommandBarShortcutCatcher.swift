import SwiftUI

struct CommandBarShortcutCatcher: NSViewRepresentable {
    let onFocus: () -> Void
    let onBlur: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFocus: onFocus, onBlur: onBlur)
    }

    func makeNSView(context: Context) -> NSView {
        let view = ShortcutView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        let onFocus: () -> Void
        let onBlur: () -> Void
        init(onFocus: @escaping () -> Void, onBlur: @escaping () -> Void) {
            self.onFocus = onFocus
            self.onBlur = onBlur
        }
    }

    final class ShortcutView: NSView {
        weak var coordinator: Coordinator?

        override var acceptsFirstResponder: Bool { true }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "l" {
                coordinator?.onFocus()
                return true
            }
            if event.keyCode == 53 { // escape
                coordinator?.onBlur()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}
