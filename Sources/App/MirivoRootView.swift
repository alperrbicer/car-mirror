import SwiftUI

struct MirivoRootView: View {
    @ObservedObject var model: MirrorModel
    @AppStorage("language", store: SharedPreferences.defaults) private var language = "system"
    @State private var selectedPage = 0
    @State private var showingSettings = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    pageNavigation
                    if selectedPage == 0 {
                        MirrorHomeView(model: model)
                    } else {
                        LibraryView()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(MirrorStyle.background)
            .toolbar(.hidden, for: .navigationBar)
            .id(language)
        }
        .sheet(isPresented: $showingSettings) { MirrorSettingsView(model: model) }
        .environment(\.locale, Locale(identifier: L10n.language))
        .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
        .environment(\.defaultMinListRowHeight, MirrorStyle.controlHeight)
        .tint(MirrorStyle.accent)
    }

    private var header: some View {
        HStack(spacing: 12) {
            MirrorMark().frame(width: 42, height: 42)
            Text(BrandIdentity.name)
                .font(.system(.title, design: .default, weight: .semibold))
                .tracking(-1.1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 54, height: 54)
                    .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(MirrorStyle.hairline) }
                    .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Ayarlar"))
            .accessibilityIdentifier("open-settings")
        }
    }

    private var pageNavigation: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 24))
        return layout {
            pageButton(0, title: L10n.tr("Yansıt"), symbol: "rectangle.on.rectangle")
            pageButton(1, title: L10n.tr("Kaynaklar"), symbol: "play.rectangle.on.rectangle")
        }
    }

    private func pageButton(_ page: Int, title: String, symbol: String) -> some View {
        Button { selectedPage = page } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                    }
                    Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: MirrorStyle.controlHeight, alignment: .leading)
                .padding(.vertical, 3)
                Capsule().fill(selectedPage == page ? MirrorStyle.accent : MirrorStyle.hairline).frame(height: 2)
            }
            .foregroundStyle(selectedPage == page ? .white : MirrorStyle.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(page == 0 ? "page-mirror" : "page-library")
        .accessibilityAddTraits(selectedPage == page ? [.isSelected] : [])
    }
}
