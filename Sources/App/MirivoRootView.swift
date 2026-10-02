import SwiftUI

struct MirivoRootView: View {
    @ObservedObject var model: MirrorModel
    @AppStorage("language", store: SharedPreferences.defaults) private var language = "system"
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            MirrorHomeView(model: model)
                .tabItem { Label(L10n.tr("Yansıt"), systemImage: "rectangle.on.rectangle") }.tag(0)
            NavigationStack { LibraryView() }
                .tabItem { Label(L10n.tr("Kaynaklar"), systemImage: "play.rectangle.on.rectangle") }.tag(1)
            MirrorSettingsView(model: model, isTab: true)
                .tabItem { Label(L10n.tr("Ayarlar"), systemImage: "slider.horizontal.3") }.tag(2)
        }
        .environment(\.locale, Locale(identifier: L10n.language))
        .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
        .id(language)
        .tint(MirrorStyle.accent)
    }
}
