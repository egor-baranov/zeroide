import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum WorkbenchState: Equatable {
    case idle
    case loading
    case ready
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "Pick a folder to start editing."
        case .loading:
            return "Bringing the editor environment online..."
        case .ready:
            return "Workspace ready."
        case .error(let message):
            return message
        }
    }
}

enum EditorMode: String, CaseIterable, Identifiable {
    case native
    case workbench

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native:
            return "Native"
        case .workbench:
            return "Code OSS"
        }
    }
}

struct WorkbenchConfiguration {
    let workbenchRoot: URL
    let workspaceURL: URL?
    let entryRelativePath: String

    init(workbenchRoot: URL, workspaceURL: URL?, entryRelativePath: String = "out/vs/code/browser/workbench/workbench.html") {
        self.workbenchRoot = workbenchRoot
        self.workspaceURL = workspaceURL
        self.entryRelativePath = entryRelativePath
    }

    var entrypoint: URL {
        workbenchRoot.appendingPathComponent(entryRelativePath)
    }
}

struct WorkspaceNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [WorkspaceNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct EditorTab: Identifiable, Hashable {
    enum Kind: Hashable {
        case file(URL)
        case canvas(UUID)
        case web(URL)
    }

    let kind: Kind

    init(url: URL) {
        self.kind = .file(url)
    }

    init(kind: Kind) {
        self.kind = kind
    }

    init(webURL: URL) {
        self.kind = .web(webURL)
    }

    var id: AnyHashable {
        switch kind {
        case .file(let url):
            return AnyHashable(url)
        case .canvas(let uuid):
            return AnyHashable(uuid)
        case .web(let url):
            return AnyHashable("web-\(url.absoluteString)")
        }
    }

    var title: String {
        switch kind {
        case .file(let url):
            return url.lastPathComponent
        case .canvas:
            return "New Tab"
        case .web(let url):
            if let host = url.host, !host.isEmpty {
                return host
            }
            return url.absoluteString
        }
    }

    var fileURL: URL? {
        if case let .file(url) = kind { return url }
        return nil
    }

    var isCanvas: Bool {
        if case .canvas = kind { return true }
        return false
    }

    var dragIdentifier: String {
        "\(id.hashValue)"
    }

    var webURL: URL? {
        if case let .web(url) = kind { return url }
        return nil
    }

    func subtitle(relativeTo workspace: URL?) -> String {
        guard case let .file(url) = kind else { return "" }
        guard let workspace = workspace else {
            return url.deletingLastPathComponent().path
        }
        let rootPath = workspace.resolvingSymlinksInPath().path.hasSuffix("/") ? workspace.resolvingSymlinksInPath().path : workspace.resolvingSymlinksInPath().path + "/"
        let trimmed = url.path.replacingOccurrences(of: rootPath, with: "")
        let components = trimmed.split(separator: "/").dropLast()
        return components.isEmpty ? workspace.lastPathComponent : components.joined(separator: "/")
    }
}

struct EditorPane: Identifiable, Hashable {
    let id: UUID
    var tabs: [EditorTab]
    var activeTabID: EditorTab.ID?

    init(id: UUID = UUID(), tabs: [EditorTab] = [], active: EditorTab.ID? = nil) {
        self.id = id
        self.tabs = tabs
        self.activeTabID = active
    }

    var activeTab: EditorTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }
}

final class AppModel: NSObject, ObservableObject {
    @Published var workspaceURL: URL?
    @Published var reloadToken = UUID()
    @Published var state: WorkbenchState = .idle
    @Published var editorMode: EditorMode = .native
    @Published var fileTree: [WorkspaceNode] = []
    @Published var panes: [EditorPane]
    @Published var activePaneID: EditorPane.ID
    @Published var paneWidthFractions: [EditorPane.ID: CGFloat]
    @Published var recentWorkspaces: [URL] = []
    @Published private var tabContents: [EditorTab.ID: String] = [:]

