import SwiftUI

struct RequiredUpdateView: View {
    @ObservedObject var updates: AppUpdateStore
    let url: URL
    @Environment(\.openURL) private var openURL
    @State private var openFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                MirrorMark().frame(width: 72, height: 72)
                Text(L10n.tr("Güncelleme gerekli")).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.tr("Devam etmek için Mirivo’nun yeni sürümünü App Store’dan indir."))
                    .foregroundStyle(MirrorStyle.secondary).multilineTextAlignment(.center)
                Button {
                    openURL(url) { accepted in openFailed = !accepted }
                } label: {
                    Label(L10n.tr("App Store’da güncelle"), systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent).tint(MirrorStyle.accent).foregroundStyle(.black)
                .accessibilityIdentifier("required-update-store")
                Button(L10n.tr("Yeniden kontrol et")) { Task { await updates.refresh(force: true) } }
                    .frame(minHeight: 48).disabled(updates.checking)
                    .accessibilityIdentifier("required-update-retry")
                if updates.checking { ProgressView() }
                if openFailed { Text(L10n.tr("App Store açılamadı. Lütfen yeniden dene.")).foregroundStyle(MirrorStyle.secondary) }
            }
            .padding(32).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .background(MirrorStyle.background.ignoresSafeArea())
        .environment(\.locale, Locale(identifier: L10n.language))
        .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
        .accessibilityIdentifier("required-update-screen")
        .onAppear { FirebaseServices.recordScreen(.requiredUpdate) }
    }
}
