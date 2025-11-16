import SwiftUI
import AppKit
import WebKit

enum ImagePreviewSupport {
    static let rasterExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "bmp", "heic", "heif", "webp"
    ]

    static func supportsRaster(ext: String) -> Bool {
        rasterExtensions.contains(ext.lowercased())
    }
}

struct RasterImagePreview: View {
    let url: URL
    @State private var image: NSImage?
    @State private var error: String?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let nsImage = image {
                    Color.clear.overlay(
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    )
                } else if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().onAppear(perform: load)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color.black.opacity(0.02))
        .onChange(of: url) { _ in
            image = nil
            load()
        }
    }

    private func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = NSImage(contentsOf: url)
            DispatchQueue.main.async {
                self.image = image
                if image == nil {
                    self.error = "Unable to load image preview"
                } else {
                    self.error = nil
                }
            }
        }
    }
}

struct SVGPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        load(into: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        load(into: nsView)
    }

    private func load(into webView: WKWebView) {
        let svgURL = url

        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: svgURL) else {
                let html = self.errorHTML(for: svgURL.lastPathComponent)
                DispatchQueue.main.async {
                    webView.loadHTMLString(html, baseURL: nil)
                }
                return
            }

            let base64 = data.base64EncodedString()
            let html = self.htmlWrapper(for: base64)

            DispatchQueue.main.async {
                webView.loadHTMLString(html, baseURL: svgURL.deletingLastPathComponent())
            }
        }
    }

    private func htmlWrapper(for base64: String) -> String {
        """
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
            <style>
              html, body {
                margin: 0;
                height: 100%;
                background-color: #ffffff;
              }
              body, .canvas {
                width: 100%;
                height: 100%;
              }
              body {
                display: flex;
                align-items: stretch;
                justify-content: stretch;
              }
              .canvas {
                box-sizing: border-box;
                padding: 48px;
                width: 100%;
                height: 100%;
              }
              img {
                display: block;
                width: 100%;
                height: 100%;
                object-fit: contain;
              }
            </style>
          </head>
          <body>
            <div class="canvas">
              <img src="data:image/svg+xml;base64,\(base64)" alt="SVG preview">
            </div>
          </body>
        </html>
        """
    }

    private func errorHTML(for fileName: String) -> String {
        """
        <html>
          <body style="font-family: -apple-system, Helvetica; color: #6b7280; display:flex; align-items:center; justify-content:center; background-color:#ffffff; height:100vh; margin:0;">
            Unable to load \(fileName)
          </body>
        </html>
        """
    }
}
