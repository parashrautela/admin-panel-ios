import Foundation
import Supabase

// A readable error message from an Edge Function's `{ error: "..." }` body,
// so callers (toasts, the login screen) show something meaningful instead of
// FunctionsError's generic "non-2xx status code" text.
struct AdminAPIError: LocalizedError {
    let message: String
    var code: String? = nil
    var status: Int? = nil
    var errorDescription: String? { message }
}

// Mirrors src/lib/adminApi.ts from the web admin panel, but talks to
// password-gated Edge Functions instead of the database directly — this app
// never holds the Supabase service-role key (see SupabaseClient.swift).
enum AdminAPI {

    // Set once by AdminAuth.login on success; attached to every call below
    // as the x-admin-password header. In-memory only, cleared on relaunch —
    // mirrors the web's sessionStorage-scoped login.
    static var adminPassword: String?

    // MARK: - Auth

    static func verifyPassword(_ password: String) async throws {
        do {
            try await supabase.functions.invoke(
                "admin-verify-password",
                options: FunctionInvokeOptions(headers: ["x-admin-password": password])
            )
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Reads

    static func fetchStatusCounts(entity: ReviewEntity) async throws -> [WholesalerStatus: Int] {
        struct Body: Encodable { let table: String }
        let raw: [String: Int] = try await invoke(
            "admin-fetch-status-counts",
            body: Body(table: entity.table)
        )
        var counts: [WholesalerStatus: Int] = [:]
        for status in WholesalerStatus.allCases {
            counts[status] = raw[status.rawValue] ?? 0
        }
        return counts
    }

    static func fetchSubmissions(
        entity: ReviewEntity,
        statusFilter: WholesalerStatus?,
        searchQuery: String
    ) async throws -> [Submission] {
        struct Body: Encodable {
            let table: String
            let statusFilter: String?
            let searchQuery: String
        }
        return try await invoke(
            "admin-fetch-submissions",
            body: Body(table: entity.table, statusFilter: statusFilter?.rawValue, searchQuery: searchQuery)
        )
    }

    static func fetchSubmissionDetail(entity: ReviewEntity, id: String) async throws -> Submission {
        struct Body: Encodable { let table: String; let id: String }
        return try await invoke(
            "admin-fetch-submission-detail",
            body: Body(table: entity.table, id: id)
        )
    }

    static func referrals(page: Int, search: String, status: String?, wholesaler: String?, retailer: String?) async throws -> ReferralPage {
        struct Body: Encodable { let action = "list"; let page: Int; let search: String; let status: String?; let wholesaler_id: String?; let retailer_id: String? }
        return try await invoke("admin-referrals", body: Body(page: page, search: search, status: status, wholesaler_id: wholesaler, retailer_id: retailer))
    }
    static func referralEvents(id: String) async throws -> [ReferralEvent] {
        struct Body: Encodable { let action = "events"; let id: String }
        struct Response: Decodable { let events: [ReferralEvent] }
        let response: Response = try await invoke("admin-referrals", body: Body(id: id))
        return response.events
    }
    static func repairReferral(retailer: String) async throws {
        struct Body: Encodable { let action = "settle"; let retailer_id: String }
        try await invokeVoid("admin-referrals", body: Body(retailer_id: retailer))
    }

    static func creditAllowance(entity: ReviewEntity, id: String) async throws -> CreditAllowancePage {
        struct Body: Encodable {
            let action = "list"
            let business_type: String
            let wholesaler_id: String
            let page = 0
            let pageSize = 1
        }
        return try await invoke("admin-credit-allowances", body: Body(business_type: entity.rawValue, wholesaler_id: id))
    }

    static func saveCreditAllowance(_ change: CreditAllowanceChange) async throws -> CreditAllowanceSaved {
        try await invoke("admin-credit-allowances", body: change)
    }

    static func giveCreditsNow(_ change: CreditAllowanceChange) async throws -> ImmediateCreditSaved {
        try await invoke("admin-credit-allowances", body: change)
    }

    // MARK: - Admin actions (same payloads as the web app)

    static func verifySubmission(entity: ReviewEntity, id: String) async throws {
        struct Body: Encodable { let table: String; let id: String }
        try await invokeVoid("admin-verify-submission", body: Body(table: entity.table, id: id))
    }

    static func rejectSubmission(entity: ReviewEntity, id: String, reason: String) async throws {
        struct Body: Encodable { let table: String; let id: String; let reason: String }
        try await invokeVoid(
            "admin-reject-submission",
            body: Body(table: entity.table, id: id, reason: reason.isEmpty ? "Review failed." : reason)
        )
    }

    static func requestResubmission(
        entity: ReviewEntity,
        id: String,
        documents: [String],
        reason: String
    ) async throws {
        struct Body: Encodable { let table: String; let id: String; let documents: [String]; let reason: String }
        try await invokeVoid(
            "admin-request-resubmission",
            body: Body(table: entity.table, id: id, documents: documents, reason: reason)
        )
    }

    static func putOnHold(entity: ReviewEntity, id: String, notes: String) async throws {
        struct Body: Encodable { let table: String; let id: String; let notes: String }
        try await invokeVoid("admin-hold-submission", body: Body(table: entity.table, id: id, notes: notes))
    }

    static func banSubmission(entity: ReviewEntity, id: String) async throws {
        struct Body: Encodable { let table: String; let id: String }
        try await invokeVoid("admin-ban-submission", body: Body(table: entity.table, id: id))
    }

    static func saveNotes(entity: ReviewEntity, id: String, notes: String) async throws {
        struct Body: Encodable { let table: String; let id: String; let notes: String }
        try await invokeVoid("admin-save-notes", body: Body(table: entity.table, id: id, notes: notes))
    }

    // MARK: - Transport

    private static var passwordHeader: [String: String] {
        guard let adminPassword else { return [:] }
        return ["x-admin-password": adminPassword]
    }

    private static func invoke<Body: Encodable, Response: Decodable>(
        _ function: String,
        body: Body
    ) async throws -> Response {
        do {
            return try await supabase.functions.invoke(
                function,
                options: FunctionInvokeOptions(headers: passwordHeader, body: body)
            )
        } catch {
            throw mapError(error)
        }
    }

    private static func invokeVoid<Body: Encodable>(_ function: String, body: Body) async throws {
        do {
            try await supabase.functions.invoke(
                function,
                options: FunctionInvokeOptions(headers: passwordHeader, body: body)
            )
        } catch {
            throw mapError(error)
        }
    }

    private static func mapError(_ error: Error) -> Error {
        struct Failure: Decodable { let error: String?; let message: String? }
        guard case let FunctionsError.httpError(status, data) = error,
              let body = try? JSONDecoder().decode(Failure.self, from: data) else { return error }
        let friendly: String
        switch body.error {
        case "VERSION_CONFLICT": friendly = "This allocation changed elsewhere. Refresh before editing again."
        case "IDEMPOTENCY_CONFLICT": friendly = "This request could not be reused. Refresh before editing again."
        case "NOT_VERIFIED": friendly = "Verify this business before changing its allocation."
        default: friendly = body.message ?? body.error ?? "The request could not be completed."
        }
        return AdminAPIError(message: friendly, code: body.error, status: status)
    }
}
