import SwiftUI
import WebKit

enum LegalPage: String, Identifiable {
    case privacy, terms, support, index
    var id: String { rawValue }
    func publicURL(language: String) -> URL {
        BrandIdentity.websiteURL.appendingPathComponent(language == "tr" ? "tr" : "en")
            .appendingPathComponent("\(rawValue).html")
    }
    var title: String {
        if self == .index { return BrandIdentity.name }
        return L10n.tr(self == .privacy ? "Gizlilik Politikası" : self == .terms ? "Kullanım Koşulları (EULA)" : "Yardım ve SSS")
    }
}

struct LegalDocumentView: View {
    @State private var page: LegalPage
    @State private var documentLanguage = L10n.language == "tr" ? "tr" : "en"
    init(page: LegalPage) { _page = State(initialValue: page) }
    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.tr("Belge dili"), selection: $documentLanguage) {
                Text("Türkçe").tag("tr")
                Text("English").tag("en")
            }.pickerStyle(.segmented).padding()
            LocalLegalWebView(page: $page, language: $documentLanguage)
        }
            .background(MirrorStyle.background)
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: page.publicURL(language: documentLanguage)) {
                        Image(systemName: "safari")
                    }.accessibilityLabel(page.title)
                }
            }
    }
}

private struct LocalLegalWebView: UIViewRepresentable {
    @Binding var page: LegalPage
    @Binding var language: String
    func makeCoordinator() -> Coordinator { Coordinator(page: $page, language: $language) }
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
        context.coordinator.page = $page
        context.coordinator.language = $language
        guard let root = Bundle.main.url(forResource: "Legal", withExtension: nil),
              context.coordinator.loaded != "\(language)/\(page.rawValue)" else { return }
        context.coordinator.loaded = "\(language)/\(page.rawValue)"
        view.loadFileURL(root.appendingPathComponent("\(language)/\(page.rawValue).html"), allowingReadAccessTo: root)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?
        var page: Binding<LegalPage>
        var language: Binding<String>
        init(page: Binding<LegalPage>, language: Binding<String>) {
            self.page = page; self.language = language
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.isFileURL {
                guard action.navigationType == .linkActivated else { decisionHandler(.allow); return }
                guard let target = LegalPage(rawValue: url.deletingPathExtension().lastPathComponent) else {
                    decisionHandler(.cancel); return
                }
                let targetLanguage = url.deletingLastPathComponent().lastPathComponent
                guard ["tr", "en"].contains(targetLanguage) else { decisionHandler(.cancel); return }
                if target == page.wrappedValue && targetLanguage == language.wrappedValue && url.fragment != nil {
                    decisionHandler(.allow); return
                }
                // Native state owns navigation. A late page-load callback cannot undo a selection.
                decisionHandler(.cancel)
                page.wrappedValue = target
                language.wrappedValue = targetLanguage
                return
            }
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, ["https", "mailto"].contains(url.scheme ?? "") {
                UIApplication.shared.open(url)
            }
        }
    }
}

struct ThirdPartyNoticesView: View {
    private var license: String {
        guard let root = Bundle.main.url(forResource: "Legal", withExtension: nil) else { return "" }
        return (try? String(contentsOf: root.appendingPathComponent("VLCKit-COPYING.txt"), encoding: .utf8)) ?? ""
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("VLCKit · VideoLAN").font(.title2.bold())
                Text("Copyright © VLC authors and VideoLAN. Distributed under GNU LGPL 2.1 or later. Used without modification as a dynamically linked framework.")
                Link("VLCKit source code", destination: URL(string: "https://github.com/videolan/vlckit/tree/2e0868f5ed40fe59cd92f377645fdcc260c6e759")!)
                Link("VideoLAN source and build tools", destination: URL(string: "https://code.videolan.org/videolan/VLCKit")!)
                Text(license).font(.footnote).textSelection(.enabled)
            }.padding(24)
        }.background(MirrorStyle.background).navigationTitle("VLCKit · VideoLAN")
    }
}

struct CastNoticesView: View {
    private var notices: String {
        guard let root = Bundle.main.url(forResource: "Legal", withExtension: nil) else { return "" }
        return (try? String(contentsOf: root.appendingPathComponent("GoogleCast-COPYING.txt"), encoding: .utf8)) ?? ""
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Google Cast iOS SDK 4.8.6").font(.title2.bold())
                Link("Google Cast SDK", destination: URL(string: "https://developers.google.com/cast/docs/ios_sender")!)
                Text(notices).font(.footnote).textSelection(.enabled)
            }.padding(24)
        }.background(MirrorStyle.background).navigationTitle("Google Cast")
    }
}
