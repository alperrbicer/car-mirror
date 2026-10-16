import SwiftUI
import StoreKit

extension DailyViewingBudget.Limit {
    var explanation: String {
        L10n.tr(self == .carPlay
            ? "Bugünkü 1 saatlik CarPlay süren doldu. Yarın yeniden izleyebilir veya Pro ile sınırsız devam edebilirsin."
            : "Günlük 2 saatlik izleme sınırına ulaştın. Yarın yeniden izleyebilirsin.")
    }
}

struct ViewingLimitOfferPresenter: ViewModifier {
    @ObservedObject var model: MirrorModel
    var restoredPlayer = false

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: {
            model.presentingPlayer == restoredPlayer ? model.viewingLimitPrompt : nil
        }, set: { model.viewingLimitPrompt = $0 })) { limit in
            NavigationStack { ProView(viewingLimit: limit) }
        }
    }
}

struct ProView: View {
    let viewingLimit: DailyViewingBudget.Limit?
    let allowsFreeContinuation: Bool
    let showsCloseButton: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var store = PurchaseStore.shared
    @State private var selectedID = ProProduct.yearly.rawValue
    private let benefits: [(String, String, String)] = [
        ("play.rectangle", "Sınırsız izleme", "Pro ile günlük izleme sınırı olmadan devam et."),
        ("infinity", "Sınırsız kaynak", "Oynatma listelerini, yayın bağlantılarını ve IPTV sunucularını bir arada tut."),
        ("captions.bubble", "Canlı altyazılar", "Desteklenen dillerde ekran paylaşımına cihaz içi altyazı ekle."),
        ("rectangle.on.rectangle", "Sınırsız yayın", "Ekran paylaşımını Mirivo süre sınırı olmadan kullan.")
    ]
    private var selected: Product? { store.products.first { $0.id == selectedID } }
    init(viewingLimit: DailyViewingBudget.Limit? = nil, allowsFreeContinuation: Bool = false,
         showsCloseButton: Bool = true) {
        self.viewingLimit = viewingLimit
        self.allowsFreeContinuation = allowsFreeContinuation
        self.showsCloseButton = showsCloseButton
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    MirrorMark().frame(width: 42, height: 42)
                    Spacer()
                    Text(L10n.tr("PRO")).font(.caption.weight(.bold)).tracking(2)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(MirrorStyle.accent.opacity(0.12), in: Capsule()).foregroundStyle(MirrorStyle.accent)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Mirivo Pro")).font(.system(.largeTitle, design: .default, weight: .bold))
                    Text(L10n.tr(store.verifiedPro ? "Tüm özellikler seninle." : "Büyük ekranda daha fazlası."))
                        .font(.title3).foregroundStyle(MirrorStyle.secondary)
                }
                if let viewingLimit {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.tr("Bugünkü ücretsiz süren doldu"), systemImage: "clock")
                            .font(.headline).foregroundStyle(MirrorStyle.accent)
                        Text(viewingLimit.explanation).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MirrorStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityElement(children: .contain).accessibilityIdentifier("viewing-limit-offer")
                }
                VStack(spacing: 24) {
                    ForEach(benefits, id: \.0) { icon, title, subtitle in
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                        layout {
                            Image(systemName: icon).font(.title2)
                                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 32)
                                .foregroundStyle(MirrorStyle.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(L10n.tr(title)).font(.headline)
                                Text(L10n.tr(subtitle)).font(.subheadline).foregroundStyle(MirrorStyle.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        }
                    }
                }.padding(22).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 26))
                if store.verifiedPro {
                    Label(L10n.tr("Pro etkin"), systemImage: "checkmark.seal.fill").foregroundStyle(MirrorStyle.accent)
                }
                if !store.lifetimeOwned {
                    if store.busy && store.products.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(20)
                    }
                    ForEach(store.products, id: \.id) { product in
                        Button { selectedID = product.id } label: {
                            let layout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                                : AnyLayout(HStackLayout(spacing: 14))
                            layout {
                                Image(systemName: selectedID == product.id ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(title(product)).font(.headline)
                                    Text(L10n.tr(product.type == .nonConsumable ? "Tek seferlik ödeme" : "Yılda bir tahsil edilir; otomatik yenilenir.")).font(.caption)
                                        .foregroundStyle(MirrorStyle.secondary).fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("pro-description-\(product.id)")
                                }
                                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                                Text(product.displayPrice).font(.title3.weight(.semibold))
                                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                            }.padding(20).frame(maxWidth: .infinity)
                                .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                                .overlay { RoundedRectangle(cornerRadius: 22).stroke(selectedID == product.id ? MirrorStyle.accent : .clear, lineWidth: 1.5) }
                        }.buttonStyle(.plain)
                            .disabled(store.busy || (store.verifiedPro && product.id != ProProduct.lifetime.rawValue))
                            .accessibilityIdentifier("pro-plan-\(product.id)")
                            .accessibilityAddTraits(selectedID == product.id ? .isSelected : [])
                    }
                    if let selected {
                        Text(L10n.tr(selected.type == .nonConsumable
                            ? "Tek ödeme ile Mirivo Pro özelliklerine kalıcı erişim. Abonelik veya otomatik yenileme yok."
                            : "Ödeme Apple hesabından alınır. Abonelik iptal edilmedikçe seçtiğin dönem ve fiyatla otomatik yenilenir. App Store hesap ayarlarından yönetebilirsin."))
                            .font(.footnote).foregroundStyle(MirrorStyle.secondary)
                        if store.subscriptionActive && selected.id == ProProduct.lifetime.rawValue {
                            Text(L10n.tr("Ömür boyu satın almak mevcut aboneliği otomatik iptal etmez. Apple hesabından iptal edebilirsin."))
                                .font(.footnote).foregroundStyle(MirrorStyle.secondary)
                        }
                        Button { Task { await store.purchase(selected) } } label: {
                            HStack { if store.busy { ProgressView() }; Text("\(selected.displayPrice) · \(L10n.tr("Satın al"))") }
                        }.buttonStyle(MirivoButtonStyle(prominent: true)).disabled(!store.canPurchase(selected))
                            .accessibilityIdentifier("pro-purchase")
                    } else if !store.busy {
                        if allowsFreeContinuation {
                            Text(L10n.tr("Planlar yüklenemedi. Biraz sonra yeniden dene."))
                                .font(.footnote).foregroundStyle(MirrorStyle.secondary)
                        }
                        Button(L10n.tr("Planları yeniden yükle")) { Task { await store.loadProducts() } }
                            .buttonStyle(MirivoButtonStyle())
                            .accessibilityIdentifier("pro-reload")
                    }
                }
                Text(L10n.tr("Ücretsiz izleme günde 2 saat."))
                    .font(.footnote).foregroundStyle(MirrorStyle.secondary)
                VStack(spacing: 16) {
                    if store.salesEnabled || store.verifiedPro {
                        Button(L10n.tr("Satın alımları geri yükle")) { Task { await store.restore() } }
                            .buttonStyle(MirivoButtonStyle()).disabled(store.busy)
                            .accessibilityIdentifier("pro-restore")
                        Link(L10n.tr("Aboneliği yönet"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                            .frame(minHeight: 44)
                    }
                    HStack(spacing: 20) {
                        Link(L10n.tr("Gizlilik"), destination: BrandIdentity.privacyURL)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("pro-privacy")
                        Link(L10n.tr("Kullanım koşulları"), destination: BrandIdentity.termsURL)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("pro-terms")
                    }
                }.font(.footnote).frame(maxWidth: .infinity)
            }.padding(24).frame(maxWidth: 580).frame(maxWidth: .infinity)
        }
        .background(MirrorStyle.background).tint(MirrorStyle.accent)
        .safeAreaInset(edge: .bottom) {
            if allowsFreeContinuation {
                Button(L10n.tr("Ücretsiz devam et")) { dismiss() }
                    .buttonStyle(MirivoButtonStyle())
                    .accessibilityIdentifier("onboarding-continue-free")
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .frame(maxWidth: 580).frame(maxWidth: .infinity)
                    .background(MirrorStyle.background)
            }
        }
        .navigationTitle(L10n.tr("Mirivo Pro")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    }.accessibilityLabel(L10n.tr("Kapat")).accessibilityIdentifier("pro-close")
                }
            }
        }
        .task {
            await store.loadProducts(reportErrors: !allowsFreeContinuation)
            if store.subscriptionActive { selectedID = ProProduct.lifetime.rawValue }
            else if selected == nil, let first = store.products.first { selectedID = first.id }
        }
        .onChange(of: store.subscriptionActive) { _, active in
            if active { selectedID = ProProduct.lifetime.rawValue }
        }
        .onChange(of: store.verifiedPro) { _, active in
            if active && allowsFreeContinuation { dismiss() }
        }
        .alert(L10n.tr("Mirivo Pro"), isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button(L10n.tr("Tamam")) { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
    private func title(_ product: Product) -> String {
        L10n.tr(product.id == ProProduct.yearly.rawValue ? "Yıllık" : "Ömür boyu")
    }
}
