import Foundation
import PaywallSDK

/// Collects the SDK's HTTP traffic for the "Ağ" tab (`PaywallSdk.setNetworkListener`, debug builds only).
///
/// For Masterpass calls the SDK also attaches the lines Masterpass writes to its own log channel during each call
/// (`vendorLogs`, tokens masked).
final class NetworkCapture: ObservableObject, PaywallNetworkListener, @unchecked Sendable {
    @Published private(set) var events: [PaywallNetworkEvent] = []

    func onNetworkEvent(_ event: PaywallNetworkEvent) {
        DispatchQueue.main.async { self.events.insert(event, at: 0) }
    }

    func clear() { events = [] }

    static func prettyJSON(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "(boş)" }
        return PaywallJSON.parse(text)?.jsonString(pretty: true) ?? text
    }

    static func describe(_ event: PaywallNetworkEvent) -> String {
        var lines = [
            "\(event.method) \(event.url)",
            "Kaynak: \(event.source == .paywall ? "Paywall" : "Masterpass") · \(event.statusCode.map(String.init) ?? "HATA") · \(event.durationMs) ms",
            "",
            "Request headers:",
            event.requestHeaders.isEmpty ? "(boş)" : event.requestHeaders.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"),
            "",
            "Request:",
            prettyJSON(event.requestBody),
            "",
            "Response:",
            event.error ?? prettyJSON(event.responseBody),
        ]
        if !event.vendorLogs.isEmpty {
            lines += ["", "Masterpass logları:"] + event.vendorLogs
        }
        return lines.joined(separator: "\n")
    }
}
