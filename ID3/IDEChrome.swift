import SwiftUI

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
    @State private var draggingTab: EditorTab?
    @State private var dragTranslation: CGFloat = 0
    @State private var tabWidths: [EditorTab.ID: CGFloat] = [:]
    @State private var lastReorderTranslation: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    private let overflowThreshold: CGFloat = 280

    var body: some View {
        HStack(spacing: 8) {
            if appModel.tabs.isEmpty {
                HStack {
                    Text("")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { proxy in
                    HStack(spacing: 4) {
                        ForEach(appModel.tabs) { tab in
                            EditorTabChip(
                                tab: tab,
                                isActive: appModel.activeTabID == tab.id,
                                closeAction: { appModel.closeTab(tab) }
                            )
                            .id(tab.id)
                            .zIndex(draggingTab == tab ? 1 : 0)
                            .offset(x: draggingTab == tab ? dragTranslation : 0)
                            .onTapGesture {
                                appModel.activate(tab: tab)
                            }
                            .gesture(dragGesture(for: tab))
                        }

                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 24, height: 32)
                    }
                    .padding(.horizontal, 8)
                    .onChange(of: appModel.activeTabID) { target in
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
    }
}

private extension EditorTabBar {
    var shouldShowOverflowButton: Bool {
        guard !appModel.tabs.isEmpty, availableWidth > 0 else { return false }
        guard let averageWidth = tabWidths.values.average else { return false }
        let totalNeeded = averageWidth * CGFloat(appModel.tabs.count)
        let reservedRight: CGFloat = 64 // plus + overflow controls
        return totalNeeded > max(availableWidth - reservedRight, 0)
    }
}

private struct TabBarAvailableWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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

    private var cardColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white
    }

    private var backdrop: LinearGradient {
        let top = colorScheme == .dark ? Color.black.opacity(0.75) : Color.white.opacity(0.95)
        let bottom = colorScheme == .dark ? Color.black.opacity(0.9) : Color.white
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack {
            backdrop
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.ideAccent)
                    )

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Ask changes about project…", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .onSubmit(handleQuerySubmit)
                        Button(action: {}) {
                            Image(systemName: "mic.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        Button(action: handleQuerySubmit) {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                    Divider()

                    HStack(spacing: 12) {
                        Button(action: openWorkspaceAction) {
                            Label("Add tabs or files", systemImage: "plus")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 999)
                                .fill(Color.secondary.opacity(0.15))
                        )

                        Button(action: {}) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .background(
                            Circle().fill(Color.secondary.opacity(0.15))
                        )

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(cardColor)
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.08), radius: 30, x: 0, y: 25)
                )
                .padding(.horizontal, 40)

                HStack(spacing: 12) {
                    StartQuickAction(
                        label: "Skills",
                        systemImage: "bolt.fill",
                        action: addTabAction
                    )
                    StartQuickAction(
                        label: "Learn Skills",
                        systemImage: "graduationcap.fill",
                        action: {}
                    )
                }

                Spacer()
            }
            .padding(.horizontal, 60)
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

private struct StartQuickAction: View {
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
                        .fill(Color.secondary.opacity(0.2))
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

private extension EditorTabBar {
    func dragGesture(for tab: EditorTab) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggingTab != tab {
                    draggingTab = tab
                }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                handleDragEnd(for: tab, translation: value.translation.width)
                draggingTab = nil
                dragTranslation = 0
            }
    }

    func handleDragEnd(for tab: EditorTab, translation: CGFloat) {
        guard let startIndex = appModel.tabs.firstIndex(of: tab) else { return }
        let tabWidth = tabWidths[tab.id] ?? 120
        let step = max(tabWidth + 4, 60)
        let offset = Int((translation / step).rounded())
        let destination = max(0, min(appModel.tabs.count - 1, startIndex + offset))
        appModel.moveTab(tab, to: destination)
    }
}

private struct TabWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [EditorTab.ID: CGFloat] = [:]
    static func reduce(value: inout [EditorTab.ID: CGFloat], nextValue: () -> [EditorTab.ID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