    private let recentWorkspacesKey = "recentWorkspaces"
    private let recentBookmarksKey = "recentWorkspaceBookmarks"
    private var recentWorkspaceBookmarks: [String: Data] = [:]
    private var activeSecurityScopedURL: URL?

    var activeTab: EditorTab? {
        guard let index = activePaneIndex else { return nil }
        return panes[index].activeTab
    }

    var isShowingStartTab: Bool {
        activeTab?.isCanvas ?? false
    }

    var activeWebURL: URL? {
        if case let .web(url) = activeTab?.kind {
            return url
        }
        return nil
    }

    var focusedFileURL: URL? {
        activePane?.activeTab?.fileURL
    }

    func widthFraction(for pane: EditorPane) -> CGFloat {
        paneWidthFractions[pane.id] ?? (1 / CGFloat(max(panes.count, 1)))
    }

    func paneWidthSnapshot() -> [EditorPane.ID: CGFloat] {
        let paneIDs = panes.map(\.id)
        guard !paneIDs.isEmpty else { return [:] }

        var snapshot: [EditorPane.ID: CGFloat] = [:]
        for id in paneIDs {
            if let value = paneWidthFractions[id] {
                snapshot[id] = value
            }
        }

        if snapshot.count < paneIDs.count {
            let fallback = 1 / CGFloat(paneIDs.count)
            for id in paneIDs where snapshot[id] == nil {
                snapshot[id] = fallback
            }
        }

        let total = snapshot.values.reduce(0, +)
        guard total > 0 else {
            let equal = 1 / CGFloat(paneIDs.count)
            return Dictionary(uniqueKeysWithValues: paneIDs.map { ($0, equal) })
        }

        var normalized: [EditorPane.ID: CGFloat] = [:]
        for (key, value) in snapshot {
            normalized[key] = value / total
        }
        return normalized
    }

    func commitPaneWidthFractions(_ fractions: [EditorPane.ID: CGFloat]) {
        paneWidthFractions = fractions
        normalizePaneWidths()
    }

    private var activePaneIndex: Int? {
        panes.firstIndex(where: { $0.id == activePaneID })
    }

    private var activePane: EditorPane? {
        guard let index = activePaneIndex else { return nil }
        return panes[index]
    }

    var tabs: [EditorTab] {
        get { activePane?.tabs ?? [] }
        set {
            guard let index = activePaneIndex else { return }
            panes[index].tabs = newValue
        }
    }

    var activeTabID: EditorTab.ID? {
        get { activePane?.activeTabID }
        set {
            guard let index = activePaneIndex else { return }
            panes[index].activeTabID = newValue
        }
    }

    func paneIndex(containing tabID: EditorTab.ID) -> Int? {
        panes.firstIndex { pane in
            pane.tabs.contains { $0.id == tabID }
        }
    }

    func paneIndex(containing tab: EditorTab) -> Int? {
        panes.firstIndex { pane in
            pane.tabs.contains(tab)
        }
    }

    private func tabLocation(forIdentifier identifier: String) -> (paneIndex: Int, tabIndex: Int, tab: EditorTab)? {
        for (paneIdx, pane) in panes.enumerated() {
            for (tabIdx, tab) in pane.tabs.enumerated() {
                if tab.dragIdentifier == identifier {
                    return (paneIdx, tabIdx, tab)
                }
            }
        }
        return nil
    }

    private func ensureActivePane() {
        if panes.isEmpty {
            let pane = EditorPane()
            panes = [pane]
            activePaneID = pane.id
            paneWidthFractions = [pane.id: 1]
        } else if !panes.contains(where: { $0.id == activePaneID }) {
            activePaneID = panes[0].id
        }
    }

    private var allTabIDs: Set<EditorTab.ID> {
        Set(panes.flatMap { $0.tabs.map(\.id) })
    }

    private func pruneTabContents(keeping ids: Set<EditorTab.ID>) {
        tabContents = tabContents.filter { ids.contains($0.key) }
    }

