import SwiftUI

struct MirivoRootView: View {
    @ObservedObject var model: MirrorModel
    var onInitialContentReady: (() -> Void)?
    var replayOnboarding: () -> Void = {}
    @State private var requestedOnboarding = false
    @AppStorage("language", store: SharedPreferences.defaults) private var language = "system"
    @AppStorage(LibraryStartup.lastSourceKey) private var lastOpenedSourceID = ""
    @SceneStorage("mirivo.root.selectedPage") private var selectedPage = 0
    @State private var sourcePath: [UUID]
    @State private var appliedInitialPage: Bool
    @State private var showingSettings = false
    @State private var showingPlayer = false
    @ObservedObject private var library = SourceLibrary.shared
    @ObservedObject private var notifications = NotificationStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: MirrorModel, onInitialContentReady: (() -> Void)? = nil, replayOnboarding: @escaping () -> Void = {}) {
        self.model = model
        self.onInitialContentReady = onInitialContentReady
        self.replayOnboarding = replayOnboarding
        // Seed the stack before its first presentation. Foregrounding and going
        // back must never repeat the launch redirect.
        let canRestoreSource = NotificationStore.shared.pendingNavigation == nil &&
            !model.presentingPlayer && !model.playback.hasActivePlayback
        let remembered = UserDefaults.standard.string(forKey: LibraryStartup.lastSourceKey).flatMap(UUID.init(uuidString:))
        let sourceID = canRestoreSource ? LibraryStartup.sourceID(
            in: SourceLibrary.shared.sources.map(\.id), lastOpened: remembered,
            lastPlayed: remembered == nil ? LastPlaybackStore.shared.record?.sourceID : nil) : nil
        _sourcePath = State(initialValue: sourceID.map { [$0] } ?? [])
        _appliedInitialPage = State(initialValue: !canRestoreSource)
    }

    var body: some View {
        NavigationStack(path: $sourcePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    pageNavigation
                    if selectedPage == 0 {
                        MirrorHomeView(model: model)
                    } else {
                        LibraryView { showingPlayer = true }
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
            .safeAreaInset(edge: .bottom) { NowPlayingBar(model: model) { showingPlayer = true } }
            .navigationDestination(for: UUID.self) { sourceID in
                if let source = library.sources.first(where: { $0.id == sourceID }) {
                    ChannelListView(source: source, onInitialContentReady: onInitialContentReady,
                                    onOpenSettings: { showingSettings = true }) { selectedID in
                        guard selectedID != sourceID, library.sources.contains(where: { $0.id == selectedID }) else { return }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { sourcePath = [selectedID] }
                    }
                    .id(source.id)
                }
            }
            .navigationDestination(isPresented: $showingPlayer) { MediaPlayerScreen(model: model) }
        }
        .modifier(MembershipOfferPresenter(model: model))
        .modifier(ReviewPromptPresenter(model: model, playback: model.playback,
            rootAvailable: selectedPage == 0 && sourcePath.isEmpty && !showingSettings && !showingPlayer))
        .fullScreenCover(isPresented: $model.presentingPlayer) {
            NavigationStack { MediaPlayerScreen(model: model) }
                .modifier(MembershipOfferPresenter(model: model, restoredPlayer: true))
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            if requestedOnboarding { requestedOnboarding = false; replayOnboarding() }
        }) {
            MirrorSettingsView(model: model) { requestedOnboarding = true }
        }
        .onAppear {
            if !appliedInitialPage {
                appliedInitialPage = true
                if notifications.pendingNavigation == nil, !library.sources.isEmpty {
                    selectedPage = 1
                }
            }
            FirebaseServices.recordScreen(selectedPage == 0 ? .home : .library)
        }
        .onChange(of: sourcePath, initial: true) { _, path in
            guard let sourceID = path.first else {
                onInitialContentReady?()
                return
            }
            selectedPage = 1
            lastOpenedSourceID = sourceID.uuidString
        }
        .onChange(of: library.sources.map(\.id)) { _, sourceIDs in
            if let sourceID = sourcePath.first, !sourceIDs.contains(sourceID) {
                sourcePath.removeAll()
            }
        }
        .onChange(of: selectedPage) { _, page in FirebaseServices.recordScreen(page == 0 ? .home : .library) }
        .onChange(of: model.requestingLibrary) { _, requested in
            guard requested else { return }
            model.requestingLibrary = false
            appliedInitialPage = true
            showingPlayer = false
            model.presentingPlayer = false
            selectedPage = 1
        }
        .onChange(of: notifications.pendingNavigation, initial: true) { _, navigation in
            guard let navigation else { return }
            appliedInitialPage = true
            sourcePath.removeAll()
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
            MirivoSettingsButton { showingSettings = true }
        }
    }

    private var pageNavigation: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            pageButton(0, title: L10n.tr("Ekranlar"), symbol: "tv")
            pageButton(1, title: L10n.tr("Kaynaklar"), symbol: "play.rectangle.on.rectangle")
        }
        .padding(4).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func pageButton(_ page: Int, title: String, symbol: String) -> some View {
        Button { selectedPage = page } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 10).padding(.vertical, 2)
                .foregroundStyle(selectedPage == page ? .white : MirrorStyle.secondary)
                .background(selectedPage == page ? MirrorStyle.raised : .clear, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(page == 0 ? "page-mirror" : "page-library")
        .accessibilityAddTraits(selectedPage == page ? [.isSelected] : [])
    }
}

struct MirivoSettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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

private enum LibraryStartup {
    static let lastSourceKey = "mirivo.library.lastOpenedSourceID"

    static func sourceID(in sourceIDs: [UUID], lastOpened: UUID?, lastPlayed: UUID?) -> UUID? {
        if let lastOpened, sourceIDs.contains(lastOpened) { return lastOpened }
        if sourceIDs.count == 1 { return sourceIDs.first }
        // Playback history is only a migration fallback for existing users.
        // Once a source has been opened, a deleted selection returns to the list.
        if lastOpened == nil, let lastPlayed, sourceIDs.contains(lastPlayed) { return lastPlayed }
        return nil
    }
}
