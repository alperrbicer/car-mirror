import Foundation
import Combine
@preconcurrency import GoogleCast

@MainActor
enum CastServices {
    static let context: GCKCastContext = {
        let options = GCKCastOptions(discoveryCriteria: GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID))
        options.disableDiscoveryAutostart = true
        options.startDiscoveryAfterFirstTapOnCastButton = false
        options.disableAnalyticsLogging = true
        options.stopReceiverApplicationWhenEndingSession = true
        GCKCastContext.setSharedInstanceWith(options)
        return GCKCastContext.sharedInstance()
    }()
}

/// Discovery runs only while the user has the TV picker open.
@MainActor
final class TVDiscovery: NSObject, ObservableObject, @preconcurrency GCKDiscoveryManagerListener {
    struct Device: Identifiable {
        let device: GCKDevice
        var id: String { device.uniqueID }
        var name: String { device.friendlyName ?? device.modelName ?? "Google Cast" }
    }
    @Published private(set) var devices: [Device] = []
    @Published private(set) var searching = false
    @Published private(set) var unavailable = false
    private var observing = false

    func start() {
        stop()
        let manager = CastServices.context.discoveryManager
        manager.add(self)
        observing = true
        unavailable = false
        searching = true
        manager.startDiscovery()
        refreshDevices()
    }

    func stop() {
        if observing {
            let manager = CastServices.context.discoveryManager
            manager.remove(self)
            manager.stopDiscovery()
        }
        observing = false
        searching = false
    }

    func didUpdateDeviceList() { refreshDevices() }
    private func refreshDevices() {
        guard observing else { return }
        let manager = CastServices.context.discoveryManager
        devices = (0..<manager.deviceCount).map { manager.device(at: $0) }
            .filter { $0.hasCapabilities(.videoOut) }.map(Device.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        searching = devices.isEmpty
    }
}