    private func removePaneIfEmpty(at index: Int) {
        guard panes.indices.contains(index) else { return }
        guard panes[index].tabs.isEmpty, panes.count > 1 else { return }
        let removed = panes.remove(at: index)
        paneWidthFractions.removeValue(forKey: removed.id)
        normalizePaneWidths()
        if removed.id == activePaneID {
            let newIndex = min(index, panes.count - 1)
            activePaneID = panes[newIndex].id
        }
    }

    private func createPane(after referencePaneID: EditorPane.ID?) -> EditorPane {
        let insertIndex: Int
        if let referencePaneID,
           let referenceIndex = panes.firstIndex(where: { $0.id == referencePaneID }) {
            insertIndex = referenceIndex + 1
        } else {
            insertIndex = panes.count
        }
        let referenceID = referencePaneID ?? (insertIndex > 0 && insertIndex - 1 < panes.count ? panes[insertIndex - 1].id : nil)
        return createPane(insertingAt: insertIndex, splitting: referenceID)
    }

    private func createPane(before referencePaneID: EditorPane.ID?) -> EditorPane {
        let insertIndex: Int
        if let referencePaneID,
           let referenceIndex = panes.firstIndex(where: { $0.id == referencePaneID }) {
            insertIndex = referenceIndex
        } else {
            insertIndex = 0
        }
        let referenceID = referencePaneID ?? (insertIndex < panes.count ? panes[insertIndex].id : panes.last?.id)
        return createPane(insertingAt: insertIndex, splitting: referenceID)
    }

    private func createPane(insertingAt index: Int, splitting referencePaneID: EditorPane.ID?) -> EditorPane {
        let pane = EditorPane()
        let clamped = max(0, min(index, panes.count))
        panes.insert(pane, at: clamped)
        handlePaneInsertion(newPane: pane, splitting: referencePaneID)
        return pane
    }

    private func handlePaneInsertion(newPane: EditorPane, splitting referencePaneID: EditorPane.ID?) {
        ensurePaneWidthEntries()
        if panes.count == 1 {
            paneWidthFractions[newPane.id] = 1
            return
        }

        if let referencePaneID,
           let referenceWidth = paneWidthFractions[referencePaneID] {
            let splitWidth = referenceWidth / 2
            paneWidthFractions[referencePaneID] = splitWidth
            paneWidthFractions[newPane.id] = splitWidth
            normalizePaneWidths()
        } else {
            applyEqualPaneWidthDistribution()
        }
    }

    private func applyEqualPaneWidthDistribution() {
        guard !panes.isEmpty else {
            paneWidthFractions = [:]
            return
        }
        let equalFraction = 1 / CGFloat(panes.count)
        paneWidthFractions = Dictionary(uniqueKeysWithValues: panes.map { ($0.id, equalFraction) })
    }

    private func ensurePaneWidthEntries() {
        let paneIDs = panes.map(\.id)
        paneWidthFractions = paneWidthFractions.filter { paneIDs.contains($0.key) }
        guard !paneIDs.isEmpty else {
            paneWidthFractions = [:]
            return
        }
        if paneWidthFractions.isEmpty {
            applyEqualPaneWidthDistribution()
            return
        }
        let missing = paneIDs.filter { paneWidthFractions[$0] == nil }
        if !missing.isEmpty {
            let defaultFraction = 1 / CGFloat(paneIDs.count)
            for id in missing {
                paneWidthFractions[id] = defaultFraction
            }
        }
        normalizePaneWidths()
    }

    private func normalizePaneWidths() {
        let paneIDs = panes.map(\.id)
        var filtered: [EditorPane.ID: CGFloat] = [:]
        for id in paneIDs {
            if let value = paneWidthFractions[id] {
                filtered[id] = value
            }
        }
        guard !filtered.isEmpty else {
            applyEqualPaneWidthDistribution()
            return
        }
        let total = filtered.values.reduce(0, +)
        guard total > 0 else {
            applyEqualPaneWidthDistribution()
            return
        }
        var normalized: [EditorPane.ID: CGFloat] = [:]
        for (key, value) in filtered {
            normalized[key] = value / total
        }
        paneWidthFractions = normalized
    }

