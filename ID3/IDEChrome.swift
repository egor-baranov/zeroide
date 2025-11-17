import SwiftUI
import UniformTypeIdentifiers

struct IDEWindowToolbar: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.ideBackground)
    }
}

struct EditorTabBar: View {
    @EnvironmentObject private var appModel: AppModel
    let pane: EditorPane
    var onTargetChange: (Bool) -> Void = { _ in }
    @State private var tabWidths: [EditorTab.ID: CGFloat] = [:]
    @State private var availableWidth: CGFloat = 0
    @State private var isDropTarget = false
    @State private var isTabDragActive = false
    @State private var dragHoverCount = 0
    private let overflowThreshold: CGFloat = 280

    var body: some View {
        HStack(spacing: 8) {
            if pane.tabs.isEmpty {
                HStack {
                    TabInsertTarget(
                        index: 0,
                        pane: pane,
                        width: 120,
                        onDrop: { identifier, idx, pane in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appModel.moveTab(withIdentifier: identifier, toIndex: idx, in: pane)
                            }
                        },
                        isDragActive: $isTabDragActive,
                        dragStateChanged: handleTabDragHoverChange
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { proxy in
                    HStack(spacing: 4) {
                    TabInsertTarget(
                        index: 0,
                        pane: pane,
                        width: averageTabWidth,
                        onDrop: { id, idx, pane in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appModel.moveTab(withIdentifier: id, toIndex: idx, in: pane)
                            }
                        },
                        isDragActive: $isTabDragActive,
                        dragStateChanged: handleTabDragHoverChange
                    )
                        ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { idx, tab in
                        TabDropWrapper(
                            pane: pane,
                            tabIndex: idx,
                            estimatedWidth: tabWidths[tab.id] ?? averageTabWidth,
                            isDragActive: $isTabDragActive,
                            dragStateChanged: handleTabDragHoverChange,
                            moveAction: { identifier, insertIndex, pane in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appModel.moveTab(withIdentifier: identifier, toIndex: insertIndex, in: pane)
                                }
                            }
                        ) {
                            EditorTabChip(
                                tab: tab,
                                isActive: pane.activeTabID == tab.id,
                                closeAction: { appModel.closeTab(tab) }
                            )
                        }
                        .id(tab.id)
                        .onTapGesture {
                            appModel.activate(tab: tab)
                        }
                        TabInsertTarget(
                            index: idx + 1,
                            pane: pane,
                            width: tabWidths[tab.id] ?? averageTabWidth,
                            onDrop: { identifier, insertIndex, pane in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appModel.moveTab(withIdentifier: identifier, toIndex: insertIndex, in: pane)
                                }
                            },
                            isDragActive: $isTabDragActive,
                            dragStateChanged: handleTabDragHoverChange
                        )
                        }

                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 24, height: 32)
                    }
                    .padding(.horizontal, 8)
                    .onChange(of: pane.activeTabID) { target in
                        guard let target else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                    }
                }
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .onPreferenceChange(TabWidthPreferenceKey.self) { values in
                    tabWidths.merge(values) { _, new in new }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TabBarAvailableWidthKey.self, value: proxy.size.width)
                    }
                )
                .onPreferenceChange(TabBarAvailableWidthKey.self) { availableWidth = $0 }
            }

            if shouldShowOverflowButton {
                TabOverflowButton()
            }

            Button(action: { appModel.createStartTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 36)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.ideBackground)
        .onDrop(of: [UTType.plainText, .fileURL, .url], isTargeted: $isDropTarget) { providers in
            appModel.handleDrop(providers, into: pane)
        }
        .onChange(of: isDropTarget) { value in
            onTargetChange(value)
        }
    }
}

private extension EditorTabBar {
    var shouldShowOverflowButton: Bool {
        guard !pane.tabs.isEmpty, availableWidth > 0 else { return false }
        guard let averageWidth = tabWidths.values.average else { return false }
        let totalNeeded = averageWidth * CGFloat(pane.tabs.count)
        let reservedRight: CGFloat = 64 // plus + overflow controls
        return totalNeeded > max(availableWidth - reservedRight, 0)
    }

    var averageTabWidth: CGFloat {
        guard !tabWidths.isEmpty else { return 120 }
        let total = tabWidths.values.reduce(CGFloat(0), +)
        return total / CGFloat(tabWidths.count)
    }

