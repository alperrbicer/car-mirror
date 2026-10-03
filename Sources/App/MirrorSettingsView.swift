import SwiftUI
import UIKit
#if DEBUG
import AVKit
#endif

struct MirrorSettingsView: View {
    @ObservedObject var model: MirrorModel
    @Environment(\.dismiss) private var dismiss
    @State private var report: ReportFile?
    @State private var working = false
    @State private var errorMessage: String?
    @State private var cleared = false
    @State private var clearingLibrary = false
    @AppStorage("language", store: SharedPreferences.defaults) private var language = "system"
    @AppStorage("streamQuality", store: SharedPreferences.defaults) private var quality = StreamQuality.balanced.rawValue
    @AppStorage("audioMode", store: SharedPreferences.defaults) private var audioMode = StreamAudioMode.synchronized.rawValue
    @ObservedObject private var purchases = PurchaseStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        MirrorMark().frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(BrandIdentity.name).font(.system(.title2, design: .default, weight: .semibold)).tracking(-0.6)
                            Text(BrandIdentity.tagline).font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .listRowBackground(MirrorStyle.surface)
                Section {
                    NavigationLink { ProView() } label: {
                        HStack {
                            Label(L10n.tr("Mirivo Pro"), systemImage: "sparkles")
                            Spacer()
                            Text(L10n.tr(purchases.verifiedPro ? "Etkin" : purchases.salesEnabled ? "Keşfet" : "Yakında"))
                                .font(.caption).foregroundStyle(MirrorStyle.accent)
                        }
                    }
                }.listRowBackground(MirrorStyle.surface)
                Section(L10n.tr("Tercihler")) {
                    NavigationLink { LanguageSettingsView() } label: {
                        LabeledContent(L10n.tr("Dil"), value: language == "system" ? L10n.tr("Sistemi izle") : L10n.appLanguage.nativeName)
                    }.accessibilityIdentifier("settings-language")
                    Picker(L10n.tr("Yayın kalitesi"), selection: $quality) {
                        Text(L10n.tr("Dengeli")).tag(StreamQuality.balanced.rawValue)
                        Text(L10n.tr("Yüksek")).tag(StreamQuality.high.rawValue)
                    }
                    Picker(L10n.tr("Ses"), selection: $audioMode) {
                        Text(L10n.tr("Görüntüyle birlikte")).tag(StreamAudioMode.synchronized.rawValue)
                        Text(L10n.tr("Kaynak uygulamadan")).tag(StreamAudioMode.source.rawValue)
                    }
                    if purchases.access.fullAccess {
                        NavigationLink(L10n.tr("Canlı altyazılar")) { CaptionSettingsView() }
                    } else {
                        NavigationLink(L10n.tr("Canlı altyazılar · Pro")) { ProView() }
                    }
                }.listRowBackground(MirrorStyle.surface)
                Section(L10n.tr("Yasal")) {
                    NavigationLink(L10n.tr("Gizlilik Politikası")) { LegalDocumentView(page: .privacy) }
                    NavigationLink(L10n.tr("Kullanım Koşulları (EULA)")) { LegalDocumentView(page: .terms) }
                }.listRowBackground(MirrorStyle.surface)
                Section(L10n.tr("Hakkında")) {
                    NavigationLink(L10n.tr("Yardım ve SSS")) { LegalDocumentView(page: .support) }
                    Link(L10n.tr("Bize ulaş"), destination: URL(string: "mailto:alperrbicer@gmail.com?subject=Mirivo")!)
                    LabeledContent(L10n.tr("Sürüm"), value: version)
                }.listRowBackground(MirrorStyle.surface)
                Section {
                    Button {
                        working = true
                        Task {
                            defer { working = false }
                            do { report = ReportFile(url: try await model.diagnostics.export()) }
                            catch { errorMessage = L10n.tr("Rapor hazırlanamadı. Lütfen yeniden dene.") }
                        }
                    } label: {
                        HStack {
                            Label(L10n.tr("Tanılama raporunu paylaş"), systemImage: "square.and.arrow.up")
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working)
                    Button(L10n.tr(cleared ? "Kayıtlar temizlendi" : "Kayıtları temizle"), role: .destructive) {
                        working = true
                        Task {
                            defer { working = false }
                            do { try await model.diagnostics.clear(); cleared = true }
                            catch { errorMessage = L10n.tr("Kayıtlar temizlenemedi.") }
                        }
                    }
                    .disabled(working || cleared)
                } header: { Text(L10n.tr("Destek")) } footer: {
                    Text(L10n.tr("Rapor yalnızca bağlantı ve hata kayıtlarını içerir. Rapora ekran görüntüsü ve ses eklenmez."))
                }
                .listRowBackground(MirrorStyle.surface)
                Section {
                    NavigationLink("VLCKit · VideoLAN") { ThirdPartyNoticesView() }
                    NavigationLink("Google Cast") { CastNoticesView() }
                }.listRowBackground(MirrorStyle.surface)
                Section {
                    Button(L10n.tr("Tüm kaynakları sil"), role: .destructive) { clearingLibrary = true }
                }.listRowBackground(MirrorStyle.surface)
                #if DEBUG
                Section(L10n.tr("Geliştirme")) {
                    NavigationLink(L10n.tr("Ekran bağlantı testi")) { ConnectionTestView(model: model) }
                }
                .listRowBackground(MirrorStyle.surface)
                #endif
            }
            .environment(\.defaultMinListRowHeight, MirrorStyle.controlHeight)
            .scrollContentBackground(.hidden)
            .background(MirrorStyle.background)
            .tint(MirrorStyle.accent)
            .navigationTitle(L10n.tr("Ayarlar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                        .accessibilityLabel(L10n.tr("Bitti"))
                        .accessibilityIdentifier("close-settings")
                }
            }
            .confirmationDialog(L10n.tr("Tüm kaynaklar ve kayıtlı giriş bilgileri silinsin mi?"), isPresented: $clearingLibrary, titleVisibility: .visible) {
                Button(L10n.tr("Tüm kaynakları sil"), role: .destructive) {
                    model.stopPlayback()
                    do { try SourceLibrary.shared.clear() } catch { errorMessage = L10n.tr("Kaynaklar silinemedi. Yeniden dene.") }
                }
            }
            .sheet(item: $report) { file in
                DiagnosticShareSheet(url: file.url)
                    .onDisappear { try? FileManager.default.removeItem(at: file.url) }
            }
            .alert(L10n.tr("Rapor"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(L10n.tr("Tamam")) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .environment(\.locale, Locale(identifier: L10n.language))
        .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
        .preferredColorScheme(.dark)
    }

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(version) (\(build))"
    }
}

