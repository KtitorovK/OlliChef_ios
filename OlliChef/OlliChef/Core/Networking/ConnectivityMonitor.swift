import Network

/// Mirrors networkUtils.ts's checkInternetConnectivity: a one-shot check, lenient by
/// design — if the path can't be determined, assume connectivity rather than blocking
/// the user.
enum ConnectivityMonitor {
    static func hasInternetConnectivity() async -> Bool {
        let monitor = NWPathMonitor()
        return await withCheckedContinuation { continuation in
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "com.biteplanai.connectivity-check"))
        }
    }
}
