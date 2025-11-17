import SwiftUI

struct ZeroWelcomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var prompt: String = ""

    private var recentItems: [URL] {
        Array(appModel.recentWorkspaces.prefix(5))
    }

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 150)
                Text("AI-native IDE for thoughtful builders")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            PromptComposer(prompt: $prompt, submit: handlePromptSubmit)
                .frame(maxWidth: 520)

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
                        HStack(spacing: 12) {
                            Text("View all (\(appModel.recentWorkspaces.count))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Clear") {
                                Task { await appModel.clearRecentWorkspaces() }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                    }
                }

                if appModel.recentWorkspaces.isEmpty {
                    Text("No recent projects yet. Open a folder to get started.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(recentItems, id: \.self) { url in
                            RecentRow(name: url.lastPathComponent, path: displayPath(for: url)) {
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

    private func handlePromptSubmit() {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        prompt = ""
    }
}

private func displayPath(for url: URL) -> String {
    let path = url.path
    let home = NSHomeDirectory()
    if path.hasPrefix(home) {
        return path.replacingOccurrences(of: home, with: "~")
    }
    return path
}

private struct PromptComposer: View {
    @Binding var prompt: String
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("", text: $prompt, prompt: Text("Ask ZERO to open, create, or explain…").foregroundStyle(.secondary))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .submitLabel(.send)
                .onSubmit(submit)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .foregroundColor(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
        )
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
