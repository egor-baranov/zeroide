import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @State private var contentWidth: CGFloat = 0
    @State private var sidebarButtonWidth: CGFloat = 0
    @State private var chatButtonWidth: CGFloat = 0

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
            WindowTitleUpdater(title: appModel.workspaceURL?.lastPathComponent ?? "")
                .frame(width: 0, height: 0)
        )
        .background(contentWidthReader)
        .onPreferenceChange(ContentWidthPreferenceKey.self) { contentWidth = $0 }
        .overlay(TabSwitcherShortcuts())
        .toolbar { workspaceToolbar }
        .toolbarBackground(Color.ideBackground, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Group {
                if appModel.workspaceURL != nil {
                    sidebarToolbarButton
                        .background(WidthObserver(width: $sidebarButtonWidth))
                } else {
                    EmptyView()
                }
            }
        }

        ToolbarItem(placement: .navigation) {
            WorkspacePickerButton(currentProjectName: currentProjectName)
        }

        ToolbarItem(placement: .principal) {
            Group {
                if appModel.workspaceURL != nil {
                    CommandBar(path: currentPath)
                        .frame(height: 26)
                        .commandBarWidth(commandBarWidthEstimate)
                } else {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
        }

        ToolbarItem(placement: .automatic) {
            HStack {
                if appModel.workspaceURL != nil {
                    Spacer(minLength: 0)
                    chatToolbarButton
                        .background(WidthObserver(width: $chatButtonWidth))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

private var commandBarWidthEstimate: CGFloat? {
        guard contentWidth > 0 else { return nil }
        let reserved = sidebarButtonWidth + chatButtonWidth + toolbarSpacingAllowance
        let available = contentWidth - reserved
        return available > 0 ? available : nil
    }

    private var toolbarSpacingAllowance: CGFloat { 48 }

    private var contentWidthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ContentWidthPreferenceKey.self, value: proxy.size.width)
        }
    }

    private var sidebarToolbarButton: some View {
        Button(action: { withAnimation { showSidebar.toggle() } }) {
            Image(systemName: "sidebar.leading")
                .foregroundStyle(showSidebar ? .primary : .secondary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(showSidebar ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("s", modifiers: [.command])
        .padding(.vertical, 6)
    }

    private var chatToolbarButton: some View {
        Button(action: toggleChat) {
            Label("Chat", systemImage: "bubble.left.fill")
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 80)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(showChatSidebar ? Color.ideAccent.opacity(0.2) : Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    private var currentPath: String {
        if let webURL = appModel.activeWebURL {
            return webURL.absoluteString
        }
        if let fileURL = appModel.focusedFileURL {
            return fileURL.path
        }
        if let workspace = appModel.workspaceURL {
            return workspace.path
        }
        return "No file open"
    }

    private var currentProjectName: String? {
        appModel.workspaceURL?.lastPathComponent
    }

    private struct WorkspacePickerButton: View {
        @EnvironmentObject private var appModel: AppModel
        let currentProjectName: String?
        @State private var showMenu = false
        @State private var hovered = false

        var body: some View {
            Button(action: { showMenu.toggle() }) {
                HStack(spacing: 4) {
                    Text(currentProjectName ?? "Select Project")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(hovered ? 0.12 : 0))
                )
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .popover(isPresented: $showMenu, arrowEdge: .bottom) {
                WorkspaceMenuContent(
                    currentWorkspace: appModel.workspaceURL,
                    recentWorkspaces: appModel.recentWorkspaces,
                    openFolder: {
                        showMenu = false
                        DispatchQueue.main.async {
                            appModel.presentWorkspacePicker()
                        }
                    },
                    openWorkspace: { url in
                        showMenu = false
                        DispatchQueue.main.async {
                            appModel.openRecentWorkspace(url)
                        }
                    }
                )
                .frame(width: 320)
                .padding(.vertical, 8)
            }
        }
    }

    private struct WorkspaceMenuContent: View {
        let currentWorkspace: URL?
        let recentWorkspaces: [URL]
        let openFolder: () -> Void
        let openWorkspace: (URL) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: openFolder) {
                    Label("Open Folder…", systemImage: "folder")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)

                if let currentWorkspace {
                    SectionHeader("Open Project")
                    Button {
                        openWorkspace(currentWorkspace)
                    } label: {
                        WorkspaceMenuRow(name: currentWorkspace.lastPathComponent, path: currentWorkspace.path)
                    }
                    .buttonStyle(.plain)
                }

                if !recentWorkspaces.isEmpty {
                    SectionHeader("Recent Projects")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recentWorkspaces, id: \.self) { url in
                            Button {
                                openWorkspace(url)
                            } label: {
                                WorkspaceMenuRow(name: url.lastPathComponent, path: url.path)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private struct SectionHeader: View {
        let title: String

        init(_ title: String) {
            self.title = title
        }

        var body: some View {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private struct WorkspaceMenuRow: View {
        let name: String
        let path: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                Text(path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
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

            EditorWorkspaceView()
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
    @EnvironmentObject private var appModel: AppModel
    let path: String
    @State private var showPalette = false

    var body: some View {
        ZStack(alignment: .center) {
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
            Text(path)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .contentShape(Rectangle())
        .onTapGesture { showPalette = true }
        .background(
            CommandBarShortcutCatcher(activate: { showPalette = true })
        )
        .popover(isPresented: $showPalette, arrowEdge: .top) {
            CommandPaletteView(
                isPresented: $showPalette,
                currentPath: path
            )
            .environmentObject(appModel)
            .frame(width: 460, height: 360)
        }
    }
}

private struct ContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct WidthObserver: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { width = $0 }
        }
    }
}

private extension View {
    @ViewBuilder
    func commandBarWidth(_ width: CGFloat?) -> some View {
        if let width, width > 0 {
            frame(width: width)
        } else {
            self
        }
    }
}

private struct EditorWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(appModel.panes) { pane in
                PaneContainer(pane: pane)

                if pane.id != appModel.panes.last?.id {
                    Divider()
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

private struct PaneContainer: View {
    @EnvironmentObject private var appModel: AppModel
    let pane: EditorPane
    @State private var isPaneTarget = false
    @State private var isSplitLeftTarget = false
    @State private var isSplitRightTarget = false
    private let dropTypes: [UTType] = [.plainText, .fileURL, .url]

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBar(pane: pane, onTargetChange: { isTargeted in
                isPaneTarget = isTargeted
            })
            Divider()
            EditorSurface(pane: pane)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.ideAccent, lineWidth: 2)
                        .padding(3)
                        .opacity(isPaneTarget ? 0.4 : 0)
                        .animation(.easeInOut(duration: 0.2), value: isPaneTarget)

                    HStack(spacing: 0) {
                        splitZone(width: geo.size.width * 0.3,
                                  isTargeted: $isSplitLeftTarget,
                                  action: { providers in
                                      appModel.handleDropIntoNewPaneBefore(providers, before: pane)
                                  })

                        Color.clear
                            .frame(width: geo.size.width * 0.4)
                            .allowsHitTesting(false)

                        splitZone(width: geo.size.width * 0.3,
                                  isTargeted: $isSplitRightTarget,
                                  action: { providers in
                                      appModel.handleDropIntoNewPane(providers, after: pane)
                                  })
                    }
                }
            }
        )
        .contentShape(Rectangle())
        .onDrop(of: dropTypes, isTargeted: $isPaneTarget) { providers in
            appModel.handleDrop(providers, into: pane)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                appModel.activePaneID = pane.id
            }
        )
    }

    private func splitZone(width: CGFloat,
                           isTargeted: Binding<Bool>,
                           action: @escaping ([NSItemProvider]) -> Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.ideAccent, lineWidth: 2)
                .padding(.vertical, 6)
                .opacity(isTargeted.wrappedValue ? 0.6 : 0)
                .animation(.easeInOut(duration: 0.2), value: isTargeted.wrappedValue)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .allowsHitTesting(isTargeted.wrappedValue)
        .onDrop(of: dropTypes, isTargeted: isTargeted, perform: action)
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

            Button(action: { appModel.createStartTab() }) {
                Color.clear.frame(width: 0, height: 0)
            }
            .keyboardShortcut("t", modifiers: [.command])
            .buttonStyle(.plain)
            .opacity(0)

            Button(action: appModel.closeActiveTab) {
                Color.clear.frame(width: 0, height: 0)
            }
            .keyboardShortcut("w", modifiers: [.command])
            .buttonStyle(.plain)
            .opacity(0)
        }
    }
}


private struct EditorSurface: View {
    @EnvironmentObject private var appModel: AppModel
    let pane: EditorPane

    private var showWorkspacePlaceholder: Bool {
        appModel.workspaceURL == nil
    }

    private var showFilePlaceholder: Bool {
        appModel.workspaceURL != nil
        && pane.activeTab?.fileURL == nil
        && !(pane.activeTab?.isCanvas ?? false)
        && pane.activeTab?.webURL == nil
    }

    private var showStartTab: Bool {
        pane.activeTab?.isCanvas ?? false
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.ideEditorBackground.ignoresSafeArea()

            switch appModel.editorMode {
            case .native:
                if showWorkspacePlaceholder {
                    ZeroWelcomeView()
                } else if let webURL = pane.activeTab?.webURL {
                    WebTabView(url: webURL)
                } else if showStartTab {
                    StartTabView(
                        addTabAction: { appModel.createStartTab() },
                        openWorkspaceAction: appModel.presentWorkspacePicker
                    )
                } else if showFilePlaceholder {
                    EditorPlaceholderView(
                        title: "No file selected",
                        message: "Pick a file from the sidebar to start editing."
                    )
                } else if let tab = pane.activeTab {
                    NativeEditorView(tab: tab)
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
private struct CommandPaletteView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var isPresented: Bool
    let currentPath: String
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var quickActions: [PaletteAction] {
        [
            PaletteAction(title: "Go to File", subtitle: nil, systemImage: "doc.text.magnifyingglass", shortcut: "⌘E", action: {}),
            PaletteAction(title: "Show and Run Commands", subtitle: nil, systemImage: "command", shortcut: "⇧⌘P", action: {}),
            PaletteAction(title: "Search for Text", subtitle: nil, systemImage: "text.magnifyingglass", shortcut: "⇧⌘F", action: {}),
            PaletteAction(title: "Go to Symbol in Editor", subtitle: nil, systemImage: "at", shortcut: "⌘@", action: {}),
            PaletteAction(title: "Start Debugging", subtitle: "debug", systemImage: "play.circle", shortcut: "F5", action: {}),
            PaletteAction(title: "Run Task", subtitle: "task", systemImage: "hammer", shortcut: "⇧⌘B", action: {})
        ]
    }

    private var filteredTabs: [EditorTab] {
        let tabs = appModel.tabs
        guard !query.isEmpty else { return tabs }
        let lower = query.lowercased()
        return tabs.filter { $0.title.lowercased().contains(lower) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Search files, content, and symbols", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .focused($searchFocused)

                Text(currentPath.isEmpty ? "No location" : currentPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(quickActions) { action in
                    Button(action: {
                        action.action?()
                        isPresented = false
                    }) {
                        HStack {
                            Label(action.title, systemImage: action.systemImage)
                            if let subtitle = action.subtitle {
                                Text(subtitle).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let shortcut = action.shortcut {
                                Text(shortcut).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Text("Recently Opened")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if filteredTabs.isEmpty {
                        Text("No tabs available")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filteredTabs) { tab in
                            Button {
                                appModel.activate(tab: tab)
                                isPresented = false
                            } label: {
                                HStack(alignment: .center, spacing: 8) {
                                    Image(systemName: tab.isCanvas ? "square.on.square.dashed" : "doc.text")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tab.title)
                                            .font(.system(size: 13, weight: .semibold))
                                        if let workspace = appModel.workspaceURL {
                                            Text(workspace.lastPathComponent)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { searchFocused = true }
        .onExitCommand { isPresented = false }
    }
}

private struct PaletteAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let systemImage: String
    let shortcut: String?
    let action: (() -> Void)?
}
