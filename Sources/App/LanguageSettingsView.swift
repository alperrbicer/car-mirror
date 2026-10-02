import SwiftUI

struct LanguageSettingsView: View {
    @AppStorage("language", store: SharedPreferences.defaults) private var selection = "system"
    @State private var query = ""
    private var locale: Locale { Locale(identifier: L10n.language) }
    private var recommended: [AppLanguage] {
        let system = AppLanguage.resolve(selection: "system", preferredLanguages: Locale.preferredLanguages)
        return AppLanguage.allCases.filter { $0 == system || $0 == .tr || $0 == .en }
    }
    private var results: [AppLanguage] { AppLanguage.allCases.filter { $0.matches(query, displayLocale: locale) } }
    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    row(id: "system", title: L10n.tr("Sistemi izle"), subtitle: AppLanguage.resolve(selection: "system", preferredLanguages: Locale.preferredLanguages).nativeName)
                }
                Section(L10n.tr("Önerilen")) {
                    ForEach(recommended) { language in languageRow(language) }
                }
            }
            Section(L10n.tr("Tüm diller")) {
                ForEach(results) { language in languageRow(language) }
            }
            if results.isEmpty {
                ContentUnavailableView(L10n.tr("Dil bulunamadı"), systemImage: "magnifyingglass",
                    description: Text(L10n.tr("Başka bir ad veya dil kodu dene.")))
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.tr("Dil bul"))
        .scrollContentBackground(.hidden).background(MirrorStyle.background)
        .navigationTitle(L10n.tr("Dil")).navigationBarTitleDisplayMode(.inline)
    }
    private func languageRow(_ language: AppLanguage) -> some View {
        row(id: language.rawValue, title: language.nativeName,
            subtitle: locale.localizedString(forIdentifier: language.rawValue))
    }
    private func row(id: String, title: String, subtitle: String?) -> some View {
        Button { selection = id } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    if let subtitle, subtitle.localizedCaseInsensitiveCompare(title) != .orderedSame {
                        Text(subtitle).font(.caption).foregroundStyle(MirrorStyle.secondary)
                    }
                }
                Spacer(minLength: 0)
                if selection == id { Image(systemName: "checkmark").foregroundStyle(MirrorStyle.accent) }
            }.frame(minHeight: MirrorStyle.controlHeight).padding(.vertical, 5).contentShape(Rectangle())
        }
        .accessibilityIdentifier("language-\(id)")
        .accessibilityAddTraits(selection == id ? [.isSelected] : [])
        .listRowBackground(MirrorStyle.surface)
    }
}
