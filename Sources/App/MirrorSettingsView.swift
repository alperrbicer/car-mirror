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
    @State private var showingDailyBudgetReset = false
    @State private var hiddenResetSequence: [String] = []
    @State private var hiddenResetLastTap = Date.distantPast
    @AppStorage("language", store: SharedPreferences.defaults) private var language = "system"
    @AppStorage("streamQuality", store: SharedPreferences.defaults) private var quality = StreamQuality.balanced.rawValue
    @AppStorage("audioMode", store: SharedPreferences.defaults) private var audioMode = StreamAudioMode.synchronized.rawValue
    @AppStorage("player.edgeGestureIntroShown") private var edgeGestureIntroShown = false
    @ObservedObject private var purchases = PurchaseStore.shared
    @AppStorage("analytics.enabled") private var analyticsEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Button { registerHiddenResetTap("brand") } label: {
                            MirrorMark().frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("Mirivo"))
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
                            Text(L10n.tr(purchases.verifiedPro ? "Etkin" : "Keşfet"))
                                .font(.caption).foregroundStyle(MirrorStyle.accent)
                        }
                    }.accessibilityIdentifier("settings-pro")
                }.listRowBackground(MirrorStyle.surface)
                Section(L10n.tr("Tercihler")) {
                    NavigationLink { NotificationSettingsView() } label: {
                        Label(L10n.tr("Bildirimler"), systemImage: "bell")
                    }.accessibilityIdentifier("settings-notifications")
                    NavigationLink { LanguageSettingsView() } label: {
                        LabeledContent(L10n.tr("Dil"), value: language == "system" ? L10n.tr("Sistemi izle") : L10n.appLanguage.nativeName)
                    }.accessibilityIdentifier("settings-language")
                    Picker(L10n.tr("Yayın kalitesi"), selection: $quality) {
                        Text(L10n.tr("Dengeli")).tag(StreamQuality.balanced.rawValue)
                        Text(L10n.tr("Yüksek")).tag(StreamQuality.high.rawValue)
                    }.accessibilityIdentifier("settings-quality")
                    Picker(L10n.tr("Ses"), selection: $audioMode) {
                        Text(L10n.tr("Görüntüyle birlikte")).tag(StreamAudioMode.synchronized.rawValue)
                        Text(L10n.tr("Kaynak uygulamadan")).tag(StreamAudioMode.source.rawValue)
                    }.accessibilityIdentifier("settings-audio")
                    if purchases.access.fullAccess {
                        NavigationLink(L10n.tr("Canlı altyazılar")) { CaptionSettingsView() }
                    } else {
                        NavigationLink(L10n.tr("Canlı altyazılar · Pro")) { ProView() }
                    }
                }.listRowBackground(MirrorStyle.surface)
                playerGestureIntroSection
                Section {
                    Toggle(L10n.tr("Kullanım analizi"), isOn: $analyticsEnabled)
                        .disabled(!FirebaseServices.configured)
                        .accessibilityIdentifier("settings-analytics")
                        .onChange(of: analyticsEnabled) { _, _ in FirebaseServices.applyAnalyticsPreference(reset: true) }
                } footer: {
                    Text(L10n.tr("Mirivo’yu geliştirmek için kullanım istatistiklerini paylaş. Medya, kaynak adresleri ve arama metinleri gönderilmez. İstediğin zaman kapatabilirsin."))
                }.listRowBackground(MirrorStyle.surface)
                Section(L10n.tr("Yasal")) {
                    Link(L10n.tr("Gizlilik Politikası"), destination: BrandIdentity.privacyURL)
                        .accessibilityIdentifier("settings-privacy")
                    Link(L10n.tr("Kullanım Koşulları (EULA)"), destination: BrandIdentity.termsURL)
                        .accessibilityIdentifier("settings-terms")
                }.listRowBackground(MirrorStyle.surface)
                Section(L10n.tr("Hakkında")) {
                    Link(L10n.tr("Yardım ve SSS"), destination: BrandIdentity.supportURL)
                        .accessibilityIdentifier("settings-support")
                    Link(L10n.tr("Bize ulaş"), destination: URL(string: "mailto:alperrbicer@gmail.com?subject=Mirivo")!)
                    Button { registerHiddenResetTap("version") } label: {
                        LabeledContent(L10n.tr("Sürüm"), value: version)
                    }
                    .buttonStyle(.plain)
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
                    NavigationLink("VLCKit · VideoLAN") { ThirdPartyNoticesView() }.accessibilityIdentifier("settings-vlc")
                    NavigationLink("Google Cast") { CastNoticesView() }.accessibilityIdentifier("settings-cast")
                }.listRowBackground(MirrorStyle.surface)
                Section {
                    Button(L10n.tr("Tüm kaynakları sil"), role: .destructive) { clearingLibrary = true }
                }.listRowBackground(MirrorStyle.surface)
                #if DEBUG
                Section(L10n.tr("Geliştirme")) {
                    NavigationLink(L10n.tr("Ekran bağlantı testi")) { ConnectionTestView(model: model) }.accessibilityIdentifier("settings-connection-test")
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
            .confirmationDialog(L10n.tr("Bugünkü ücretsiz izleme süresi sıfırlansın mı?"), isPresented: $showingDailyBudgetReset, titleVisibility: .visible) {
                Button(L10n.tr("Sıfırla"), role: .destructive) {
                    model.resetDailyViewingBudget()
                    errorMessage = L10n.tr("Bugünkü ücretsiz izleme süren sıfırlandı. Bugün 2 saate kadar izleyebilirsin.")
                }
                Button(L10n.tr("İptal"), role: .cancel) { }
            }
            .sheet(item: $report) { file in
                DiagnosticShareSheet(url: file.url)
                    .onDisappear { try? FileManager.default.removeItem(at: file.url) }
            }
            .alert(L10n.tr("Mirivo"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(L10n.tr("Tamam")) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .environment(\.locale, Locale(identifier: L10n.language))
        .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
        .preferredColorScheme(.dark)
        .onAppear { FirebaseServices.recordScreen(.settings) }
    }

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(version) (\(build))"
    }

    private var playerGestureIntroSection: some View {
        Section {
            Button {
                edgeGestureIntroShown = false
                errorMessage = L10n.tr("Hareket tanıtımı sıfırlandı. Yatay tam ekranı bir sonraki açışında gösterilecek.")
            } label: {
                Label(L10n.tr("Hareket tanıtımını yeniden göster"), systemImage: "hand.draw")
            }
            .accessibilityIdentifier("settings-player-gesture-intro")
        } header: {
            Text(L10n.tr("Oynatıcı"))
        } footer: {
            Text(L10n.tr("Ses, parlaklık ve ekran hareketlerini oynatıcıda tekrar göster."))
        }
        .listRowBackground(MirrorStyle.surface)
    }

    // Hidden maintenance shortcut: tap the brand mark three times, then the version row twice.
    private func registerHiddenResetTap(_ key: String) {
        let now = Date()
        if now.timeIntervalSince(hiddenResetLastTap) > 4 { hiddenResetSequence = [] }
        hiddenResetLastTap = now

        let expected = ["brand", "brand", "brand", "version", "version"]
        guard hiddenResetSequence.count < expected.count,
              expected[hiddenResetSequence.count] == key else {
            hiddenResetSequence = key == expected[0] ? [key] : []
            return
        }

        hiddenResetSequence.append(key)
        if hiddenResetSequence == expected {
            hiddenResetSequence = []
            showingDailyBudgetReset = true
        }
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
                Text(L10n.tr("Hareketli ekran bağlantı testi"))
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