private struct ReportFile: Identifiable { let url: URL; var id: String { url.lastPathComponent } }

private struct DiagnosticShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#if DEBUG
private struct ConnectionTestView: View {
    @ObservedObject var model: MirrorModel

    var body: some View {
        List {
            Section(L10n.tr("iOS bağlantısı")) {
                LabeledContent(L10n.tr("CarPlay sahnesi"), value: L10n.tr(model.carPlayConnected ? "Açık" : "Kapalı"))
                LabeledContent(L10n.tr("Araç video desteği"), value: L10n.tr(model.supportsVideo.map { $0 ? "Var" : "Yok" } ?? "Henüz okunmadı"))
                LabeledContent(L10n.tr("Harici ekran sayısı"), value: "\(model.externalScreenCount)")
            }
            Section {
                Button(L10n.tr("CarPlay video testini başlat")) { model.startVideoProbe() }
                    .disabled(model.broadcasting || !model.carPlayConnected || model.supportsVideo != true)
                Button(L10n.tr("Harici ekran desenini başlat")) { model.startExternalProbe() }
                    .disabled(model.broadcasting || model.externalScreenCount == 0)
                Button(L10n.tr("Testi durdur"), role: .destructive) { model.stopProbe() }
                    .disabled(model.probeStartedAt == nil)
            } footer: {
                Text(L10n.tr("Araç ekranındaki sayacın değiştiğini kontrol et. Bu test bağlantı yolunu ölçer."))
            }
            if model.probeStartedAt != nil {
                VideoPlayer(player: model.playback.player).frame(height: 180)
            }
        }
        .navigationTitle(L10n.tr("Bağlantı testi"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stopProbe() }
    }
}
#endif
