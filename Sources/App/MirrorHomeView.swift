import SwiftUI

struct MirrorHomeView: View {
    @ObservedObject var model: MirrorModel
    private let accent = Color(red: 0.35, green: 0.91, blue: 0.77)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    connectionCard
                    broadcastCard
                    steps
                    playbackControls
                    diagnostics
                    Text("Ekran paylaşımı açıkken ekrandaki bildirimler de görünebilir. Görüntüyü yalnızca park hâlinde kullan.")
                        .font(.footnote).foregroundStyle(.secondary).lineSpacing(3)
                }
                .padding(24)
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.09))
            .navigationTitle("CarMirror")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("PROTOTİP").font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4).foregroundStyle(accent)
                }
            }
            .alert("CarMirror", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("Tamam") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
            .sheet(isPresented: $model.showingPreview, onDismiss: { model.stopPlayback() }) {
                NavigationStack {
                    VStack(spacing: 12) {
                        StreamPlayerView(player: model.playback.player)
                        Text("Bu önizleme iPhone’daki yayını gösterir. Başka bir uygulamaya geçtiğinde önizleme kapanır, ekran yayını devam eder.")
                            .font(.footnote).foregroundStyle(.secondary).padding()
                    }
                    .navigationTitle("Canlı önizleme").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { model.stopPlayback() } } }
                }.preferredColorScheme(.dark)
            }
        }.tint(accent)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                Image(systemName: "iphone.radiowaves.left.and.right").font(.system(size: 38, weight: .light))
                Image(systemName: "arrow.right").font(.title3).opacity(0.5)
                Image(systemName: "car.side").font(.system(size: 43, weight: .light))
            }.foregroundStyle(accent).padding(.vertical, 14).accessibilityHidden(true)
            Text("Telefonundaki görüntü.\nAracındaki ekran.")
                .font(.system(size: 32, weight: .semibold, design: .rounded)).tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ekranını paylaş, sevdiğin uygulamayı aç.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusRow(icon: "record.circle", title: model.captureTitle, active: model.broadcasting)
            Divider()
            statusRow(icon: "car", title: model.carTitle, active: model.carPlayConnected)
            if !model.carPlayBuild {
                Text("Bu sürüm ekran yayınını telefonda test eder. Araç entegrasyonu için CarPlay yetkili derleme gerekir.")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            }
        }.card()
    }

    private var broadcastCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.broadcasting ? "Ekranın paylaşılıyor" : "Ekranı paylaş")
                    .font(.headline)
                Text("Sağdaki yayın düğmesine dokun; açılan iOS penceresinde CarMirror’ı seç.")
                    .font(.caption).foregroundStyle(.white.opacity(0.8)).lineSpacing(3)
            }
            Spacer(minLength: 0)
            BroadcastPicker().frame(width: 60, height: 60)
                .background(.white.opacity(0.15), in: Circle())
                .allowsHitTesting(model.storageReady)
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0.07, green: 0.36, blue: 0.34),
                                            Color(red: 0.07, green: 0.23, blue: 0.29)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24))
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 18) {
            step("1", title: "Ekran yayınını başlat", detail: "iOS’un paylaşım onayını ver. Yayın birkaç saniyede hazırlanır.")
            step("2", title: "Araçta CarMirror’ı aç", detail: "Desteklenen bağlantıda “iPhone ekranı” satırını seç.")
            step("3", title: "YouTube veya IPTV’yi aç", detail: "Telefonu yatay çevirerek görüntüyü büyütebilirsin.")
        }
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { model.startPreview() } label: {
                Label("Yayını telefonda önizle", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.bordered).disabled(!model.readyToPlay)
            if model.carPlayConnected && model.supportsVideo == true {
                Button { model.playInCar() } label: {
                    Label("Araçta oynatmayı başlat", systemImage: "car.side")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).disabled(!model.readyToPlay)
                HStack {
                    Text("AirPlay hedefi").font(.subheadline)
                    Spacer()
                    RoutePicker().frame(width: 44, height: 44)
                }
            }
            if model.broadcasting {
                Button(role: .destructive) { model.stopBroadcast() } label: {
                    Label("Paylaşımı durdur", systemImage: "stop.circle").frame(maxWidth: .infinity)
                }.padding(.top, 4)
            }
            Text("Bu ilk sürüm görüntü aktarır. Ses, kaynak uygulamanın mevcut araç ses bağlantısında kalır. Korumalı videolar paylaşımda siyah görünebilir.")
                .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("Bağlantı ayrıntıları") {
            VStack(spacing: 12) {
                detail("Derleme", model.carPlayBuild ? "CarPlay Video" : "iPhone / önizleme")
                detail("Alınan kare", "\(model.capture?.receivedFrames ?? 0)")
                detail("Kodlanan kare", "\(model.capture?.encodedFrames ?? 0)")
                detail("Üretilen bölüm", "\(model.capture?.segmentCount ?? 0)")
                detail("Bellekteki yayın", ByteCountFormatter.string(fromByteCount: Int64(model.capture?.bufferedBytes ?? 0), countStyle: .memory))
                PlaybackDiagnostics(playback: model.playback)
                if let message = model.capture?.message { Text(message).font(.caption).foregroundStyle(.orange) }
                Text("Araç bağlantısı, video desteği ve harici oynatma ayrı ayrı ölçülür. Araç ekranındaki görüntü fiziksel testte doğrulanır.")
                    .font(.caption).foregroundStyle(.secondary)
                #if targetEnvironment(simulator)
                Text("Simülatör arayüz testi içindir. Ekran yayını için fiziksel iPhone gerekir.")
                    .font(.caption).foregroundStyle(.secondary)
                #endif
            }.padding(.top, 16)
        }.font(.subheadline).card()
    }

    private func statusRow(icon: String, title: String, active: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(active ? accent : .secondary).frame(width: 24)
            Text(title).font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
            Circle().fill(active ? accent : Color.gray.opacity(0.45)).frame(width: 7, height: 7)
        }
    }

    private func step(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.caption.bold()).foregroundStyle(accent)
                .frame(width: 26, height: 26).background(accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineSpacing(2)
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value).font(.caption).foregroundStyle(.secondary)
    }
}

private struct PlaybackDiagnostics: View {
    @ObservedObject var playback: PlaybackController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Harici oynatma", value: playback.externalPlaybackActive ? "Etkin" : "Etkin değil")
            LabeledContent("Oynatıcı", value: playback.isPlaying ? "Oynatıyor" : "Bekliyor")
            if let error = playback.errorMessage { Text(error).foregroundStyle(.orange) }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

private extension View {
    func card() -> some View {
        padding(20).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}
