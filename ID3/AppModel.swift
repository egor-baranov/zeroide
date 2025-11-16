import SwiftUI
import AppKit

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
    }

    let kind: Kind

    init(url: URL) {
        self.kind = .file(url)
    }

    init(kind: Kind) {
        self.kind = kind
    }

    var id: AnyHashable {
        switch kind {
        case .file(let url):
            return AnyHashable(url)
        case .canvas(let uuid):
            return AnyHashable(uuid)
        }
    }

    var title: String {
        switch kind {
        case .file(let url):
            return url.lastPathComponent
        case .canvas:
            return "New Tab"
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

final class AppModel: NSObject, ObservableObject {
    @Published var workspaceURL: URL?
    @Published var reloadToken = UUID()
    @Published var state: WorkbenchState = .idle
    @Published var editorMode: EditorMode = .native
    @Published var fileTree: [WorkspaceNode] = []
    @Published var selectedFileURL: URL?
    @Published var fileContent: String = ""
    @Published var tabs: [EditorTab] = []
    @Published var activeTabID: EditorTab.ID?
    @Published var recentWorkspaces: [URL] = []

    private let recentWorkspacesKey = "recentWorkspaces"
    private let recentBookmarksKey = "recentWorkspaceBookmarks"
    private var recentWorkspaceBookmarks: [String: Data] = [:]
    private var activeSecurityScopedURL: URL?

    var activeTab: EditorTab? {
        guard let activeTabID else { return nil }
        return tabs.first(where: { $0.id == activeTabID })
    }

    var isShowingStartTab: Bool {
        activeTab?.isCanvas ?? false
    }

    override init() {
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

    func openFile(at url: URL) {
        selectedFileURL = url
        let tab = EditorTab(url: url)
        if tabs.contains(tab) == false {
            tabs.append(tab)
        }
        activeTabID = tab.id
        loadFileContents(from: url)
    }

    func activate(tab: EditorTab) {
        switch tab.kind {
        case .file(let url):
            openFile(at: url)
        case .canvas:
            activeTabID = tab.id
            selectedFileURL = nil
            fileContent = ""
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

    func closeTab(_ tab: EditorTab) {
        guard let index = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: index)

        if activeTabID == tab.id {
            if let replacement = tabs.indices.contains(index) ? tabs[index] : tabs.last {
                activate(tab: replacement)
            } else {
                activeTabID = nil
                selectedFileURL = nil
                fileContent = ""
                state = workspaceURL == nil ? .idle : .ready
            }
        }
    }

    func moveTab(_ dragging: EditorTab, before target: EditorTab?) {
        guard let fromIndex = tabs.firstIndex(of: dragging) else { return }

        if let target, let targetIndex = tabs.firstIndex(of: target) {
            if fromIndex == targetIndex { return }
            var destination = targetIndex
            if fromIndex < targetIndex { destination -= 1 }
            tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: max(destination, 0))
        } else {
            tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: tabs.count)
        }
    }

    func swapTabs(from index: Int, to destination: Int) {
        guard tabs.indices.contains(index), tabs.indices.contains(destination) else { return }
        tabs.swapAt(index, destination)
    }

    func moveTab(_ tab: EditorTab, to destinationIndex: Int) {
        guard let currentIndex = tabs.firstIndex(of: tab) else { return }
        let clamped = max(0, min(destinationIndex, tabs.count - 1))
        guard currentIndex != clamped else { return }

        if clamped > currentIndex {
            tabs.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: clamped + 1)
        } else {
            tabs.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: clamped)
        }
    }

    func updateNativeEditorText(_ text: String) {
        fileContent = text
        if editorMode == .native {
            state = .ready
        }
    }

    func saveCurrentFile() {
        guard let url = selectedFileURL else { return }

        do {
            try fileContent.write(to: url, atomically: true, encoding: .utf8)
            state = .ready
        } catch {
            state = .error("Couldn't save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func createStartTab() {
        let tab = EditorTab(kind: .canvas(UUID()))
        tabs.append(tab)
        activate(tab: tab)
    }

    func prepareWorkspace(at url: URL) {
        beginSecurityScopeIfNeeded(for: url)
        workspaceURL = url
        UserDefaults.standard.set(url, forKey: "lastWorkspace")
        recordRecentWorkspace(url)
        selectedFileURL = nil
        fileContent = ""
        activeTabID = nil
        tabs.removeAll()
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
        guard selectedFileURL == nil else { return }
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

    private func loadFileContents(from url: URL) {
        let ext = url.pathExtension.lowercased()
        if ImagePreviewSupport.supportsRaster(ext: ext) || ext == "svg" {
            fileContent = ""
            state = .ready
            return
        }

        do {
            fileContent = try String(contentsOf: url)
            state = .ready
        } catch {
            fileContent = ""
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
