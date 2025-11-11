import SwiftUI

struct ZeroWelcomeView: View {
    @EnvironmentObject private var appModel: AppModel

    private var recentItems: [URL] {
        Array(appModel.recentWorkspaces.prefix(5))
    }

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text("ZERO")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .kerning(2)
                Text("Your AI-native IDE")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                ActionTile(icon: "folder", title: "Open project", action: appModel.presentWorkspacePicker)
                ActionTile(icon: "square.and.arrow.down", title: "Clone repo", action: {})
                ActionTile(icon: "bolt.horizontal", title: "Connect via SSH", action: {})
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Recent projects")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if !appModel.recentWorkspaces.isEmpty {
                        Text("View all (\(appModel.recentWorkspaces.count))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if appModel.recentWorkspaces.isEmpty {
                    Text("No recent projects yet. Open a folder to get started.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(recentItems, id: \.self) { url in
                            RecentRow(name: url.lastPathComponent, path: url.deletingLastPathComponent().path) {
                                appModel.openRecentWorkspace(url)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
                    )
                }
            }
            .frame(maxWidth: 520)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ideEditorBackground)
    }
}

private struct ActionTile: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.headline)
            }
            .frame(width: 160, height: 90)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RecentRow: View {
    let name: String
    let path: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    Text(path)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
