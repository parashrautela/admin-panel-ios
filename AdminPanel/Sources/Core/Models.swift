import Foundation

enum ReviewEntity: String, CaseIterable, Hashable {
    case wholesaler
    case retailer

    var table: String {
        switch self {
        case .wholesaler: return "wholesalers"
        case .retailer: return "retailers"
        }
    }

    var label: String {
        switch self {
        case .wholesaler: return "Wholesaler"
        case .retailer: return "Retailer"
        }
    }
}

enum WholesalerStatus: String, Codable, CaseIterable, Hashable {
    case pending
    case on_hold
    case verified
    case resubmission_required
    case rejected
    case banned

    // Unknown statuses from the DB decode as .pending instead of crashing.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WholesalerStatus(rawValue: raw) ?? .pending
    }

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .on_hold: return "On Hold"
        case .verified: return "Verified"
        case .resubmission_required: return "Resubmission"
        case .rejected: return "Rejected"
        case .banned: return "Banned"
        }
    }

    // Filter chip label, mirroring the web's capitalize + replace('_', ' ').
    var filterLabel: String {
        let text = rawValue.replacingOccurrences(of: "_", with: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
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
    var aadhaar_front_url: String?
    var aadhaar_back_url: String?
    var business_logo_url: String?
    var pan_card_url: String?
    var gst_certificate_url: String?
    var admin_notes: String?
    var rejection_reason: String?
    var rejected_documents: [String]?
    var referred_by: String?
    var referral_code: String?

    var status: WholesalerStatus { verification_status ?? .pending }
    var displayName: String { full_name ?? "—" }
    var initial: String { String(displayName.prefix(1)).uppercased() }

    var createdDate: Date? {
        guard let created_at else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: created_at) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: created_at) { return date }
        // Postgres timestamps may arrive without a timezone suffix.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: String(created_at.prefix(19)))
    }

    // Matches the web's toLocaleDateString().
    var submittedDateText: String {
        guard let date = createdDate else { return "—" }
        return date.formatted(date: .numeric, time: .omitted)
    }

    // Matches the web's toLocaleString().
    var submittedDateTimeText: String {
        guard let date = createdDate else { return "—" }
        return date.formatted(date: .numeric, time: .shortened)
    }
}

struct ReviewRoute: Hashable {
    let entity: ReviewEntity
    let id: String
}
