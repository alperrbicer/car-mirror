import SwiftUI
import StoreKit
import UserNotifications
import UIKit

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
    @ObservedObject private var reminders = TrialReminderStore.shared
    @State private var selectedID = ProProduct.yearly.rawValue
    @State private var copiedMembershipID = false
    @State private var measuredPaywall = false

    private var selected: Product? { store.products.first { $0.id == selectedID } ?? store.products.first }
    private var trialDays: Int? { selected.flatMap(store.freeTrialDays) }

    init(allowsBrowsing: Bool = false, showsCloseButton: Bool = true, onClose: (() -> Void)? = nil) {
        self.allowsBrowsing = allowsBrowsing
        self.showsCloseButton = showsCloseButton
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                benefits
                if store.verifiedPro {
                    Label(L10n.tr("Pro etkin"), systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(MirrorStyle.accent)
                        .padding(20).frame(maxWidth: .infinity)
                        .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                } else if let selected {
                    if let trialDays { trialTimeline(selected, days: trialDays) }
                    VStack(spacing: 10) {
                        ForEach(store.products, id: \.id) { product in plan(product) }
                        if store.products.count > 1 {
                            Text(L10n.tr("İki planda da tüm Pro özellikleri."))
                                .font(.caption).foregroundStyle(MirrorStyle.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
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
                Text(L10n.tr("Mirivo içerik sağlamaz. İndirme, içerik ve kaynağın desteğine bağlıdır."))
                    .font(.caption).foregroundStyle(MirrorStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                footer
            }
            .padding(24).frame(maxWidth: 580).frame(maxWidth: .infinity)
        }
        .background(MirrorStyle.background).tint(MirrorStyle.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if allowsBrowsing || (!dynamicTypeSize.isAccessibilitySize && !store.verifiedPro && selected != nil) {
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
        .task {
            if !measuredPaywall, !store.verifiedPro {
                measuredPaywall = true
                AppMeasurement.shared.record(MeasurementEvent(name: .paywallView, outcome: .success))
            }
            await reminders.refreshAuthorization()
            await store.loadProducts(reportErrors: !allowsBrowsing)
        }
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
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(LinearGradient(colors: [MirrorStyle.accent, MirrorStyle.accent.opacity(0.35)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 36, height: 3)
                .accessibilityHidden(true)
            Text(L10n.tr(store.verifiedPro ? "Tüm özellikler seninle." : "Mirivo Pro’yu kendi ekranlarında dene."))
                .font(.title.bold())
                .tracking(L10n.appLanguage.allowsLetterSpacing ? -0.6 : 0)
                .lineSpacing(3)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var benefits: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                feature("CarPlay’de video izle", detail: "Destekleyen araçlarda, park halindeyken.", symbol: "car.side")
                Rectangle()
                    .fill(MirrorStyle.hairline)
                    .frame(height: 1)
                    .padding(.leading, 72)
                    .padding(.trailing, 16)
                    .accessibilityHidden(true)
                feature("İndir, çevrimdışı izle", detail: "İndirdiğin videoları internet olmadan aç.", symbol: "arrow.down.circle")
            }
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(MirrorStyle.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LinearGradient(colors: [MirrorStyle.accent.opacity(0.08), .clear],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [MirrorStyle.accent.opacity(0.22), MirrorStyle.hairline],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
            }
            secondaryBenefits
        }
    }

    private var secondaryBenefits: some View {
        let layout = dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            chip("Süre sınırı yok", symbol: "infinity", accessibility: "Sınırsız izleme", id: "unlimited")
            chip("TV’ye aktar", symbol: "tv", accessibility: "İçeriklerini uyumlu bir TV’ye aktar veya ekranını paylaş.", id: "cast")
            chip("Kaldığın yerden", symbol: "play.circle", accessibility: "Bir bölüme başla, ara ver, kaldığın yerden sürdür. Mirivo izleme ilerlemeni hatırlar.", id: "resume")
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro-secondary-benefits")
    }

    private func feature(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(MirrorStyle.accent)
                .frame(width: 44, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [MirrorStyle.accent.opacity(0.18), MirrorStyle.accent.opacity(0.05)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(MirrorStyle.accent.opacity(0.16))
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.tr(title))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(L10n.tr(detail))
                    .font(.footnote)
                    .foregroundStyle(MirrorStyle.secondary)
                    .lineSpacing(2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private func chip(_ title: String, symbol: String, accessibility: String, id: String) -> some View {
        let stacked = dynamicTypeSize >= .xxxLarge
        let layout = stacked
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 8))
        return layout {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(MirrorStyle.accent)
                .frame(minWidth: 22, minHeight: 22)
                .accessibilityHidden(true)
            Text(L10n.tr(title))
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(stacked ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(L10n.tr(accessibility))
                .accessibilityIdentifier("pro-benefit-\(id)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: stacked ? nil : .infinity,
               alignment: stacked ? .leading : .top)
        .background(MirrorStyle.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MirrorStyle.hairline)
                .allowsHitTesting(false)
        }
    }

    private func plan(_ product: Product) -> some View {
        let isAnnual = product.id == ProProduct.yearly.rawValue
        let isSelected = selected?.id == product.id
        return Button {
            selectedID = product.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? MirrorStyle.accent : MirrorStyle.secondary)
                        .accessibilityHidden(true)
                    Text(L10n.tr(isAnnual ? "Yıllık" : "Haftalık")).font(.headline)
                    Spacer(minLength: 8)
                    if isAnnual, store.annualSavingsPercent != nil {
                        Text(L10n.tr("En avantajlı")).font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.accent)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        planPrice(product)
                        Spacer(minLength: 10)
                        planTrial(product)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        planPrice(product)
                        planTrial(product)
                    }
                }
                if isAnnual, let saving = store.annualSavingsPercent {
                    Text(String(format: L10n.tr("52 haftalık ödemeye göre yaklaşık %d%% daha az."), saving))
                        .font(.caption2).foregroundStyle(MirrorStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? MirrorStyle.accent.opacity(0.08) : MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(isSelected ? MirrorStyle.accent : MirrorStyle.hairline, lineWidth: isSelected ? 1.5 : 1) }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).disabled(store.busy)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("pro-plan-\(product.id)")
    }

    private func planPrice(_ product: Product) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
        return layout {
            Text(product.displayPrice).font(.title2.weight(.bold))
                .lineLimit(1).minimumScaleFactor(0.65)
            Text(L10n.tr(product.id == ProProduct.weekly.rawValue ? "/ hafta" : "/ yıl"))
                .font(.caption).foregroundStyle(MirrorStyle.secondary)
        }.fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
    }

    @ViewBuilder
    private func planTrial(_ product: Product) -> some View {
        if let days = store.freeTrialDays(product) {
            Text(String(format: L10n.tr("%d gün ücretsiz"), days))
                .font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func trialTimeline(_ product: Product, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            timelineStep(L10n.tr("Bugün"), body: L10n.tr("Denemen ücretsiz başlar. Tüm Pro özellikleri açılır."), symbol: "lock.open")
            if days > 2 {
                timelineStep(days == 3 ? L10n.tr("1 gün sonra · Hatırlatma") : String(format: L10n.tr("%d gün sonra · Hatırlatma"), days - 2),
                             body: reminderText, symbol: "bell")
            }
            timelineStep(String(format: L10n.tr("%d gün sonra · İlk ödeme"), days),
                         body: String(format: L10n.tr("İptal etmezsen %@ ödemesi başlar."), store.billingRate(product)), symbol: "calendar")
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(MirrorStyle.hairline).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro-trial-timeline")
    }

    private func timelineStep(_ title: String, body: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol).font(.caption).foregroundStyle(MirrorStyle.accent)
                .frame(width: 28, height: 28)
                .background(MirrorStyle.accent.opacity(0.1), in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(MirrorStyle.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reminderText: String {
        if !reminders.enabled { return L10n.tr("Deneme hatırlatması kapalı.") }
        if reminders.authorization == .denied { return L10n.tr("Hatırlatma almak için Ayarlar’dan bildirimleri açabilirsin.") }
        if NotificationStore.allowsNotifications(reminders.authorization) {
            return L10n.tr("Denemen bitmeden 2 gün önce bildirimle hatırlatırız.")
        }
        return L10n.tr("Bildirimlere izin verirsen denemen bitmeden 2 gün önce hatırlatırız.")
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
        if !store.verifiedPro, let selected {
            VStack(spacing: 8) {
                Text(trialDays.map { String(format: L10n.tr("%d gün ücretsiz, sonra %@"), $0, store.billingRate(selected)) } ?? store.billingRate(selected))
                    .font(.footnote.weight(.medium)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("pro-billing-summary")
                Button { Task { await store.purchase(selected) } } label: {
                    HStack(spacing: 10) {
                        if store.busy { ProgressView().tint(MirrorStyle.background) }
                        Text(trialDays.map { String(format: L10n.tr("%d gün ücretsiz dene"), $0) } ?? L10n.tr("Abone ol"))
                        Image(systemName: "arrow.forward").accessibilityHidden(true)
                    }
                }
                .buttonStyle(MirivoButtonStyle(prominent: true)).disabled(!store.canPurchase(selected))
                .accessibilityIdentifier("pro-purchase")
                Text(L10n.tr("Otomatik yenilenir."))
                    .font(.caption).foregroundStyle(MirrorStyle.secondary)
                Text(L10n.tr(trialDays != nil
                    ? "Ücret ödememek için denemen bitmeden en az 24 saat önce App Store’dan iptal et."
                    : "App Store’dan istediğin zaman iptal edebilirsin."))
                    .font(.caption2).foregroundStyle(MirrorStyle.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button(L10n.tr("Satın alımları geri yükle")) { Task { await store.restore() } }
                .disabled(store.busy || store.refreshingMembership).frame(minHeight: 44).accessibilityIdentifier("pro-restore")
            if store.subscriptionActive {
                Link(L10n.tr("Aboneliği yönet"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    .frame(minHeight: 44)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { legalLinks }
                VStack(spacing: 4) { legalLinks }
            }
            if let customerID = store.membershipCustomerID {
                DisclosureGroup(L10n.tr("Üyelik desteği")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.tr("Üyelik kimliği")).foregroundStyle(MirrorStyle.secondary)
                        Text(customerID).font(.caption.monospaced()).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("pro-membership-id")
                        Button {
                            UIPasteboard.general.string = customerID
                            copiedMembershipID = true
                        } label: {
                            Label(L10n.tr(copiedMembershipID ? "Kimlik kopyalandı" : "Üyelik kimliğini kopyala"),
                                  systemImage: copiedMembershipID ? "checkmark" : "doc.on.doc")
                        }.accessibilityIdentifier("pro-copy-membership-id")
                        Button { Task { await store.refreshMembership() } } label: {
                            HStack {
                                if store.refreshingMembership { ProgressView() }
                                Text(L10n.tr("Üyelik durumunu yenile"))
                            }
                        }
                        .disabled(store.busy || store.refreshingMembership)
                        .accessibilityIdentifier("pro-refresh-membership")
                        Text(L10n.tr("Destek ekibi bu kimlikle üyelik durumunu kontrol edebilir."))
                            .font(.caption).foregroundStyle(MirrorStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }
                .padding(.top, 12)
                .accessibilityIdentifier("pro-membership-support")
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
