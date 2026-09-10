import Network
import Foundation

/// Mirrors networkUtils.ts's checkInternetConnectivity: lenient by design — if the
/// path can't be determined, assume connectivity rather than blocking the user.
actor ConnectivityMonitor {
    static let shared = ConnectivityMonitor()

    private let monitor = NWPathMonitor()
    private var isConnected = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.update(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "com.biteplanai.connectivity-monitor"))
    }

    private func update(_ connected: Bool) {
        isConnected = connected
    }

    func hasInternetConnectivity() -> Bool {
        isConnected
    }
}
