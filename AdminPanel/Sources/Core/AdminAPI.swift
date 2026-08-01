import Foundation
import Supabase

// Mirrors src/lib/adminApi.ts from the web admin panel.
enum AdminAPI {

    // MARK: - Reads

    static func fetchStatusCounts(entity: ReviewEntity) async throws -> [WholesalerStatus: Int] {
        try await withThrowingTaskGroup(of: (WholesalerStatus, Int).self) { group in
            for status in WholesalerStatus.allCases {
                group.addTask {
                    let response = try await supabase
                        .from(entity.table)
                        .select("*", head: true, count: .exact)
                        .eq("verification_status", value: status.rawValue)
                        .execute()
                    return (status, response.count ?? 0)
                }
            }
            var counts: [WholesalerStatus: Int] = [:]
            for try await (status, count) in group {
                counts[status] = count
            }
            return counts
        }
    }

    static func fetchSubmissions(
        entity: ReviewEntity,
        statusFilter: WholesalerStatus?,
        searchQuery: String
    ) async throws -> [Submission] {
        var query = supabase
            .from(entity.table)
            .select("id, full_name, business_name, city, state, created_at, verification_status")

        if let statusFilter {
            query = query.eq("verification_status", value: statusFilter.rawValue)
        }

        let search = searchQuery.trimmingCharacters(in: .whitespaces)
        if !search.isEmpty {
            query = query.or("full_name.ilike.%\(search)%,business_name.ilike.%\(search)%")
        }

        return try await query
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func fetchSubmissionDetail(entity: ReviewEntity, id: String) async throws -> Submission {
        try await supabase
            .from(entity.table)
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    // MARK: - Admin actions (same payloads as the web app)

    private struct VerifyPayload: Encodable {
        let verification_status: String
        let notification_message: String
        let notified: Bool
    }

    private struct RejectPayload: Encodable {
        let verification_status: String
        let rejection_reason: String
        let notification_message: String
        let notified: Bool
    }

    private struct ResubmissionPayload: Encodable {
        let verification_status: String
        let rejected_documents: [String]
        let rejection_reason: String
        let notification_message: String
        let notified: Bool
    }

    private struct OnHoldPayload: Encodable {
        let verification_status: String
        let admin_notes: String
    }

    private struct BanPayload: Encodable {
        let verification_status: String
        let notification_message: String
    }

    private struct NotesPayload: Encodable {
        let admin_notes: String
    }

    private static func update(_ entity: ReviewEntity, _ id: String, _ payload: some Encodable) async throws {
        try await supabase
            .from(entity.table)
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    static func verifySubmission(entity: ReviewEntity, id: String) async throws {
        try await update(entity, id, VerifyPayload(
            verification_status: "verified",
            notification_message: "You're verified! You can now access your full dashboard.",
            notified: false
        ))
    }

    static func rejectSubmission(entity: ReviewEntity, id: String, reason: String) async throws {
        try await update(entity, id, RejectPayload(
            verification_status: "rejected",
            rejection_reason: reason.isEmpty ? "Review failed." : reason,
            notification_message: "Verification failed. \(reason.isEmpty ? "Contact support." : reason)",
            notified: false
        ))
    }

    static func requestResubmission(
        entity: ReviewEntity,
        id: String,
        documents: [String],
        reason: String
    ) async throws {
        try await update(entity, id, ResubmissionPayload(
            verification_status: "resubmission_required",
            rejected_documents: documents,
            rejection_reason: reason.isEmpty ? "Please resubmit your documents." : reason,
            notification_message: "Some documents need to be resubmitted.",
            notified: false
        ))
    }

    static func putOnHold(entity: ReviewEntity, id: String, notes: String) async throws {
        try await update(entity, id, OnHoldPayload(
            verification_status: "on_hold",
            admin_notes: notes
        ))
    }

    static func banSubmission(entity: ReviewEntity, id: String) async throws {
        try await update(entity, id, BanPayload(
            verification_status: "banned",
            notification_message: "Your account has been suspended."
        ))
    }

    static func saveNotes(entity: ReviewEntity, id: String, notes: String) async throws {
        try await update(entity, id, NotesPayload(admin_notes: notes))
    }
}
