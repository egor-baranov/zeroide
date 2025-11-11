import SwiftUI

struct WorkspaceSidebar: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var searchText = ""
    @State private var expandedNodes: Set<URL> = []
    @State private var showSearch = false
    @State private var selectedPanel: SidebarPanel = .structure

    private var tree: [WorkspaceNode] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return appModel.fileTree }
        return appModel.fileTree.compactMap { filter(node: $0, term: term) }
    }

    private var displayTree: [WorkspaceNode] {
        guard let rootURL = appModel.workspaceURL else { return tree }
        return [
            WorkspaceNode(url: rootURL, isDirectory: true, children: tree)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarTabs(selected: $selectedPanel)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if showSearch && selectedPanel == .structure {
                searchField
            }
            Group {
                switch selectedPanel {
                case .structure:
                    ScrollView {
                        FileTreeView(nodes: displayTree, expanded: $expandedNodes, depth: 0)
                            .padding(.vertical, 4)
                    }
                case .commit, .find, .hierarchy:
                    SidebarPlaceholder(title: selectedPanel.title, description: selectedPanel.description)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        }
        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.ideSidebar)
        .onAppear(perform: syncRootExpansion)
        .onChange(of: appModel.workspaceURL) { _ in
            expandedNodes.removeAll()
            syncRootExpansion()
        }
        .background(SidebarKeyCatcher(toggleSearch: toggleSearch))
    }

    private var searchField: some View {
        TextField("Search files", text: $searchText)
            .textFieldStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.05))
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    private func filter(node: WorkspaceNode, term: String) -> WorkspaceNode? {
        let nameMatches = node.name.lowercased().contains(term)
        let filteredChildren = node.children?.compactMap { filter(node: $0, term: term) }

        if nameMatches || !(filteredChildren?.isEmpty ?? true) {
            return WorkspaceNode(
                url: node.url,
                isDirectory: node.isDirectory,
                children: filteredChildren
            )
        }

        return nil
    }

    private func syncRootExpansion() {
        if let root = appModel.workspaceURL {
            expandedNodes.insert(root)
        }
    }

    private func toggleSearch() {
        guard selectedPanel == .structure else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            showSearch.toggle()
            if !showSearch {
                searchText = ""
            }
        }
    }

    private struct FileTreeView: View {
        @EnvironmentObject private var appModel: AppModel
        let nodes: [WorkspaceNode]
        @Binding var expanded: Set<URL>
        let depth: Int

        var body: some View {
            ForEach(nodes) { node in
                if node.isDirectory {
                    VStack(spacing: 2) {
                        FileRow(
                            node: node,
                            isExpanded: expanded.contains(node.url),
                            toggleDisclosure: { toggle(node) },
                            indentation: indent(for: depth)
                        )
                        if expanded.contains(node.url), let children = node.children {
                            FileTreeView(nodes: children, expanded: $expanded, depth: depth + 1)
                        }
                    }
                } else {
                    FileRow(
                        node: node,
                        isExpanded: nil,
                        toggleDisclosure: nil,
                        indentation: indent(for: depth)
                    )
                }
            }
        }

        private func toggle(_ node: WorkspaceNode) {
            if expanded.contains(node.url) {
                expanded.remove(node.url)
            } else {
                expanded.insert(node.url)
            }
        }

        private func indent(for depth: Int) -> CGFloat {
            CGFloat(depth) * 14
        }
    }

private struct FileRow: View {
        @EnvironmentObject private var appModel: AppModel
        let node: WorkspaceNode
        let isExpanded: Bool?
        let toggleDisclosure: (() -> Void)?
        let indentation: CGFloat

        var body: some View {
            let isSelected = appModel.selectedFileURL == node.url
            HStack(spacing: 0) {
                Color.clear.frame(width: indentation)
                HStack(spacing: 6) {
                    if let isExpanded, let toggleDisclosure {
                        Button(action: toggleDisclosure) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12, height: 12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 12, height: 12)
                    }

                    Image(systemName: node.isDirectory ? "folder" : "doc.plaintext")
                        .foregroundStyle(node.isDirectory ? .secondary : .primary)
                    Text(node.name)
                        .font(.system(size: 13, weight: node.isDirectory ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.ideAccent : Color.primary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.ideAccent.opacity(0.12) : Color.clear)
            )
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDirectory {
                    toggleDisclosure?()
                } else {
                    appModel.selectFile(node)
                }
            }
        }
    }
}

private struct SidebarTabs: View {
    @Binding var selected: SidebarPanel

    var body: some View {
        Picker("Sidebar Mode", selection: $selected) {
            ForEach(SidebarPanel.allCases) { panel in
                Image(systemName: panel.systemImage)
                    .tag(panel)
                    .help(panel.title)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

private struct SidebarPlaceholder: View {
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum SidebarPanel: String, CaseIterable, Identifiable {
    case structure = "Structure"
    case commit = "Commit"
    case find = "Find"
    case hierarchy = "Hierarchy"

    var id: Self { self }

    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .structure: return "folder"
        case .commit: return "clock.arrow.circlepath"
        case .find: return "magnifyingglass"
        case .hierarchy: return "rectangle.grid.1x2"
        }
    }

    var description: String {
        switch self {
        case .structure:
            return ""
        case .commit:
            return "View pending changes and commit history."
        case .find:
            return "Search across your workspace."
        case .hierarchy:
            return "Browse symbol hierarchies."
        }
    }
}