    private func handleTabDragHoverChange(_ isActive: Bool) {
        dragHoverCount = max(0, dragHoverCount + (isActive ? 1 : -1))
        let active = dragHoverCount > 0
        if active != isTabDragActive {
            isTabDragActive = active
        }
    }
}

private struct TabBarAvailableWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TabInsertTarget: View {
    let index: Int
    let pane: EditorPane
    let width: CGFloat
    let onDrop: (String, Int, EditorPane) -> Void
    @Binding var isDragActive: Bool
    let dragStateChanged: (Bool) -> Void
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            if isTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.25))
            } else if isDragActive {
                Capsule()
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: 4, height: 16)
                    .opacity(0.4)
            } else {
                Color.clear
            }
        }
        .frame(width: max(isTargeted ? width : 6, 6), height: 32)
        .opacity(isTargeted ? 1 : (isDragActive ? 0.4 : 0))
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .animation(.easeInOut(duration: 0.15), value: isDragActive)
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
                return false
            }
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let nsString = object as? NSString else { return }
                let identifier = nsString as String
                DispatchQueue.main.async {
                    onDrop(identifier, index, pane)
                    }
            }
            return true
        }
        .onChange(of: isTargeted) { active in
            dragStateChanged(active)
        }
    }
}

private struct TabPlaceholderGhost: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.accentColor.opacity(0.25))
    }
}

private enum TabHoverSide {
    case left
    case right
}

private struct TabDropWrapper<Content: View>: View {
    let pane: EditorPane
    let tabIndex: Int
    let estimatedWidth: CGFloat
    @Binding var isDragActive: Bool
    let dragStateChanged: (Bool) -> Void
    let moveAction: (String, Int, EditorPane) -> Void
    @ViewBuilder var content: () -> Content
    @State private var hoverSide: TabHoverSide?
    @State private var viewWidth: CGFloat

    init(
        pane: EditorPane,
        tabIndex: Int,
        estimatedWidth: CGFloat,
        isDragActive: Binding<Bool>,
        dragStateChanged: @escaping (Bool) -> Void,
        moveAction: @escaping (String, Int, EditorPane) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.pane = pane
        self.tabIndex = tabIndex
        self.estimatedWidth = estimatedWidth
        self._isDragActive = isDragActive
        self.dragStateChanged = dragStateChanged
        self.moveAction = moveAction
        self.content = content
        _viewWidth = State(initialValue: estimatedWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            if hoverSide == .left {
                TabPlaceholderGhost()
                    .frame(width: placeholderWidth, height: 32)
            }

            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { viewWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { viewWidth = $0 }
                    }
                )

            if hoverSide == .right {
                TabPlaceholderGhost()
                    .frame(width: placeholderWidth, height: 32)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hoverSide != nil)
        .onDrop(
            of: [.plainText],
            delegate: TabHoverDropDelegate(
                pane: pane,
                tabIndex: tabIndex,
                tabWidth: max(viewWidth, 1),
                hoverSide: $hoverSide,
                moveAction: moveAction
            )
        )
        .onChange(of: hoverSide != nil) { isHovering in
            dragStateChanged(isHovering)
        }
    }

    private var placeholderWidth: CGFloat {
        guard isDragActive, hoverSide != nil else { return 0 }
        return max(min(viewWidth, 180), 80)
    }
}

private struct TabHoverDropDelegate: DropDelegate {
    let pane: EditorPane
    let tabIndex: Int
    let tabWidth: CGFloat
    @Binding var hoverSide: TabHoverSide?
    let moveAction: (String, Int, EditorPane) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        updateHoverSide(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateHoverSide(for: info)
        return nil
    }

    func dropExited(info: DropInfo) {
        DispatchQueue.main.async {
            hoverSide = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let side = determineSide(for: info)
        DispatchQueue.main.async {
            hoverSide = nil
        }
        guard let provider = info.itemProviders(for: [.plainText]).first else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let nsString = object as? NSString else { return }
            let identifier = nsString as String
            DispatchQueue.main.async {
                let insertionIndex = side == .left ? tabIndex : tabIndex + 1
                moveAction(identifier, insertionIndex, pane)
            }
        }
        return true
    }

    private func determineSide(for info: DropInfo) -> TabHoverSide {
        let mid = tabWidth / 2
        return info.location.x < mid ? .left : .right
    }

