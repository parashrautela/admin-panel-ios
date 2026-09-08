import Foundation

enum ReviewEntity: String, Codable, CaseIterable, Hashable, Identifiable {
    case wholesaler, retailer
    var id: String { rawValue }
    var table: String { rawValue + "s" }
    var label: String { rawValue.capitalized }
}
enum WholesalerStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case pending, on_hold, verified, resubmission_required, rejected, banned, unknown
    var id: String { rawValue }
    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
    var label: String {
        switch self {
        case .pending: return "Pending"
        case .on_hold: return "On hold"
        case .verified: return "Verified"
        case .resubmission_required: return "Resubmission"
        case .rejected: return "Rejected"
        case .banned: return "Banned"
        case .unknown: return "Unknown status"
        }
    }
    var symbol: String {
        switch self {
        case .pending: return "clock"
        case .on_hold: return "pause.circle"
        case .verified: return "checkmark.seal.fill"
        case .resubmission_required: return "arrow.clockwise"
        case .rejected: return "xmark.circle"
        case .banned: return "hand.raised.fill"
        case .unknown: return "exclamationmark.triangle"
        }
    }
    var actionable: Bool { self != .unknown && self != .banned }
}
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonblank: String? { trimmed.isEmpty ? nil : trimmed }
}
struct Submission: Codable, Identifiable, Hashable {
    let id: String
    var full_name: String?
    var business_name: String?
    var city: String?
    var state: String?
    var verification_status: WholesalerStatus?
    var created_at: String?
    var aadhar_number: String?
    var admin_notes: String?
    var rejection_reason: String?
    var email: String?
    var phone: String?
    var admin_version: Int?
    var assigned_to: String?
    var follow_up_at: String?
    var status: WholesalerStatus { verification_status ?? .unknown }
    var displayName: String { full_name?.nonblank ?? "Name not provided" }
    var business: String { business_name?.nonblank ?? "Business not provided" }
    var initial: String { String(displayName.prefix(1)).uppercased() }
    var location: String { [city?.nonblank, state?.nonblank].compactMap { $0 }.joined(separator: ", ").nonblank ?? "Location not provided" }
    var version: Int { admin_version ?? 0 }
    var createdDate: Date? { Self.date(created_at) }
    var submittedDateTimeText: String { Self.timeText(created_at) }
    var ageDays: Int { max(0, Int(Date().timeIntervalSince(createdDate ?? Date()) / 86400)) }
    var maskedAadhaar: String {
        guard let number = aadhar_number?.nonblank else { return "Not provided" }
        return "•••• •••• " + number.suffix(4)
    }
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func timeText(_ value: String?) -> String {
        guard let date = date(value) else { return "Time unavailable" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm z"
        return formatter.string(from: date)
    }
}
struct AdminProfile: Codable, Identifiable {
    let id: String
    let display_name: String
    let role: String
    var can_reveal_pii: Bool
    var require_mfa: Bool
    var canReview: Bool { ["reviewer", "supervisor"].contains(role) }
    var isSupervisor: Bool { role == "supervisor" }
}
struct QueuePage: Codable {
    var rows: [Submission]
    var next_cursor: String?
    var total: Int
}
struct ReviewDetail: Codable {
    var submission: Submission
    var documents: [EvidenceDocument]
    var events: [AuditEvent]
    var ban_request: BanRequest?
}
struct EvidenceDocument: Codable, Identifiable, Hashable {
    var id: String
    var kind: String
    var filename: String
    var mime_type: String?
    var uploaded_at: String?
    var revision: String?
    var available: Bool
    var title: String {
        switch kind {
        case "aadhaar_front": return "Aadhaar front"
        case "aadhaar_back": return "Aadhaar back"
        case "pan_card": return "PAN card"
        case "gst_certificate": return "GST certificate"
        default: return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
struct AuditEvent: Codable, Identifiable {
    var id: String
    var event_type: String
    var actor_name: String
    var occurred_at: String
    var reason: String?
    var new_status: String?
}
struct BanRequest: Codable, Identifiable {
    var id: String
    var requested_by: String
    var reason: String
}
struct DecisionReceipt: Codable, Identifiable {
    var id: String { event_id }
    var event_id: String
    var previous_status: String
    var new_status: String
    var committed_at: String
    var message: String
}
enum DecisionOutcome: String, Codable, CaseIterable, Identifiable {
    case approve, hold, resubmit, reject, ban
    var id: String { rawValue }
    var title: String {
        switch self {
        case .approve: return "Approve application"
        case .hold: return "Put on hold"
        case .resubmit: return "Request resubmission"
        case .reject: return "Reject application"
        case .ban: return "Request permanent ban"
        }
    }
    var impact: String {
        switch self {
        case .approve: return "The applicant gains verified access. Review all required evidence before confirming."
        case .hold: return "The application remains under review. Set a follow-up date and explain why."
        case .resubmit: return "The applicant will be asked to replace the selected documents."
        case .reject: return "The application will be rejected. The applicant receives the message below."
        case .ban: return "A different supervisor must confirm this request before the account is permanently banned."
        }
    }
}
struct DecisionDraft {
    var outcome: DecisionOutcome = .approve
    var reason = ""
    var message = ""
    var documents: Set<String> = []
    var assessments: [String: String] = [:]
    var confirmed = false
    var followUp = Date().addingTimeInterval(86400)
    var requestID = UUID().uuidString
    func validation(required: [EvidenceDocument], status: WholesalerStatus) -> String? {
        guard status.actionable else { return "This status cannot be changed from this workflow." }
        guard reason.trimmed.count >= 5 else { return "Enter a reason with at least 5 characters." }
        guard reason.count <= 2000 && message.count <= 2000 else { return "Keep the reason and message under 2,000 characters." }
        if outcome == .approve && (required.isEmpty || required.contains { !$0.available || assessments[$0.kind] != "pass" }) { return "Inspect and pass every required document before approval." }
        if outcome == .resubmit && documents.isEmpty { return "Select at least one document to replace." }
        if [.approve, .resubmit, .reject].contains(outcome) && message.trimmed.count < 5 { return "Write the applicant-facing message." }
        if outcome == .hold && followUp <= Date() { return "Choose a future follow-up date." }
        guard confirmed else { return "Confirm that you reviewed the impact of this decision." }
        return nil
    }
}
struct IntegrationHealth: Codable, Identifiable {
    var id: String
    var name: String
    var status: String
    var environment: String
    var checked_at: String?
    var detail: String
}
struct SavedQueue: Codable, Identifiable {
    var id = UUID()
    var name: String
    var entity: ReviewEntity
    var status: WholesalerStatus?
    var query: String
    var sort: String
    var ownership: String
}
struct AdminAPIError: LocalizedError {
    var code: String
    var message: String
    var traceID: String? = nil
    var errorDescription: String? { message }
    var title: String {
        switch code {
        case "offline": return "You are offline"
        case "timeout": return "Request timed out"
        case "unauthorized": return "Sign in again"
        case "forbidden": return "Access restricted"
        case "not_found": return "Application not found"
        case "conflict": return "Application changed"
        case "contract": return "App update required"
        default: return "Unable to complete request"
        }
    }
    static func map(_ error: Error) -> AdminAPIError {
        if let error = error as? AdminAPIError { return error }
        if let error = error as? URLError {
            return AdminAPIError(code: error.code == .timedOut ? "timeout" : "offline", message: "Check your connection, then try again. Your last loaded data is preserved.")
        }
        if error is DecodingError { return AdminAPIError(code: "contract", message: "The server response is not compatible with this app. Contact your administrator.") }
        return AdminAPIError(code: "server", message: "The request could not be completed. Try again or contact your administrator.")
    }
}
