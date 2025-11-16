import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showSidebar = true
    @State private var showChatSidebar = false
    @State private var sidebarWidth: CGFloat = 280
    @State private var chatWidth: CGFloat = 320
    @State private var sidebarDragOrigin: CGFloat?
    @State private var chatDragOrigin: CGFloat?
    @State private var chatMessages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "Hi! I'm here if you need help or want to jot notes while you work.")
    ]

    var body: some View {
        Group {
            if appModel.workspaceURL == nil {
                ZeroWelcomeView()
            } else {
                mainWorkspaceView
            }
        }
        .frame(minWidth: 1080, minHeight: 720)
        .animation(.easeInOut(duration: 0.25), value: showSidebar)
        .animation(.easeInOut(duration: 0.25), value: showChatSidebar)
        .background(
            WindowTitleUpdater(title: appModel.workspaceURL?.lastPathComponent ?? "ID3")
                .frame(width: 0, height: 0)
        )
        .overlay(TabSwitcherShortcuts())
    }

    private var mainWorkspaceView: some View {
        HStack(spacing: 0) {
            if showSidebar {
                WorkspaceSidebar()
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.ideSidebar)
                    .overlay(alignment: .trailing) {
                        DragHandle(edge: .trailing)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if sidebarDragOrigin == nil { sidebarDragOrigin = sidebarWidth }
                                        let base = sidebarDragOrigin ?? sidebarWidth
                                        sidebarWidth = clamp(base + value.translation.width, min: 200, max: 520)
                                    }
                                    .onEnded { _ in sidebarDragOrigin = nil }
                            )
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                EditorToolbar(
                    toggleSidebar: { withAnimation { showSidebar.toggle() } },
                    sidebarVisible: showSidebar,
                    toggleChat: toggleChat,
                    chatVisible: showChatSidebar
                )
                VStack(spacing: 0) {
                    EditorTabBar()
                    Divider()
                    EditorSurface()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ideBackground)

            if showChatSidebar {
                ChatSidebar(
                    messages: $chatMessages,
                    closeAction: { showChatSidebar = false }
                )
                    .frame(width: chatWidth)
                    .background(Color.ideSidebar)
                    .overlay(alignment: .leading) {
                        DragHandle()
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if chatDragOrigin == nil { chatDragOrigin = chatWidth }
                                        let base = chatDragOrigin ?? chatWidth
                                        chatWidth = clamp(base - value.translation.width, min: 240, max: 520)
                                    }
                                    .onEnded { _ in chatDragOrigin = nil }
                            )
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private func toggleChat() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showChatSidebar.toggle()
        }
    }
}

private struct EditorToolbar: View {
    @EnvironmentObject private var appModel: AppModel
    let toggleSidebar: () -> Void
    let sidebarVisible: Bool
    let toggleChat: () -> Void
    let chatVisible: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.leading")
                    .foregroundStyle(sidebarVisible ? .primary : .secondary)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(sidebarVisible ? Color.primary.opacity(0.08) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: [.command])

            CommandBar(path: currentPath)
                .frame(height: 26)

            Button(action: toggleChat) {
                Label("Chat", systemImage: "bubble.left.fill")
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(chatVisible ? Color.ideAccent.opacity(0.2) : Color.secondary.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.ideBackground)
    }

    private var currentPath: String {
        guard let url = appModel.selectedFileURL ?? appModel.workspaceURL else {
            return "No file open"
        }
        return url.path
    }
}

private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
    Swift.min(Swift.max(value, min), max)
}

private struct DragHandle: View {
    enum Edge {
        case leading, trailing
    }

    var edge: Edge = .leading

    var body: some View {
        ZStack(alignment: edge == .leading ? .leading : .trailing) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .contentShape(Rectangle())
    }
}

private struct CommandBar: View {
    let path: String
    @State private var requestFocus = false
    @State private var requestBlur = false

    var body: some View {
        ZStack(alignment: .center) {
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
            CommandBarTextField(text: path, focusTrigger: $requestFocus, blurTrigger: $requestBlur)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            requestFocus = true
        }
        .background(
            CommandBarShortcutCatcher(
                onFocus: { requestFocus = true },
                onBlur: { requestBlur = true }
            )
        )
    }
}

private struct CommandBarTextField: NSViewRepresentable {
    var text: String
    @Binding var focusTrigger: Bool
    @Binding var blurTrigger: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.isSelectable = true
        field.lineBreakMode = .byTruncatingHead
        field.drawsBackground = false
        field.isBordered = false
        field.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        field.textColor = NSColor.secondaryLabelColor
        field.alignment = .center
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if focusTrigger, let window = nsView.window {
            window.makeFirstResponder(nsView)
            nsView.selectText(nil)
            DispatchQueue.main.async {
                focusTrigger = false
            }
        }
        if blurTrigger, let window = nsView.window {
            window.makeFirstResponder(nil)
            DispatchQueue.main.async {
                blurTrigger = false
            }
        }
    }
}

private struct TabSwitcherShortcuts: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack {
            Button(action: appModel.activateNextTab) {
                Color.clear.frame(width: 0, height: 0)
            }
            .keyboardShortcut(.tab, modifiers: [.control])
            .buttonStyle(.plain)
            .opacity(0)

            Button(action: appModel.activatePreviousTab) {
                Color.clear.frame(width: 0, height: 0)
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .buttonStyle(.plain)
            .opacity(0)
        }
    }
}


private struct EditorSurface: View {
    @EnvironmentObject private var appModel: AppModel

    private var showWorkspacePlaceholder: Bool {
        appModel.workspaceURL == nil
    }

    private var showFilePlaceholder: Bool {
        appModel.workspaceURL != nil && appModel.selectedFileURL == nil && !appModel.isShowingStartTab
    }

    private var showStartTab: Bool {
        appModel.isShowingStartTab
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.ideEditorBackground.ignoresSafeArea()

            switch appModel.editorMode {
            case .native:
                if showWorkspacePlaceholder {
                    ZeroWelcomeView()
                } else if showStartTab {
                    StartTabView(
                        addTabAction: appModel.createStartTab,
                        openWorkspaceAction: appModel.presentWorkspacePicker
                    )
                } else if showFilePlaceholder {
                    EditorPlaceholderView(
                        title: "No file selected",
                        message: "Pick a file from the sidebar to start editing."
                    )
                } else {
                    NativeEditorView()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            case .workbench:
                workbenchSurface
            }

            if case let .error(message) = appModel.state {
                ErrorBanner(message: message)
                    .padding(16)
            }
        }
    }

    @ViewBuilder
    private var workbenchSurface: some View {
        switch Result(catching: { try appModel.configuration() }) {
        case .success(let configuration):
            WorkbenchWebView(configuration: configuration, appModel: appModel)
                .id(appModel.reloadToken)
                .background(Color.ideEditorBackground)
        case .failure(let error):
            WorkbenchFallbackView(message: error.localizedDescription)
        }
    }
}

private struct WorkbenchFallbackView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Workbench unavailable")
                .font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
