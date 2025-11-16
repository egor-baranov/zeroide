import SwiftUI

struct NativeEditorView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private var theme: EditorTheme { EditorTheme(colorScheme: colorScheme) }
    private var language: ProgrammingLanguage { ProgrammingLanguage(fileURL: appModel.selectedFileURL) }

    private var textBinding: Binding<String> {
        Binding(
            get: { appModel.fileContent },
            set: { newValue in
                appModel.updateNativeEditorText(newValue)
            }
        )
    }

    var body: some View {
        Group {
            if let preview = previewType {
                switch preview {
                case .raster(let url):
                    RasterImagePreview(url: url)
                case .svg(let url):
                    SVGPreviewView(url: url)
                        .background(Color.white)
                }
            } else {
                MonacoEditorView(
                    text: textBinding,
                    language: language,
                    theme: theme,
                    onTextChange: { _ in }
                )
            }
        }
        .background(Color.ideEditorBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewType: PreviewType? {
        guard let url = appModel.selectedFileURL else { return nil }
        let ext = url.pathExtension.lowercased()
        if ImagePreviewSupport.supportsRaster(ext: ext) {
            return .raster(url)
        }
        if ext == "svg" {
            return .svg(url)
        }
        return nil
    }

    private enum PreviewType {
        case raster(URL)
        case svg(URL)
    }
}
