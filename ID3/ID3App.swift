import SwiftUI

@main
struct ID3App: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Folder...") {
                    appModel.presentWorkspacePicker()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu("Workspace") {
                Button("Save File") {
                    appModel.saveCurrentFile()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(appModel.editorMode != .native || appModel.selectedFileURL == nil)

                Button("Reload Workbench") {
                    appModel.reloadWorkbench()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appModel.workspaceURL == nil || appModel.editorMode != .workbench)

                Divider()

                Picker(
                    "Editor Mode",
                    selection: Binding(
                        get: { appModel.editorMode },
                        set: { appModel.setEditorMode($0) }
                    )
                ) {
                    ForEach(EditorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
        }
    }
}
