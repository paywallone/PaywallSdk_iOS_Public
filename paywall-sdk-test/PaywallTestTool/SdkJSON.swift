import Foundation
import PaywallSDK

/// Shows `SdkResponse` values as JSON.
/// Built with `Mirror`, so every public field of the SDK result types appears without extra code.
enum SdkJSON {
    private static let tokenKeys: Set<String> = ["token", "masterpassToken", "accessToken", "Token", "MasterpassToken"]

    static func response<T>(_ response: SdkResponse<T>) -> PaywallJSON {
        let object: [String: PaywallJSON] = [
            "success": .bool(response.success),
            "status": .string(response.status.wireValue),
            "source": .string(response.source.wireValue),
            "message": response.message.map(PaywallJSON.string) ?? .null,
            "errorCode": response.errorCode.map(PaywallJSON.string) ?? .null,
            "actionType": response.actionType.map { .string($0.wireValue) } ?? .null,
            "data": response.data.map(value) ?? .null,
            "providerMeta": response.providerMeta.map(value) ?? .null,
            "actionHint": response.actionHint.map(PaywallJSON.string) ?? .null,
            "field": response.field.map(PaywallJSON.string) ?? .null,
            "nextActionHint": response.nextActionHint.map(PaywallJSON.string) ?? .null,
        ]
        return masked(.object(object))
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

    static func maskToken(_ token: String?) -> PaywallJSON {
        guard let token else { return .null }
        return .string(token.count < 8 ? "***" : String(token.prefix(6)) + "..." + String(token.suffix(4)))
    }

    /// Reflects any SDK value into JSON.
    static func value(_ any: Any) -> PaywallJSON {
        switch any {
        case let json as PaywallJSON: return json
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
                object[label] = value(child.value)
            }
            return .object(object)
        case .enum:
            return .string(String(describing: any))
        default:
            return .string(String(describing: any))
        }
    }

    private static func masked(_ json: PaywallJSON) -> PaywallJSON {
        switch json {
        case let .object(object):
            var result: [String: PaywallJSON] = [:]
            for (key, value) in object {
                if tokenKeys.contains(key), let text = value.stringValue {
                    result[key] = maskToken(text)
                } else {
                    result[key] = masked(value)
                }
            }
            return .object(result)
        case let .array(values):
            return .array(values.map(masked))
        default:
            return json
        }
    }
}