    private func updateHoverSide(for info: DropInfo) {
        let side = determineSide(for: info)
        DispatchQueue.main.async {
            hoverSide = side
        }
    }
}

private struct TabOverflowButton: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showList = false

    var body: some View {
        Button(action: { showList.toggle() }) {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showList, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(appModel.tabs) { tab in
                    Button {
                        appModel.activate(tab: tab)
                        showList = false
                    } label: {
                        HStack {
                            Text(tab.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(appModel.activeTabID == tab.id ? .white : .primary)
                            Spacer()
                            Button {
                                appModel.closeTab(tab)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(appModel.activeTabID == tab.id ? Color.accentColor : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            .frame(width: 220)
        }
    }
}

private extension Collection where Element == CGFloat {
    var average: CGFloat? {
        guard !isEmpty else { return nil }
        let sum = reduce(.zero, +)
        return sum / CGFloat(count)
    }
}

private struct EditorTabChip: View {
    @EnvironmentObject private var appModel: AppModel
    let tab: EditorTab
    let isActive: Bool
    let closeAction: () -> Void
    @State private var isHovering = false
    @State private var isCloseHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.title)
                .font(.system(size: 13, weight: .semibold))
            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(3)
                    .background(
                        Circle()
                            .fill(isCloseHovering ? Color.primary.opacity(0.15) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovering = $0 }
            .opacity(isActive ? 1 : 0.6)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .cornerRadius(8)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TabWidthPreferenceKey.self,
                    value: [tab.id: proxy.size.width]
                )
            }
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onDrag {
            NSItemProvider(object: tab.dragIdentifier as NSString)
        }
        .contextMenu {
            Button("Close Tab") {
                closeAction()
            }
            Button("Close Other Tabs") {
                appModel.closeOtherTabs(tab)
            }
            Button("Close Tabs to the Right") {
                appModel.closeTabsToRight(of: tab)
            }
            Divider()
            Button("Split Right") {
                appModel.splitTabIntoNewPane(tab)
            }
        }
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.ideEditorBackground
        } else if isHovering {
            return Color.ideEditorBackground.opacity(0.35)
        } else {
            return Color.clear
        }
    }
}

struct EditorPlaceholderView: View {
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StartTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appModel: AppModel
    @State private var query = ""
    var addTabAction: () -> Void
    var openWorkspaceAction: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.ideEditorBackground,
                    Color.ideEditorBackground.opacity(colorScheme == .dark ? 0.4 : 0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 60)

                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, y: 6)

                Text("Ask ZERO to open files, run commands or sketch ideas.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                StartPromptComposer(text: $query, onSubmit: handleQuerySubmit)
                    .padding(.horizontal, 60)

                HStack(spacing: 16) {
                    StartActionPill(label: "Open workspace", systemImage: "folder") {
                        openWorkspaceAction()
                    }
                    StartActionPill(label: "New canvas", systemImage: "sparkles") {
                        addTabAction()
                    }
                    StartActionPill(label: "Recent files", systemImage: "clock.arrow.circlepath") {
                        appModel.activateNextTab()
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func handleQuerySubmit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let url = URL(string: trimmed) {
            appModel.openWebURL(url, replaceCurrentTab: true)
        } else if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
                  let url = URL(string: encoded) {
            appModel.openWebURL(url, replaceCurrentTab: true)
        }

        query = ""
    }
}

private struct StartPromptComposer: View {
    @Binding var text: String
    let onSubmit: () -> Void

    private var isDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(
                "",
                text: $text,
                prompt: Text("Type instructions or paste a link…")
                    .foregroundStyle(.secondary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .medium))
            .submitLabel(.send)
            .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isDisabled ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.08), radius: 20, y: 8)
        )
    }

    @Environment(\.colorScheme) private var colorScheme
}

private struct StartActionPill: View {
    let label: String
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.15))
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.15))
            )
    }
}

extension Color {
    static let ideBackground = Color(nsColor: NSColor.windowBackgroundColor)
    static let ideSidebar = Color(nsColor: NSColor.controlBackgroundColor)
    static let ideEditorBackground = Color(nsColor: NSColor.textBackgroundColor)
    static let ideAccent = Color(nsColor: NSColor.systemBlue)
}

private struct TabWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [EditorTab.ID: CGFloat] = [:]
    static func reduce(value: inout [EditorTab.ID: CGFloat], nextValue: () -> [EditorTab.ID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
