import Foundation

/// Readiness of a product's actual observation channel, never Turn state.
/// Setup is optional: an already-connected SDK source has nothing to install.
nonisolated enum MonitoringSourceGate: Sendable {
    case open(IntegrationSetupStatus?)
    case closed(
        availability: MonitorAvailability,
        setupStatus: IntegrationSetupStatus?,
        diagnostic: String
    )
}

protocol MonitoringLifecycleSource: Sendable {
    var repository: MonitoringRepository { get }
    func gate(productName: String) async -> MonitoringSourceGate
    func disconnect()
}
