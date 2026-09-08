import Foundation
import UIKit

/// Fictional, process-local fixtures. AppConfiguration disables preview arguments in Release builds.
@MainActor
final class PreviewStore {
    static let shared = PreviewStore()
    static let profile = AdminProfile(id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", display_name: "Demo supervisor", role: "supervisor", can_reveal_pii: true, require_mfa: true)
    static let kinds = ["aadhaar_front", "aadhaar_back", "pan_card", "gst_certificate"]
    private var records: [ReviewEntity: [ReviewDetail]] = [:]
    private var receipts: [String: DecisionReceipt] = [:]
    init() {
        for entity in ReviewEntity.allCases {
            records[entity] = (1...65).map { index in
                let status: WholesalerStatus = index == 65 ? .unknown : WholesalerStatus.allCases[(index - 1) % 6]
                let id = String(format: "00000000-0000-4000-8000-%012d", index + (entity == .retailer ? 100 : 0))
                let date = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(index - 66) * 86400))
                let submission = Submission(id: id, full_name: "Sample applicant \(index)", business_name: ["Aarohi Jewels", "Lotus Gold House", "Meera Silver Studio", "Prakash Jewellery", "The Heritage Gold Co."][(index - 1) % 5] + " · Sample \(index)", city: ["Jaipur", "Delhi", "Mumbai", "Surat", "Bengaluru"][(index - 1) % 5], state: nil, verification_status: status, created_at: date, aadhar_number: "1234", admin_notes: nil, rejection_reason: nil, email: "sample\(index)@example.invalid", phone: nil, admin_version: 1, assigned_to: index % 3 == 0 ? Self.profile.id : nil, follow_up_at: status == .on_hold ? date : nil)
                let docs = Self.kinds.map { EvidenceDocument(id: $0, kind: $0, filename: "sample-\($0).pdf", mime_type: "application/pdf", uploaded_at: date, revision: "1", available: index != 4 || $0 != "pan_card") }
                return ReviewDetail(submission: submission, documents: docs, events: [AuditEvent(id: UUID().uuidString, event_type: "application_received", actor_name: "Sample applicant", occurred_at: date, reason: "Fictional sample data. No live applicant records are used.")])
            }
        }
    }
    func counts(_ entity: ReviewEntity) -> [String: Int] {
        Dictionary(grouping: records[entity] ?? [], by: { $0.submission.status.rawValue }).mapValues(\.count)
    }
    func queue(_ entity: ReviewEntity, status: WholesalerStatus?, search: String, sort: String, ownership: String, cursor: String?) -> QueuePage {
        var rows = (records[entity] ?? []).map(\.submission).filter {
            (status == nil || $0.status == status) &&
            (search.trimmed.isEmpty || [$0.business, $0.displayName, $0.location, $0.id].joined(separator: " ").localizedCaseInsensitiveContains(search.trimmed)) &&
            (ownership == "all" || (ownership == "mine" ? $0.assigned_to == Self.profile.id : $0.assigned_to == nil))
        }
        rows.sort { a, b in
            if sort == "name" { return a.business.localizedStandardCompare(b.business) == .orderedAscending }
            return sort == "newest" ? (a.created_at ?? "") > (b.created_at ?? "") : (a.created_at ?? "") < (b.created_at ?? "")
        }
        let start = max(0, Int(cursor ?? "") ?? 0), end = min(start + 30, rows.count)
        return QueuePage(rows: start < end ? Array(rows[start..<end]) : [], next_cursor: end < rows.count ? String(end) : nil, total: rows.count)
    }
    func detail(_ entity: ReviewEntity, id: String) throws -> ReviewDetail {
        guard let result = records[entity]?.first(where: { $0.submission.id == id }) else { throw AdminAPIError(code: "not_found", message: "This sample application is no longer available.") }
        return result
    }
    func decide(_ entity: ReviewEntity, submission: Submission, draft: DecisionDraft) throws -> DecisionReceipt {
        if let prior = receipts[draft.requestID] { return prior }
        let current = try detail(entity, id: submission.id)
        guard current.submission.version == submission.version else { throw AdminAPIError(code: "conflict", message: "Another update changed this application. Reload and review it again.") }
        if let validation = draft.validation(required: current.documents, status: current.submission.status) { throw AdminAPIError(code: "validation", message: validation) }
        let status: WholesalerStatus = [.approve: .verified, .hold: .on_hold, .resubmit: .resubmission_required, .reject: .rejected, .ban: current.submission.status][draft.outcome]!
        let receipt = update(entity, id: submission.id, event: draft.outcome == .ban ? "ban_requested" : draft.outcome.rawValue, reason: draft.reason, status: status)
        if let index = records[entity]?.firstIndex(where: { $0.submission.id == submission.id }) {
            if draft.outcome == .hold {
                records[entity]?[index].submission.follow_up_at = ISO8601DateFormatter().string(from: draft.followUp)
                records[entity]?[index].submission.assigned_to = Self.profile.id
            }
            if draft.outcome == .ban { records[entity]?[index].ban_request = BanRequest(id: UUID().uuidString, requested_by: Self.profile.id, reason: draft.reason) }
        }
        receipts[draft.requestID] = receipt
        return receipt
    }
    func note(_ entity: ReviewEntity, id: String, text: String, requestID: String) -> DecisionReceipt {
        if let prior = receipts[requestID] { return prior }
        let receipt = update(entity, id: id, event: "note_added", reason: text)
        receipts[requestID] = receipt; return receipt
    }
    func assign(_ entity: ReviewEntity, submission: Submission, mine: Bool) -> DecisionReceipt {
        let result = update(entity, id: submission.id, event: "assignment_changed", reason: mine ? "Assigned to Demo supervisor" : "Assignment released")
        if let index = records[entity]?.firstIndex(where: { $0.submission.id == submission.id }) { records[entity]?[index].submission.assigned_to = mine ? Self.profile.id : nil }
        return result
    }
    private func update(_ entity: ReviewEntity, id: String, event: String, reason: String, status: WholesalerStatus? = nil) -> DecisionReceipt {
        let index = records[entity]!.firstIndex { $0.submission.id == id }!
        let old = records[entity]![index].submission.status
        let date = ISO8601DateFormatter().string(from: Date()), eventID = UUID().uuidString
        records[entity]![index].submission.verification_status = status ?? old
        records[entity]![index].submission.admin_version = records[entity]![index].submission.version + 1
        records[entity]![index].events.insert(AuditEvent(id: eventID, event_type: event, actor_name: Self.profile.display_name, occurred_at: date, reason: reason, new_status: (status ?? old).rawValue), at: 0)
        return DecisionReceipt(event_id: eventID, previous_status: old.rawValue, new_status: (status ?? old).rawValue, committed_at: date, message: event == "ban_requested" ? "Request recorded. A different supervisor must confirm the ban." : "Saved to sample history. No live records were changed.")
    }
    static var health: [IntegrationHealth] {
        [IntegrationHealth(id: "database", name: "Admin database", status: "healthy", environment: "Preview", checked_at: ISO8601DateFormatter().string(from: Date()), detail: "Simulated check — sample data only."),
         IntegrationHealth(id: "notifications", name: "Applicant notifications", status: "unknown", environment: "Preview", checked_at: nil, detail: "No delivery check is connected in preview."),
         IntegrationHealth(id: "ai", name: "AI document pipeline", status: "unknown", environment: "Preview", checked_at: nil, detail: "No pipeline check is connected in preview.")]
    }
    static func document(_ kind: String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            for page in 1...(kind == "gst_certificate" ? 3 : 1) {
                context.beginPage()
                let title = kind.replacingOccurrences(of: "_", with: " ").capitalized
                ("SAMPLE · NOT REAL IDENTIFICATION" as NSString).draw(in: CGRect(x: 40, y: 40, width: 530, height: 80), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.systemIndigo])
                (title as NSString).draw(at: CGPoint(x: 40, y: 160), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 30)])
                ("Fictional training document\nAarohi Jewels · Sample applicant\nReference: DEMO-1234\n\nUse pinch to zoom and swipe to review every page.\nThis file contains no real personal information.\n\nPage \(page)" as NSString).draw(in: CGRect(x: 40, y: 240, width: 530, height: 400), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.darkGray])
            }
        }
    }
}
