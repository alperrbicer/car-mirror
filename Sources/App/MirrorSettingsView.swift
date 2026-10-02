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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        working = true
                        Task {
                            defer { working = false }
                            do { report = ReportFile(url: try await model.diagnostics.export()) }
                            catch { errorMessage = "Rapor hazırlanamadı. Lütfen yeniden dene." }
                        }
                    } label: {
                        HStack {
                            Label("Tanılama raporunu paylaş", systemImage: "square.and.arrow.up")
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working)
                    Button(cleared ? "Kayıtlar temizlendi" : "Kayıtları temizle", role: .destructive) {
                        working = true
                        Task {
                            defer { working = false }
                            do { try await model.diagnostics.clear(); cleared = true }
                            catch { errorMessage = "Kayıtlar temizlenemedi." }
                        }
                    }
                    .disabled(working || cleared)
                } header: { Text("Destek") } footer: {
                    Text("Rapor yalnızca bağlantı ve hata kayıtlarını içerir. Rapora ekran görüntüsü ve ses eklenmez.")
                }
                Section {
                    LabeledContent("Sürüm", value: version)
                }
                #if DEBUG
                Section("Geliştirme") {
                    NavigationLink("Ekran bağlantı testi") { ConnectionTestView(model: model) }
                }
                #endif
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .sheet(item: $report) { file in
                DiagnosticShareSheet(url: file.url)
                    .onDisappear { try? FileManager.default.removeItem(at: file.url) }
            }
            .alert("Rapor", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Tamam") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
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
            Section("iOS bağlantısı") {
                LabeledContent("CarPlay sahnesi", value: model.carPlayConnected ? "Açık" : "Kapalı")
                LabeledContent("Araç video desteği", value: model.supportsVideo.map { $0 ? "Var" : "Yok" } ?? "Henüz okunmadı")
                LabeledContent("Harici ekran sayısı", value: "\(model.externalScreenCount)")
            }
            Section {
                Button("CarPlay video testini başlat") { model.startVideoProbe() }
                    .disabled(model.broadcasting || !model.carPlayConnected || model.supportsVideo != true)
                Button("Harici ekran desenini başlat") { model.startExternalProbe() }
                    .disabled(model.broadcasting || model.externalScreenCount == 0)
                Button("Testi durdur", role: .destructive) { model.stopProbe() }
                    .disabled(model.probeStartedAt == nil)
            } footer: {
                Text("Araç ekranındaki sayacın değiştiğini kontrol et. Bu test bağlantı yolunu ölçer.")
            }
            if model.probeStartedAt != nil {
                VideoPlayer(player: model.playback.player).frame(height: 180)
            }
        }
        .navigationTitle("Bağlantı testi")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stopProbe() }
    }
}
#endif
