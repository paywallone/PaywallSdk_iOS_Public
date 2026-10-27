import Foundation
import PaywallSDK

/// Shows `SdkResponse` values as JSON, as the web SDK prints them: tokens as they are, `raw` as JSON and empty
/// (`nil`) fields left out.
/// Built with `Mirror`, so every public field of the SDK result types appears without extra code.
enum SdkJSON {
    static func response<T>(_ response: SdkResponse<T>) -> PaywallJSON {
        let object: [String: PaywallJSON] = [
            "success": .bool(response.success),
            "status": .string(response.status.wireValue),
            "source": .string(response.source.wireValue),
            "message": response.message.map(PaywallJSON.string) ?? .null,
            "errorCode": response.errorCode.map(PaywallJSON.string) ?? .null,
            "actionType": response.actionType.map { .string($0.wireValue) } ?? .null,
            "data": response.data.map(value) ?? .null,
            "providerMeta": response.providerMeta.map(providerMeta) ?? .null,
            "actionHint": response.actionHint.map(PaywallJSON.string) ?? .null,
            "field": response.field.map(PaywallJSON.string) ?? .null,
            "nextActionHint": response.nextActionHint.map(PaywallJSON.string) ?? .null,
        ]
        return .object(object.filter { $0.value != .null })
    }

    /// `raw` is JSON text in the SDK; shown as JSON, as the web SDK returns it.
    private static func providerMeta(_ meta: ProviderMeta) -> PaywallJSON {
        var object: [String: PaywallJSON] = [:]
        if let httpStatus = meta.httpStatus { object["httpStatus"] = .number(String(httpStatus)) }
        if let responseCode = meta.responseCode { object["responseCode"] = .string(responseCode) }
        if let raw = meta.raw { object["raw"] = PaywallJSON.parse(raw) ?? .string(raw) }
        return .object(object)
    }

    /// Short summary of a response: success, status, actionType and message.
    static func normalized<T>(_ response: SdkResponse<T>) -> PaywallJSON {
        .object([
            "success": .bool(response.success || response.status == .success),
            "status": .string(response.status.wireValue),
            "actionType": response.actionType.map { .string($0.wireValue) } ?? .null,
            "message": response.message.map(PaywallJSON.string) ?? .null,
        ])
    }

    /// Keeps the first 6 and last 4 characters (the merchant's access token in request logs).
    static func maskToken(_ token: String?) -> PaywallJSON {
        guard let token else { return .null }
        return .string(token.count < 8 ? "***" : String(token.prefix(6)) + "..." + String(token.suffix(4)))
    }

    /// Reflects any SDK value into JSON; `nil` fields are left out.
    static func value(_ any: Any) -> PaywallJSON {
        switch any {
        case let json as PaywallJSON: return json
        case let meta as ProviderMeta: return providerMeta(meta)
        case let string as String: return .string(string)
        case let bool as Bool: return .bool(bool)
        case let int as Int: return .number(String(int))
        case let int as Int64: return .number(String(int))
        case let decimal as Decimal: return .number(NSDecimalNumber(decimal: decimal).stringValue)
        case let double as Double: return .number(String(double))
        case let status as SdkStatus: return .string(status.wireValue)
        case let source as SdkSource: return .string(source.wireValue)
        case let action as SdkActionType: return .string(action.wireValue)
        case let environment as PaywallEnvironment: return .string(environment.wireValue)
        case let dictionary as [String: PaywallJSON]: return .object(dictionary)
        default: break
        }
        let mirror = Mirror(reflecting: any)
        switch mirror.displayStyle {
        case .optional:
            return mirror.children.first.map { value($0.value) } ?? .null
        case .collection, .set:
            return .array(mirror.children.map { value($0.value) })
        case .struct, .class:
            var object: [String: PaywallJSON] = [:]
            for child in mirror.children {
                guard let label = child.label else { continue }
                let json = value(child.value)
                if json != .null { object[label] = json }
            }
            return .object(object)
        case .enum:
            return .string(String(describing: any))
        default:
            return .string(String(describing: any))
        }
    }
}
