import Foundation

// MARK: - Core Domain Models

/// Represents a feature flag for a specific wholesaler.
/// Lenient decoding: any unknown future fields from the server are safely ignored.
struct FeatureFlag: Codable, Identifiable, Equatable {
    let key: String
    let label: String
    let description: String
    let parent_key: String?
    let default_enabled: Bool
    let enforcement_mode: String // "off", "log", "enforce"
    let locked_message: String?
    let override_enabled: Bool?
    let effective_enabled: Bool
    let reason: String?
    let updated_by: String?
    let updated_at: String?
    let version: Int
    let parent_locked: Bool

    var id: String { key }

    var isCustom: Bool {
        override_enabled != nil
    }

    var isEnforced: Bool {
        enforcement_mode == "enforce"
    }

    var isNotEnforcedYet: Bool {
        enforcement_mode != "enforce"
    }
}

/// Represents an item in the global feature catalog.
struct FeatureCatalogItem: Codable, Identifiable, Equatable {
    let key: String
    let label: String
    let description: String
    let parent_key: String?
    let default_enabled: Bool
    let enforcement_mode: String
    let locked_message: String?
    let updated_at: String?

    var id: String { key }
}

/// Dynamic JSON value decoder for audit row values (`old_value`, `new_value`).
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else if let arr = try? container.decode([AnyCodableValue].self) {
            self = .array(arr)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .dictionary(let d): try container.encode(d)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    subscript(key: String) -> AnyCodableValue? {
        if case .dictionary(let dict) = self {
            return dict[key]
        }
        return nil
    }
}

/// Represents an entry in the feature flag audit trail.
struct FeatureAuditRow: Codable, Identifiable, Equatable {
    let id: String
    let wholesaler_user_id: String?
    let feature_key: String
    let action: String // "set", "reset", "catalog_default", "catalog_mode"
    let old_value: AnyCodableValue?
    let new_value: AnyCodableValue?
    let reason: String?
    let actor: String?
    let created_at: String?
}

/// Page of audit logs returned by the `audit` action.
struct FeatureAuditPage: Codable, Equatable {
    let ok: Bool
    let rows: [FeatureAuditRow]
    let count: Int?
    let page: Int?
    let pageSize: Int?
}

// MARK: - Server Response Payloads

struct FeatureListResponse: Codable {
    let ok: Bool
    let features: [FeatureFlag]?
    let error: String?
    let message: String?
}

struct FeatureSetResponse: Codable {
    let ok: Bool
    let version: Int?
    let error: String?
    let message: String?
}

struct FeatureCatalogListResponse: Codable {
    let ok: Bool
    let catalog: [FeatureCatalogItem]?
    let error: String?
    let message: String?
}

struct FeatureCatalogSetResponse: Codable {
    let ok: Bool
    let error: String?
    let message: String?
}

// MARK: - Outgoing Request Bodies

struct FeatureListRequest: Encodable {
    let action = "list"
    let wholesaler_id: String
}

struct FeatureSetRequest: Encodable {
    let action = "set"
    let wholesaler_id: String
    let feature_key: String
    let enabled: Bool
    let reason: String
    let expected_version: Int?
}

struct FeatureResetRequest: Encodable {
    let action = "reset"
    let wholesaler_id: String
    let feature_key: String
    let reason: String
    let expected_version: Int?
}

struct FeatureAuditRequest: Encodable {
    let action = "audit"
    let wholesaler_id: String?
    let page: Int
    let pageSize: Int
}

struct FeatureCatalogListRequest: Encodable {
    let action = "catalog_list"
}

struct FeatureCatalogSetRequest: Encodable {
    let action = "catalog_set"
    let feature_key: String
    let default_enabled: Bool?
    let enforcement_mode: String?
    let reason: String
}

// MARK: - Pure Helpers

enum FeatureValidationError: LocalizedError, Equatable {
    case empty
    case tooLong(Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Please provide a reason between 1 and 500 characters."
        case .tooLong(let length):
            return "Reason is too long (\(length) characters). Maximum is 500 characters."
        }
    }
}

enum FeatureValidation {
    /// Validates reason according to the backend contract (1-500 trimmed characters).
    static func validateReason(_ raw: String) -> Result<String, FeatureValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failure(.empty)
        }
        if trimmed.count > 500 {
            return .failure(.tooLong(trimmed.count))
        }
        return .success(trimmed)
    }
}

enum FeatureDateFormatter {
    private static let isoFormatterWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone(secondsFromGMT: 19800)!
        f.locale = Locale(identifier: "en_IN")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func parseISO8601(_ string: String) -> Date? {
        if let d = isoFormatterWithFraction.date(from: string) { return d }
        return isoFormatterStandard.date(from: string)
    }

    /// Formats an ISO8601 string to Asia/Kolkata (IST) display, matching the web admin panel.
    static func indiaTimeString(from isoString: String?) -> String {
        guard let isoString = isoString, !isoString.isEmpty,
              let date = parseISO8601(isoString) else {
            return "—"
        }
        return "\(displayFormatter.string(from: date)) IST"
    }
}

enum FeatureErrorMapper {
    /// Maps error code/status to clear, feature-specific admin messaging.
    static func map(code: String?, status: Int?, fallbackMessage: String) -> String {
        if let code = code {
            switch code {
            case "VERSION_CONFLICT":
                return "Another admin changed this. Refreshed — please try again."
            case "NOT_A_WHOLESALER":
                return "Wholesaler not found."
            case "RATE_LIMITED":
                return "Too many requests. Please retry in a moment."
            case "INVALID_REASON":
                return "Reason must be 1–500 characters."
            case "FEATURE_ADMIN_UNAVAILABLE":
                return "Feature controls service is temporarily unavailable."
            case "Unauthorized":
                return "Admin authorization failed. Please check credentials."
            default:
                break
            }
        }
        if status == 401 {
            return "Admin authorization failed. Please check credentials."
        }
        return fallbackMessage
    }

    /// Maps any Error (including AdminAPIError) to user-friendly messaging without altering AdminAPI.mapError.
    static func map(_ error: Error) -> String {
        let mirror = Mirror(reflecting: error)
        var code: String? = nil
        var status: Int? = nil
        var message: String = error.localizedDescription

        for child in mirror.children {
            if child.label == "code", let c = child.value as? String? {
                code = c
            } else if child.label == "status", let s = child.value as? Int? {
                status = s
            } else if child.label == "message", let m = child.value as? String {
                message = m
            }
        }
        return map(code: code, status: status, fallbackMessage: message)
    }
}
