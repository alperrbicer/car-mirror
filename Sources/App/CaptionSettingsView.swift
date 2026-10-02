import SwiftUI
import Speech

struct CaptionSettingsView: View {
    @AppStorage("captionsEnabled", store: SharedPreferences.defaults) private var enabled = false
    @AppStorage("captionLocale", store: SharedPreferences.defaults) private var locale = "tr-TR"
    @State private var preparing = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Toggle(L10n.tr("Canlı altyazılar"), isOn: Binding(get: { enabled }, set: { value in
                    if value { Task { await prepare() } } else { enabled = false }
                }))
                .disabled(preparing)
                Picker(L10n.tr("Konuşma dili"), selection: $locale) {
                    Text(L10n.tr("Türkçe")).tag("tr-TR")
                    Text(L10n.tr("English")).tag("en-US")
                }
                .disabled(preparing)
                .onChange(of: locale) { _, _ in enabled = false }
                if preparing { ProgressView(L10n.tr("Dil hazırlanıyor…")) }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text(L10n.tr("Ekran paylaşımındaki konuşmaları cihazında yazıya çevirir ve görüntüye ekler. iOS 26 ve desteklenen bir dil gerekir. İlk hazırlıkta dil dosyası indirilir; ses ve altyazılar kaydedilmez."))
            }
        }
        .navigationTitle(L10n.tr("Canlı altyazılar"))
        .navigationBarTitleDisplayMode(.inline)
    }
    private func prepare() async {
        preparing = true; message = nil; defer { preparing = false }
        guard #available(iOS 26, *), SpeechTranscriber.isAvailable else {
            message = L10n.tr("Canlı altyazılar bu cihazda kullanılamıyor."); return
        }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else {
            message = L10n.tr("Bu dil cihaz içi altyazı için henüz desteklenmiyor. Başka bir dil seçebilirsin."); return
        }
        let module = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        do {
            try await AssetInventory.reserve(locale: supported)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: [module]) == .installed else { throw LibraryError.invalidResponse }
            enabled = true
        } catch { message = L10n.tr("Dil hazırlanamadı. İnternet bağlantını kontrol edip yeniden dene.") }
    }
}