    override init() {
        let initialPane = EditorPane()
        _panes = Published(initialValue: [initialPane])
        _activePaneID = Published(initialValue: initialPane.id)
        _paneWidthFractions = Published(initialValue: [initialPane.id: 1])
        super.init()
        if let saved = UserDefaults.standard.array(forKey: recentWorkspacesKey) as? [String] {
            recentWorkspaces = saved.compactMap { URL(fileURLWithPath: $0) }
        }
        if let bookmarkDict = UserDefaults.standard.dictionary(forKey: recentBookmarksKey) as? [String: Data] {
            recentWorkspaceBookmarks = bookmarkDict
        }
    }

    func presentWorkspacePicker() {
        let panel = NSOpenPanel()
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            prepareWorkspace(at: url)
        }
    }

    @MainActor
    func openRecentWorkspace(_ url: URL) {
        let path = url.path
        if let bookmark = recentWorkspaceBookmarks[path] {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                beginSecurityScopeIfNeeded(for: resolved)
                prepareWorkspace(at: resolved)
                if stale { recordRecentWorkspace(resolved) }
                return
            }
        }

        guard FileManager.default.fileExists(atPath: path) else {
            state = .error("Folder not found at \(path)")
            removeRecentWorkspace(atPath: path)
            return
        }
        prepareWorkspace(at: url)
    }

    func setEditorMode(_ mode: EditorMode) {
        guard editorMode != mode else { return }
        editorMode = mode

        switch mode {
        case .native:
            state = workspaceURL == nil ? .idle : .ready
        case .workbench:
            reloadWorkbench()
        }
    }

    func configuration() throws -> WorkbenchConfiguration {
        guard let resourcesURL = Bundle.main.resourceURL else {
            let error = ConfigurationError.missingResources
            state = .error(error.errorDescription ?? "Missing resources")
            throw error
        }

        let workbenchRoot = resourcesURL.appendingPathComponent("Workbench")
        let configuration = WorkbenchConfiguration(workbenchRoot: workbenchRoot, workspaceURL: workspaceURL)

        guard FileManager.default.fileExists(atPath: configuration.entrypoint.path) else {
            let error = ConfigurationError.missingEntryPoint(path: configuration.entrypoint.path)
            state = .error(error.errorDescription ?? "Missing entry point")
            throw error
        }

        return configuration
    }

    func reloadWorkbench() {
        guard editorMode == .workbench else { return }
        guard workspaceURL != nil else {
            state = .idle
            return
        }
        state = .loading
        reloadToken = UUID()
    }

    func selectFile(_ node: WorkspaceNode) {
        guard !node.isDirectory else { return }
        openFile(at: node.url)
    }

    func openFile(at url: URL, inPane paneID: EditorPane.ID? = nil) {
        ensureActivePane()

        if let paneID, panes.firstIndex(where: { $0.id == paneID }) != nil {
            activePaneID = paneID
        }

        guard let paneIndex = activePaneIndex else { return }
        let prospectiveTab = EditorTab(url: url)
        if let existingIndex = panes[paneIndex].tabs.firstIndex(of: prospectiveTab) {
            let existingTab = panes[paneIndex].tabs[existingIndex]
            panes[paneIndex].activeTabID = existingTab.id
            if tabContents[existingTab.id] == nil {
                loadFileContents(for: existingTab, from: url)
            } else {
                state = .ready
            }
        } else {
            panes[paneIndex].tabs.append(prospectiveTab)
            panes[paneIndex].activeTabID = prospectiveTab.id
            loadFileContents(for: prospectiveTab, from: url)
        }
        activePaneID = panes[paneIndex].id
    }

    func openWebURL(_ url: URL, replaceCurrentTab: Bool = false) {
        let normalizedURL = normalizeWebURL(url)
        let tab = EditorTab(webURL: normalizedURL)

        ensureActivePane()
        guard let paneIndex = activePaneIndex else { return }

        if replaceCurrentTab,
           let activeID = panes[paneIndex].activeTabID,
           let index = panes[paneIndex].tabs.firstIndex(where: { $0.id == activeID }) {
            tabContents.removeValue(forKey: panes[paneIndex].tabs[index].id)
            panes[paneIndex].tabs[index] = tab
            panes[paneIndex].activeTabID = tab.id
        } else {
            if !panes[paneIndex].tabs.contains(tab) {
                panes[paneIndex].tabs.append(tab)
            }
            panes[paneIndex].activeTabID = tab.id
        }
        activePaneID = panes[paneIndex].id
        state = .ready
    }

    private func normalizeWebURL(_ input: URL) -> URL {
        if let scheme = input.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
            return input
        }

        let trimmed = input.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return input
        }

        if let fullURL = URL(string: "https://\(trimmed)"), looksLikeDomain(trimmed) {
            return fullURL
        }

        if let httpsURL = URL(string: "https://\(trimmed)") {
            return httpsURL
        }

        return input
    }

    private func looksLikeDomain(_ text: String) -> Bool {
        struct TLDCache {
            static let suffixes: Set<String> = [
                "com", "org", "net", "io", "app", "dev", "ai", "co", "edu", "gov", "biz",
                "info", "me", "us", "uk", "de", "jp", "fr", "au", "ca", "es", "it", "nl",
                "se", "no", "fi", "cz", "pl", "br", "ru", "in"
            ]
        }

        let components = text.lowercased().split(separator: ".")
        guard components.count >= 2 else { return false }
        let tld = components.last ?? ""
        return components.allSatisfy { !$0.isEmpty && $0.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted) == nil }
            && TLDCache.suffixes.contains(String(tld))
    }

    func activate(tab: EditorTab) {
        guard let paneIndex = paneIndex(containing: tab) else { return }
        activePaneID = panes[paneIndex].id
        panes[paneIndex].activeTabID = tab.id

        switch tab.kind {
        case .file(let url):
            if tabContents[tab.id] == nil {
                loadFileContents(for: tab, from: url)
            } else {
                state = .ready
            }
        case .canvas, .web:
            state = .ready
        }
    }

    func activateNextTab() {
        guard !tabs.isEmpty else { return }
        if let activeID = activeTabID, let index = tabs.firstIndex(where: { $0.id == activeID }) {
            let nextIndex = (index + 1) % tabs.count
            activate(tab: tabs[nextIndex])
        } else if let first = tabs.first {
            activate(tab: first)
        }
    }

    func activatePreviousTab() {
        guard !tabs.isEmpty else { return }
        if let activeID = activeTabID, let index = tabs.firstIndex(where: { $0.id == activeID }) {
            let prevIndex = (index - 1 + tabs.count) % tabs.count
            activate(tab: tabs[prevIndex])
        } else if let last = tabs.last {
            activate(tab: last)
        }
    }

    func closeActiveTab() {
        guard let activeTab = activeTab else { return }
        closeTab(activeTab)
    }

    func closeTab(_ tab: EditorTab) {
        guard let paneIndex = paneIndex(containing: tab),
              let tabIndex = panes[paneIndex].tabs.firstIndex(of: tab) else { return }

        panes[paneIndex].tabs.remove(at: tabIndex)
        tabContents.removeValue(forKey: tab.id)

        if panes[paneIndex].activeTabID == tab.id {
            if panes[paneIndex].tabs.indices.contains(tabIndex) {
                let replacement = panes[paneIndex].tabs[tabIndex]
                panes[paneIndex].activeTabID = replacement.id
                activate(tab: replacement)
            } else if let replacement = panes[paneIndex].tabs.last {
                panes[paneIndex].activeTabID = replacement.id
                activate(tab: replacement)
            } else {
                panes[paneIndex].activeTabID = nil
                if activePaneID == panes[paneIndex].id {
                    state = workspaceURL == nil ? .idle : .ready
                }
            }
        }

        removePaneIfEmpty(at: paneIndex)
    }

    func closeOtherTabs(_ tab: EditorTab) {
        guard let paneIndex = paneIndex(containing: tab),
              let tabIndex = panes[paneIndex].tabs.firstIndex(of: tab) else { return }
        let target = panes[paneIndex].tabs[tabIndex]
        panes[paneIndex].tabs = [target]
        panes[paneIndex].activeTabID = target.id
        pruneTabContents(keeping: allTabIDs)
        activate(tab: target)
    }

    func closeTabsToRight(of tab: EditorTab) {
        guard let paneIndex = paneIndex(containing: tab),
              let tabIndex = panes[paneIndex].tabs.firstIndex(of: tab) else { return }
        guard tabIndex < panes[paneIndex].tabs.count - 1 else { return }

        let removedIDs = panes[paneIndex].tabs[(tabIndex + 1)..<panes[paneIndex].tabs.count].map { $0.id }
        panes[paneIndex].tabs.removeSubrange((tabIndex + 1)..<panes[paneIndex].tabs.count)
        for id in removedIDs {
            tabContents.removeValue(forKey: id)
        }

        if let activeID = panes[paneIndex].activeTabID, removedIDs.contains(activeID) {
            panes[paneIndex].activeTabID = tab.id
            activate(tab: tab)
        }
    }

    func splitTabIntoNewPane(_ tab: EditorTab) {
        guard let sourcePaneIndex = paneIndex(containing: tab),
              let tabIndex = panes[sourcePaneIndex].tabs.firstIndex(of: tab) else { return }

        panes[sourcePaneIndex].tabs.remove(at: tabIndex)

        let newPane = EditorPane(tabs: [tab], active: tab.id)
        let insertIndex = min(sourcePaneIndex + 1, panes.count)
        panes.insert(newPane, at: insertIndex)
        activePaneID = newPane.id

        if panes[sourcePaneIndex].tabs.isEmpty {
            removePaneIfEmpty(at: sourcePaneIndex)
        } else if panes[sourcePaneIndex].activeTabID == tab.id {
            let fallbackIndex = min(tabIndex, panes[sourcePaneIndex].tabs.count - 1)
            panes[sourcePaneIndex].activeTabID = panes[sourcePaneIndex].tabs[fallbackIndex].id
        }

        activate(tab: tab)
    }

    func moveTab(_ tab: EditorTab, to destinationIndex: Int, in pane: EditorPane) {
        guard let paneIndex = panes.firstIndex(where: { $0.id == pane.id }) else { return }
        guard let currentIndex = panes[paneIndex].tabs.firstIndex(of: tab) else { return }
        let clamped = max(0, min(destinationIndex, panes[paneIndex].tabs.count - 1))
        guard currentIndex != clamped else { return }

        if clamped > currentIndex {
            panes[paneIndex].tabs.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: clamped + 1)
        } else {
            panes[paneIndex].tabs.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: clamped)
        }
    }

    func moveTab(withIdentifier identifier: String, toPane targetPaneID: EditorPane.ID) {
        guard let targetIndex = panes.firstIndex(where: { $0.id == targetPaneID }),
              let location = tabLocation(forIdentifier: identifier) else { return }

        let tab = location.tab
        if targetIndex == location.paneIndex {
            // already handled by drag gesture
            return
        }

        panes[location.paneIndex].tabs.remove(at: location.tabIndex)
        panes[targetIndex].tabs.append(tab)
        panes[targetIndex].activeTabID = tab.id

        if panes[location.paneIndex].activeTabID == tab.id {
            panes[location.paneIndex].activeTabID = panes[location.paneIndex].tabs.last?.id
        }

        removePaneIfEmpty(at: location.paneIndex)
        activate(tab: tab)
    }

    func moveTab(withIdentifier identifier: String, before target: EditorTab) {
        guard let location = tabLocation(forIdentifier: identifier),
              let targetPaneIndex = paneIndex(containing: target),
              let targetIndex = panes[targetPaneIndex].tabs.firstIndex(of: target) else { return }

        let tab = location.tab
        let sourcePaneIndex = location.paneIndex
        if sourcePaneIndex == targetPaneIndex && location.tabIndex == targetIndex { return }

        panes[sourcePaneIndex].tabs.remove(at: location.tabIndex)
        var insertionIndex = targetIndex
        if sourcePaneIndex == targetPaneIndex && location.tabIndex < targetIndex {
            insertionIndex -= 1
        }
        insertionIndex = max(0, insertionIndex)
        panes[targetPaneIndex].tabs.insert(tab, at: insertionIndex)
        panes[targetPaneIndex].activeTabID = tab.id

        if sourcePaneIndex != targetPaneIndex {
            removePaneIfEmpty(at: sourcePaneIndex)
        }
    }

    func moveTab(withIdentifier identifier: String, toIndex destinationIndex: Int, in pane: EditorPane) {
        guard let paneIndex = panes.firstIndex(where: { $0.id == pane.id }),
              let location = tabLocation(forIdentifier: identifier) else { return }

        let tab = location.tab
        panes[location.paneIndex].tabs.remove(at: location.tabIndex)

        var insertIndex = destinationIndex
        if paneIndex == location.paneIndex && location.tabIndex < destinationIndex {
            insertIndex -= 1
        }
        insertIndex = max(0, min(insertIndex, panes[paneIndex].tabs.count))

        panes[paneIndex].tabs.insert(tab, at: insertIndex)
        panes[paneIndex].activeTabID = tab.id

        if paneIndex != location.paneIndex {
            removePaneIfEmpty(at: location.paneIndex)
        }
    }

    func handleDrop(_ providers: [NSItemProvider], into pane: EditorPane) -> Bool {
        if let fileProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            || $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            fileProvider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = (object as? NSURL) as URL? ?? object as? URL else { return }
                DispatchQueue.main.async {
                    self.openFile(at: url, inPane: pane.id)
                }
            }
            return true
        }

        if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let nsString = object as? NSString else { return }
                let identifier = nsString as String
                DispatchQueue.main.async {
                    self.moveTab(withIdentifier: identifier, toPane: pane.id)
                }
            }
            return true
        }

        return false
    }

    func handleDropIntoNewPane(_ providers: [NSItemProvider], after referencePane: EditorPane?) -> Bool {
        let newPane = createPane(after: referencePane?.id)
        activePaneID = newPane.id
        return handleDrop(providers, into: newPane)
    }

    func handleDropIntoNewPaneBefore(_ providers: [NSItemProvider], before referencePane: EditorPane?) -> Bool {
        let newPane = createPane(before: referencePane?.id)
        activePaneID = newPane.id
        return handleDrop(providers, into: newPane)
    }

    func documentText(for tab: EditorTab) -> String {
        tabContents[tab.id] ?? ""
    }

    func updateDocumentText(_ text: String, for tab: EditorTab) {
        tabContents[tab.id] = text
        if editorMode == .native {
            state = .ready
        }
    }

    func saveCurrentFile() {
        guard let tab = activeTab, let url = tab.fileURL else { return }

        do {
            let text = tabContents[tab.id] ?? ""
            try text.write(to: url, atomically: true, encoding: .utf8)
            state = .ready
        } catch {
            state = .error("Couldn't save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func createStartTab(openImmediately: Bool = true) {
        ensureActivePane()
        let tab = EditorTab(kind: .canvas(UUID()))
        tabs.append(tab)
        if openImmediately {
            activate(tab: tab)
        } else {
            activeTabID = tab.id
        }
    }

    func prepareWorkspace(at url: URL) {
        beginSecurityScopeIfNeeded(for: url)
        workspaceURL = url
        UserDefaults.standard.set(url, forKey: "lastWorkspace")
        recordRecentWorkspace(url)
        tabContents.removeAll()
        let pane = EditorPane()
        panes = [pane]
        activePaneID = pane.id
        paneWidthFractions = [pane.id: 1]
        rebuildFileTree()
        DispatchQueue.main.async { [weak self] in
            self?.openFirstFileIfAvailable()
        }

        switch editorMode {
        case .native:
            state = .ready
        case .workbench:
            reloadWorkbench()
        }
    }

    private func recordRecentWorkspace(_ url: URL) {
        recentWorkspaces.removeAll { $0 == url }
        recentWorkspaces.insert(url, at: 0)
        if recentWorkspaces.count > 10 {
            recentWorkspaces = Array(recentWorkspaces.prefix(10))
        }
        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            recentWorkspaceBookmarks[url.path] = bookmark
        }
        trimBookmarkStore()
    }

    private func rebuildFileTree() {
        guard let root = workspaceURL else {
            fileTree = []
            return
        }
        fileTree = buildNodes(at: root)
    }

    private func openFirstFileIfAvailable() {
        guard focusedFileURL == nil else { return }
        if let url = firstFileURL(in: fileTree) {
            openFile(at: url)
        }
    }

    private func firstFileURL(in nodes: [WorkspaceNode]) -> URL? {
        for node in nodes {
            if node.isDirectory, let children = node.children, let url = firstFileURL(in: children) {
                return url
            } else if !node.isDirectory {
                return node.url
            }
        }
        return nil
    }

    private func trimBookmarkStore() {
        let paths = recentWorkspaces.map { $0.path }
        UserDefaults.standard.set(paths, forKey: recentWorkspacesKey)
        recentWorkspaceBookmarks = recentWorkspaceBookmarks.filter { paths.contains($0.key) }
        UserDefaults.standard.set(recentWorkspaceBookmarks, forKey: recentBookmarksKey)
    }

    private func removeRecentWorkspace(atPath path: String) {
        recentWorkspaces.removeAll { $0.path == path }
        recentWorkspaceBookmarks.removeValue(forKey: path)
        trimBookmarkStore()
    }

    private func beginSecurityScopeIfNeeded(for url: URL) {
        if activeSecurityScopedURL == url { return }
        endSecurityScopeIfNeeded()
        if url.startAccessingSecurityScopedResource() {
            activeSecurityScopedURL = url
        }
    }

    private func endSecurityScopeIfNeeded() {
        if let scoped = activeSecurityScopedURL {
            scoped.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
        }
    }

    private func buildNodes(at url: URL) -> [WorkspaceNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let sorted = contents.sorted { lhs, rhs in
            let lhsDir = lhs.hasDirectoryFlag
            let rhsDir = rhs.hasDirectoryFlag
            if lhsDir == rhsDir {
                return lhs.lastPathComponent.lowercased() < rhs.lastPathComponent.lowercased()
            }
            return lhsDir && !rhsDir
        }

        return sorted.map { item in
            let isDir = item.hasDirectoryFlag
            let children = isDir ? buildNodes(at: item) : nil
            return WorkspaceNode(url: item, isDirectory: isDir, children: children)
        }
    }

    private func loadFileContents(for tab: EditorTab, from url: URL) {
        let ext = url.pathExtension.lowercased()
        if ImagePreviewSupport.supportsRaster(ext: ext) || ext == "svg" {
            tabContents[tab.id] = ""
            state = .ready
            return
        }

        do {
            tabContents[tab.id] = try String(contentsOf: url)
            state = .ready
        } catch {
            tabContents[tab.id] = ""
            state = .error("Couldn't open \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    enum ConfigurationError: LocalizedError {
        case missingResources
        case missingEntryPoint(path: String)

        var errorDescription: String? {
            switch self {
            case .missingResources:
                return "Unable to locate app resources."
            case .missingEntryPoint(let path):
                return "No workbench HTML at \(path). Copy your Code OSS web build into Resources/Workbench."
            }
        }
    }
}

private extension URL {
    var hasDirectoryFlag: Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }
}

extension AppModel {
    @MainActor
    func clearRecentWorkspaces() {
        recentWorkspaces.removeAll()
        recentWorkspaceBookmarks.removeAll()
        trimBookmarkStore()
    }
}
