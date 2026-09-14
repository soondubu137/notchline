import Foundation

/// Readiness of a product's observation channel, never Turn state. Setup is optional.
nonisolated enum MonitoringSourceGate: Sendable {
    case open(IntegrationSetupStatus?)
    case closed(
        availability: MonitorAvailability,
        setupStatus: IntegrationSetupStatus?,
        diagnostic: String?
    )
}

protocol MonitoringLifecycleSource: Sendable {
    var repository: MonitoringRepository { get }
    func gate(productName: String) async -> MonitoringSourceGate
    func disconnect()
}
