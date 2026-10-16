import SwiftUI
import StoreKit

struct MembershipOfferPresenter: ViewModifier {
    @ObservedObject var model: MirrorModel
    var restoredPlayer = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: {
            model.presentingPlayer == restoredPlayer && model.presentingMembership
        }, set: { model.presentingMembership = $0 })) {
            NavigationStack { ProView() }
        }
    }
}

struct ProView: View {
    let allowsBrowsing: Bool
    let showsCloseButton: Bool
    private let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var store = PurchaseStore.shared
    private var annual: Product? { store.products.first { $0.id == ProProduct.yearly.rawValue } }
    private var offersTrial: Bool { annual.map(store.hasThreeDayTrial) ?? false }

    init(allowsBrowsing: Bool = false, showsCloseButton: Bool = true, onClose: (() -> Void)? = nil) {
        self.allowsBrowsing = allowsBrowsing
        self.showsCloseButton = showsCloseButton
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                benefits
                if store.verifiedPro {
                    Label(L10n.tr("Pro etkin"), systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(MirrorStyle.accent)
                        .padding(20).frame(maxWidth: .infinity)
                        .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                } else if let annual {
                    plan(annual)
                    if offersTrial { trialTimeline(annual) }
                } else if store.busy {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    VStack(spacing: 12) {
                        Text(L10n.tr("Planlar yüklenemedi. Biraz sonra yeniden dene."))
                            .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                        Button(L10n.tr("Planları yeniden yükle")) { Task { await store.loadProducts() } }
                            .buttonStyle(MirivoButtonStyle()).accessibilityIdentifier("pro-reload")
                    }
                }
                if dynamicTypeSize.isAccessibilitySize { purchaseControls }
                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.tr("Canlı altyazılar"), systemImage: "captions.bubble")
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.tr("Desteklenen dillerde ekran paylaşımına cihaz içi altyazı ekle."))
                    Text(L10n.tr("CarPlay video, destekleyen araçlarda park halindeyken kullanılabilir."))
                    Text(L10n.tr("Mirivo içerik sağlamaz. Kendi kaynağını ekleyerek başlayabilirsin."))
                }
                .font(.footnote).foregroundStyle(MirrorStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                footer
            }
            .padding(24).frame(maxWidth: 580).frame(maxWidth: .infinity)
        }
        .background(MirrorStyle.background).tint(MirrorStyle.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if allowsBrowsing || (!dynamicTypeSize.isAccessibilitySize && !store.verifiedPro && annual != nil) {
                purchaseArea
            }
        }
        .navigationTitle(L10n.tr("Mirivo Pro")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { close() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel(L10n.tr("Kapat")).accessibilityIdentifier("pro-close")
                }
            }
        }
        .task { await store.loadProducts(reportErrors: !allowsBrowsing) }
        .onChange(of: store.verifiedPro) { _, active in
            if active && showsCloseButton { close() }
        }
        .alert(L10n.tr("Mirivo Pro"), isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button(L10n.tr("Tamam")) { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private func close() {
        if let onClose { onClose() }
        else { dismiss() }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            MirivoScreensArtwork().frame(height: dynamicTypeSize.isAccessibilitySize ? 100 : 138)
            Text(L10n.tr(store.verifiedPro ? "Tüm özellikler seninle." : "Kaynakların, her ekranda."))
                .font(.largeTitle.bold()).tracking(L10n.appLanguage.allowsLetterSpacing ? -0.8 : 0)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            Text("IPTV · Smart TV · CarPlay")
                .font(.subheadline.weight(.medium)).foregroundStyle(MirrorStyle.accent)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var benefits: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            benefit("Sınırsız izleme", symbol: "play.rectangle")
            benefit("Sınırsız kaynak", symbol: "rectangle.stack")
            benefit("Sınırsız yayın", symbol: "airplay.video")
        }
    }

    private func benefit(_ title: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(MirrorStyle.accent).accessibilityHidden(true)
            Text(L10n.tr(title)).font(.caption.weight(.medium))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 74).padding(10)
        .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func plan(_ product: Product) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(MirrorStyle.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr(offersTrial ? "3 gün ücretsiz deneme" : "Yıllık")).font(.headline)
                Text(L10n.tr(offersTrial ? "Yıllık" : "Yılda bir tahsil edilir; otomatik yenilenir."))
                    .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 5) {
                Text(product.displayPrice).font(.title2.weight(.semibold))
                Text(L10n.tr("Yıllık")).font(.caption).foregroundStyle(MirrorStyle.secondary)
            }.fixedSize(horizontal: true, vertical: true)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(MirrorStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(MirrorStyle.accent, lineWidth: 1.5) }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isSelected)
        .accessibilityIdentifier("pro-plan-com.alperbicer.carmirror.pro.yearly")
    }

    private func trialTimeline(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.tr("Bugün: tüm Pro özelliklerini dene."), systemImage: "lock.open")
            Label(String(format: L10n.tr("3 gün sonra: %@ / yıl. Otomatik yenilenir."), product.displayPrice), systemImage: "calendar")
        }
        .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("pro-trial-timeline")
    }

    private var purchaseArea: some View {
        VStack(spacing: 10) {
            if !dynamicTypeSize.isAccessibilitySize { purchaseControls }
            if allowsBrowsing {
                Button(L10n.tr("Şimdilik keşfet")) { close() }
                    .font(.subheadline.weight(.medium)).foregroundStyle(MirrorStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("onboarding-continue-free")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: 580).frame(maxWidth: .infinity)
        .background(MirrorStyle.background)
        .overlay(alignment: .top) { Rectangle().fill(MirrorStyle.hairline).frame(height: 0.5) }
    }

    @ViewBuilder
    private var purchaseControls: some View {
        if !store.verifiedPro, let annual {
            VStack(spacing: 10) {
                Button { Task { await store.purchase(annual) } } label: {
                    HStack(spacing: 10) {
                        if store.busy { ProgressView().tint(MirrorStyle.background) }
                        Text(L10n.tr(offersTrial ? "Ücretsiz denemeyi başlat" : "Abone ol"))
                        Image(systemName: "arrow.forward").accessibilityHidden(true)
                    }
                }
                .buttonStyle(MirivoButtonStyle(prominent: true)).disabled(!store.canPurchase(annual))
                .accessibilityIdentifier("pro-purchase")
                Text(offersTrial
                    ? String(format: L10n.tr("3 gün ücretsiz, sonra %@ / yıl."), annual.displayPrice)
                    : String(format: L10n.tr("%@ / yıl. Otomatik yenilenir."), annual.displayPrice))
                    .font(.footnote.weight(.medium)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("pro-billing-summary")
                Text(L10n.tr("App Store’dan istediğin zaman iptal edebilirsin."))
                    .font(.caption).foregroundStyle(MirrorStyle.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button(L10n.tr("Satın alımları geri yükle")) { Task { await store.restore() } }
                .disabled(store.busy).frame(minHeight: 44).accessibilityIdentifier("pro-restore")
            if store.subscriptionActive {
                Link(L10n.tr("Aboneliği yönet"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    .frame(minHeight: 44)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { legalLinks }
                VStack(spacing: 4) { legalLinks }
            }
        }.font(.footnote).frame(maxWidth: .infinity)
    }

    private var legalLinks: some View {
        Group {
            Link(L10n.tr("Gizlilik"), destination: BrandIdentity.privacyURL)
                .frame(minHeight: 44).accessibilityIdentifier("pro-privacy")
            Link(L10n.tr("Kullanım koşulları"), destination: BrandIdentity.termsURL)
                .frame(minHeight: 44).accessibilityIdentifier("pro-terms")
        }
    }
}
