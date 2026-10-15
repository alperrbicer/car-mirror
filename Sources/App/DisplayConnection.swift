import Foundation

enum ConnectedDisplayRoute: String, Identifiable {
    case cast, carPlay, airPlay, externalDisplay

    var id: Self { self }
    var symbol: String {
        switch self {
        case .cast: return "tv.fill"
        case .carPlay: return "car.side"
        case .airPlay: return "airplayvideo"
        case .externalDisplay: return "display"
        }
    }

    @MainActor
    static func connected(to model: MirrorModel) -> [Self] { model.playback.displayConnection.routes }

    static func resolve(cast: Bool, carPlay: Bool, externalDisplay: Bool,
                        externalPlayback: Bool, airPlayAudio: Bool) -> [Self] {
        var routes: [Self] = []
        if cast { routes.append(.cast) }
        // CarPlay video can also report external playback; a generic display
        // can be wired. Neither alone establishes an AirPlay connection.
        if airPlayAudio { routes.append(.airPlay) }
        else if externalDisplay { routes.append(.externalDisplay) }
        else if externalPlayback && !carPlay && !cast { routes.append(.airPlay) }
        if carPlay { routes.append(.carPlay) }
        return routes
    }
}

/// All connection labels describe the same destination, including when media
/// is paused/stopped or more than one accessory remains connected.
struct DisplayConnection: Equatable {
    let routes: [ConnectedDisplayRoute]
    var castName: String?
    var airPlayName: String?

    var primaryRoute: ConnectedDisplayRoute? { routes.first }
    var isConnected: Bool { !routes.isEmpty }
    var symbol: String { primaryRoute?.symbol ?? "display" }
    var title: String {
        if routes.count > 1 { return L10n.tr("Ekran bağlantıları") }
        switch primaryRoute {
        case .cast: return L10n.tr("TV bağlantısı")
        case .carPlay: return "CarPlay"
        case .airPlay: return "AirPlay"
        case .externalDisplay: return L10n.tr("Harici ekran")
        case nil: return L10n.tr("Ekran bağlantısı")
        }
    }
    var destinationName: String { primaryRoute.map(destinationName(for:)) ?? title }
    var actionTitle: String {
        guard isConnected else { return L10n.tr("Ekrana bağlan") }
        if routes.count > 1 { return title }
        return primaryRoute == .carPlay ? L10n.tr("CarPlay bağlı") : destinationName
    }
    var connectedSummary: String {
        routes.map { route in
            route == .carPlay ? L10n.tr("CarPlay bağlı") : String(format: L10n.tr("Bağlı: %@"), destinationName(for: route))
        }.joined(separator: " · ")
    }

    func destinationName(for route: ConnectedDisplayRoute) -> String {
        switch route {
        case .cast: return castName ?? "Google Cast"
        case .carPlay: return "CarPlay"
        case .airPlay: return airPlayName ?? "AirPlay"
        case .externalDisplay: return L10n.tr("Harici ekran")
        }
    }

    func playbackStatus(_ state: PlaybackController.State, for route: ConnectedDisplayRoute? = nil) -> String {
        let destination = route ?? primaryRoute
        if let route, route != primaryRoute { return L10n.tr(route == .carPlay ? "CarPlay bağlı" : "Bağlı") }
        switch state {
        case .loading: return L10n.tr("Görüntü bağlanıyor")
        case .paused: return L10n.tr("Yayın duraklatıldı")
        case .failed: return L10n.tr("Yayın tamamlanamadı")
        case .idle: return L10n.tr(destination == .carPlay ? "CarPlay bağlı" : "Bağlı")
        case .playing:
            switch destination {
            case .cast: return L10n.tr("TV’de oynatılıyor")
            case .carPlay: return L10n.tr("Araç ekranında oynatılıyor")
            case .airPlay: return L10n.tr("AirPlay ile oynatılıyor")
            case .externalDisplay: return L10n.tr("Harici ekranda oynatılıyor")
            case nil: return L10n.tr("Şimdi oynatılıyor")
            }
        }
    }

    var failureMessage: String {
        switch primaryRoute {
        case .cast: return L10n.tr("TV bağlantısı kurulamadı. TV’yi ve Wi-Fi bağlantısını kontrol edip yeniden dene.")
        case .carPlay, .airPlay, .externalDisplay:
            return String(format: L10n.tr("%@ bağlantısı kurulamadı. Bağlantını kontrol edip yeniden dene."), destinationName)
        case nil: return L10n.tr("Görüntü başlatılamadı. Yeniden deneyebilirsin.")
        }
    }
}
