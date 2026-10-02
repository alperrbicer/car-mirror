import SwiftUI
import WebKit

enum LegalPage: String, Identifiable {
    case privacy, terms, support
    var id: String { rawValue }
    var title: String {
        L10n.tr(self == .privacy ? "Gizlilik Politikası" : self == .terms ? "Kullanım Koşulları (EULA)" : "Yardım ve SSS")
    }
}

struct LegalDocumentView: View {
    let page: LegalPage
    @State private var documentLanguage = L10n.language == "tr" ? "tr" : "en"
    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.tr("Belge dili"), selection: $documentLanguage) {
                Text("Türkçe").tag("tr")
                Text("English").tag("en")
            }.pickerStyle(.segmented).padding()
            LocalLegalWebView(page: page, language: documentLanguage)
        }
            .background(MirrorStyle.background)
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LocalLegalWebView: UIViewRepresentable {
    let page: LegalPage
    let language: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(MirrorStyle.background)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard let root = Bundle.main.url(forResource: "Legal", withExtension: nil),
              context.coordinator.loaded != "\(language)/\(page.rawValue)" else { return }
        context.coordinator.loaded = "\(language)/\(page.rawValue)"
        view.loadFileURL(root.appendingPathComponent("\(language)/\(page.rawValue).html"), allowingReadAccessTo: root)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.isFileURL { decisionHandler(.allow); return }
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, ["https", "mailto"].contains(url.scheme ?? "") {
                UIApplication.shared.open(url)
            }
        }
    }
}
