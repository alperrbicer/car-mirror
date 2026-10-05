import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @ObservedObject private var notifications = NotificationStore.shared
    @ObservedObject private var carReminder = CarConnectionReminderStore.shared

    var body: some View {
        Form {
            Section {
                Toggle(L10n.tr("Genel duyurular"), isOn: Binding(get: { notifications.enabled }, set: { value in
                    Task { await notifications.setEnabled(value) }
                }))
                .disabled(!notifications.configured)
                .accessibilityIdentifier("notifications-enabled")
                Text(L10n.tr(statusText)).foregroundStyle(MirrorStyle.secondary)
                    .accessibilityIdentifier("notifications-status")
                if notifications.authorization == .denied {
                    Button(L10n.tr("iOS Ayarlarını aç")) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                if [.failed, .removalPending, .permission].contains(notifications.status) {
                    Button(L10n.tr("Yeniden dene")) {
                        Task {
                            if notifications.enabled && notifications.authorization == .notDetermined { await notifications.setEnabled(true) }
                            else { await notifications.refresh() }
                        }
                    }
                }
            } footer: {
                Text(L10n.tr("Sürüm ve ürün duyuruları al. Medya içeriklerin ve kaynak adreslerin bildirim sunucusuna gönderilmez."))
            }
            .listRowBackground(MirrorStyle.surface)
            Section {
                Toggle(L10n.tr("Araç bağlantısında hatırlat"), isOn: Binding(get: { carReminder.enabled }, set: { value in
                    Task { await carReminder.setEnabled(value) }
                }))
                .accessibilityIdentifier("car-connection-reminder-enabled")
                if carReminder.enabled && carReminder.authorization == .denied {
                    Text(L10n.tr("Bildirim izni iOS Ayarları’ndan açılmalı."))
                        .foregroundStyle(MirrorStyle.secondary)
                    Button(L10n.tr("iOS Ayarlarını aç")) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } else if carReminder.enabled && !carReminder.requestingPermission &&
                            (carReminder.permissionFailed || carReminder.authorization == .notDetermined) {
                    Text(L10n.tr(carReminder.permissionFailed ? "Bildirim izni alınamadı. Yeniden dene." : "Bildirim izni bekleniyor."))
                        .foregroundStyle(MirrorStyle.secondary)
                    Button(L10n.tr("Yeniden dene")) { Task { await carReminder.setEnabled(true) } }
                }
            } footer: {
                Text(L10n.tr("Yeni bir CarPlay oturumu algılandığında telefonunda bir kez hatırlatır. Araç bağlantısı bilgisi sunucuya gönderilmez."))
            }
            .listRowBackground(MirrorStyle.surface)
        }
        .navigationTitle(L10n.tr("Bildirimler"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden).background(MirrorStyle.background)
        .task { await notifications.refresh(); await carReminder.refreshAuthorization() }
        .onAppear { FirebaseServices.recordScreen(.notifications) }
    }

    private var statusText: String {
        switch notifications.status {
        case .unavailable: "Bildirimler henüz kullanılamıyor."
        case .off: "Bildirimler kapalı."
        case .permission: "Bildirim izni bekleniyor."
        case .denied: "Bildirim izni iOS Ayarları’ndan açılmalı."
        case .registering, .syncing: "Bildirimler hazırlanıyor…"
        case .active: "Bildirimler açık."
        case .failed: "Bildirim kaydı tamamlanamadı. Yeniden dene."
        case .removalPending: "Kapatma sunucuya iletilemedi. Bağlantı kurulduğunda yeniden denenecek."
        }
    }
}
