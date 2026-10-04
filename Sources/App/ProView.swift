import SwiftUI
import StoreKit

struct ProView: View {
    @ObservedObject private var store = PurchaseStore.shared
    @State private var selectedID = ProProduct.lifetime.rawValue
    private let benefits: [(String, String, String)] = [
        ("play.rectangle", "Sınırsız izleme", "Pro ile günlük izleme sınırı olmadan devam et."),
        ("infinity", "Sınırsız kaynak", "Oynatma listelerini, yayın bağlantılarını ve IPTV sunucularını bir arada tut."),
        ("car.side", "Araç modu", "Geniş oynatıcı, büyük kontroller ve sade bir izleme alanı."),
        ("captions.bubble", "Canlı altyazılar", "Desteklenen dillerde ekran paylaşımına cihaz içi altyazı ekle."),
        ("rectangle.on.rectangle", "Sınırsız yayın", "Ekran paylaşımını Mirivo süre sınırı olmadan kullan.")
    ]
    private var selected: Product? { store.products.first { $0.id == selectedID } }
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
                    Text(L10n.tr(store.verifiedPro ? "Tüm özellikler seninle." : "Telefonunda ve aracında daha fazlası."))
                        .font(.title3).foregroundStyle(MirrorStyle.secondary)
                }
                VStack(spacing: 24) {
                    ForEach(benefits, id: \.0) { icon, title, subtitle in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: icon).font(.title2).frame(width: 32).foregroundStyle(MirrorStyle.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(L10n.tr(title)).font(.headline)
                                Text(L10n.tr(subtitle)).font(.subheadline).foregroundStyle(MirrorStyle.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }.padding(22).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 26))
                if store.verifiedPro {
                    Label(L10n.tr("Pro etkin"), systemImage: "checkmark.seal.fill").foregroundStyle(MirrorStyle.accent)
                } else {
                    if store.busy && store.products.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(20)
                    }
                    ForEach(store.products, id: \.id) { product in
                        Button { selectedID = product.id } label: {
                            HStack(spacing: 14) {
                                Image(systemName: selectedID == product.id ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(title(product)).font(.headline)
                                    Text(L10n.tr(product.type == .nonConsumable ? "Tek seferlik ödeme" : "Otomatik yenilenir; istediğin zaman iptal et.")).font(.caption)
                                }
                                Spacer()
                                Text(price(product)).font(.title3.weight(.semibold))
                            }.padding(20).frame(maxWidth: .infinity)
                                .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                                .overlay { RoundedRectangle(cornerRadius: 22).stroke(selectedID == product.id ? MirrorStyle.accent : .clear, lineWidth: 1.5) }
                        }.buttonStyle(.plain)
                    }
                    if let selected {
                        Text(L10n.tr(selected.type == .nonConsumable
                            ? "Tek ödeme ile Mirivo Pro özelliklerine kalıcı erişim. Abonelik veya otomatik yenileme yok."
                            : "Ödeme Apple hesabından alınır. Abonelik iptal edilmedikçe seçtiğin dönem ve fiyatla otomatik yenilenir. App Store hesap ayarlarından yönetebilirsin."))
                            .font(.footnote).foregroundStyle(MirrorStyle.secondary)
                        Button { Task { await store.purchase(selected) } } label: {
                            HStack { if store.busy { ProgressView() }; Text("\(selected.displayPrice) · \(L10n.tr("Satın al"))") }
                        }.buttonStyle(MirivoButtonStyle(prominent: true)).disabled(store.busy)
                    } else if !store.busy {
                        Button(L10n.tr("Planları yeniden yükle")) { Task { await store.loadProducts() } }
                            .buttonStyle(MirivoButtonStyle())
                    }
                }
                Text(L10n.tr("Ücretsiz izleme günde 2 saat. Mirivo’nun hiçbir sürümünde reklam yok."))
                    .font(.footnote).foregroundStyle(MirrorStyle.secondary)
                VStack(spacing: 16) {
                    if store.salesEnabled || store.verifiedPro {
                        Button(L10n.tr("Satın alımları geri yükle")) { Task { await store.restore() } }
                            .buttonStyle(MirivoButtonStyle()).disabled(store.busy)
                        Link(L10n.tr("Aboneliği yönet"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                            .frame(minHeight: 44)
                    }
                    HStack(spacing: 20) {
                        NavigationLink(L10n.tr("Gizlilik")) { LegalDocumentView(page: .privacy) }
                            .frame(minHeight: 44)
                        NavigationLink(L10n.tr("Kullanım koşulları")) { LegalDocumentView(page: .terms) }
                            .frame(minHeight: 44)
                    }
                }.font(.footnote).frame(maxWidth: .infinity)
            }.padding(24).frame(maxWidth: 580).frame(maxWidth: .infinity)
        }
        .background(MirrorStyle.background).tint(MirrorStyle.accent)
        .navigationTitle(L10n.tr("Mirivo Pro")).navigationBarTitleDisplayMode(.inline)
        .task { await store.loadProducts(); if selected == nil, let first = store.products.first { selectedID = first.id } }
        .alert(L10n.tr("Mirivo Pro"), isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button(L10n.tr("Tamam")) { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
    private func price(_ product: Product) -> String {
        let period = product.id == ProProduct.weekly.rawValue ? L10n.tr("Haftalık")
            : product.id == ProProduct.yearly.rawValue ? L10n.tr("Yıllık") : ""
        return period.isEmpty ? product.displayPrice : "\(product.displayPrice) · \(period)"
    }
    private func title(_ product: Product) -> String {
        L10n.tr(product.id == ProProduct.weekly.rawValue ? "Haftalık" : product.id == ProProduct.yearly.rawValue ? "Yıllık" : "Ömür boyu")
    }
}
