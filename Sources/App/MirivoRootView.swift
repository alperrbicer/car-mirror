import SwiftUI

struct MirivoRootView: View {
    @ObservedObject var model: MirrorModel
    @AppStorage("language", store: SharedPreferences.defaults) private var language = "system"
    @SceneStorage("mirivo.root.selectedPage") private var selectedPage = 0
    @State private var showingSettings = false
    @State private var showingPlayer = false
    @ObservedObject private var notifications = NotificationStore.shared
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
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    MirrorStyle.background
                        .frame(height: geometry.safeAreaInsets.top)
                        .offset(y: -geometry.safeAreaInsets.top)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .toolbar(.hidden, for: .navigationBar)
            .id(language)
            .safeAreaInset(edge: .bottom) { NowPlayingBar(hidesSavedProgress: selectedPage == 1) { showingPlayer = true } }
            .navigationDestination(isPresented: $showingPlayer) { MediaPlayerScreen(model: model) }
        }
        .fullScreenCover(isPresented: $model.presentingPlayer) {
            NavigationStack { MediaPlayerScreen(model: model) }
        }
        .sheet(isPresented: $showingSettings) { MirrorSettingsView(model: model) }
        .onAppear { FirebaseServices.recordScreen(selectedPage == 0 ? .home : .library) }
        .onChange(of: selectedPage) { _, page in FirebaseServices.recordScreen(page == 0 ? .home : .library) }
        .onChange(of: notifications.pendingNavigation, initial: true) { _, navigation in
            guard let navigation else { return }
            showingPlayer = false
            model.presentingPlayer = false
            selectedPage = navigation.route == .library ? 1 : 0
            showingSettings = navigation.route == .settings
            notifications.consumedNavigation()
        }
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
            TVRouteStatusButton(model: model)
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.65)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                    .background {
                        Circle().fill(LinearGradient(colors: [MirrorStyle.raised, MirrorStyle.surface],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.03)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(MirivoPressButtonStyle())
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
