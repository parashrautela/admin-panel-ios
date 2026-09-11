import Foundation
import Supabase

// A readable error message from an Edge Function's `{ error: "..." }` body,
// so callers (toasts, the login screen) show something meaningful instead of
// FunctionsError's generic "non-2xx status code" text.
struct AdminAPIError: LocalizedError {
    let message: String
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
        guard case FunctionsError.httpError(_, let data) = error,
              let body = try? JSONDecoder().decode([String: String].self, from: data),
              let message = body["error"] else {
            return error
        }
        return AdminAPIError(message: message)
    }
}
