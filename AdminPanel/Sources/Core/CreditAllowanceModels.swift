import Foundation

struct CreditAllowanceItem: Decodable, Identifiable {
    let wholesaler_id: String // Shared API's business ID key, including retailers.
    let verification_status: String
    let daily_allowance: Int
    let is_custom: Bool
    let policy_version: Int
    let current_allowance: Int?
    let next_refill_at: String?
    let admin_available: Int?
    let recurring_available: Int
    let gift_available: Int
    let paid_available: Int
    let available: Int
    var id: String { wholesaler_id }
}
struct CreditAllowancePage: Decodable {
    let ok: Bool
    let items: [CreditAllowanceItem]
    let server_now: String
    let program_active: Bool
    let default_allowance: Int
}
struct CreditAllowanceChange: Encodable, Equatable {
    let action: String
    let business_type: String
    let wholesaler_id: String
    let daily_allowance: Int?
    let reason: String
    let expected_version: Int
    let request_key: String
    let credits: Int?

    static func make(entity: ReviewEntity, id: String, amount: String, reason: String,
                     version: Int, reset: Bool, requestKey: String = UUID().uuidString) throws -> Self {
        let note = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, note.utf16.count <= 500 else {
            throw CreditInputError.invalid("Enter a reason of 1–500 characters.")
        }
        let parsed = Int(amount.trimmingCharacters(in: .whitespacesAndNewlines))
        guard reset || (parsed != nil && (0...100_000).contains(parsed!)) else {
            throw CreditInputError.invalid("Enter a whole number between 0 and 100,000.")
        }
        return Self(action: reset ? "reset_default" : "set_allowance", business_type: entity.rawValue,
                    wholesaler_id: id, daily_allowance: reset ? nil : parsed, reason: note,
                    expected_version: version, request_key: requestKey, credits: nil)
    }
    static func grant(entity: ReviewEntity, id: String, amount: String, reason: String) throws -> Self {
        let validated = try make(entity: entity, id: id, amount: amount, reason: reason, version: 0, reset: false)
        guard let units = validated.daily_allowance, units > 0 else { throw CreditInputError.invalid("Enter a whole number between 1 and 100,000.") }
        return Self(action: "grant_now", business_type: entity.rawValue, wholesaler_id: id, daily_allowance: nil,
            reason: validated.reason, expected_version: 0, request_key: validated.request_key, credits: units)
    }

}
enum CreditInputError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
struct CreditAllowanceSaved: Decodable {
    let ok: Bool
    let next_allowance: Int
    let program_active: Bool
    let effective_at: String?
    let replayed: Bool?
}

// Countdown follows the server clock plus elapsed uptime, not the device's wall clock.
struct AdminRefillClock {
    let serverDate: Date
    let sampledUptime: TimeInterval
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
    func remaining(until deadline: String?, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval? {
        guard let end = Self.date(deadline) else { return nil }
        return max(0, end.timeIntervalSince(serverDate) - max(0, uptime - sampledUptime))
    }
}

struct ImmediateCreditSaved: Decodable {
    let ok: Bool
    let granted: Int
    let available: Int
    let replayed: Bool
}
