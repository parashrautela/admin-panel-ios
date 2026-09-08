import Foundation
import OSLog

struct TokenSession: Codable {
    var access_token: String
    var refresh_token: String
    var expires_in: Double
}
extension Notification.Name {
    static let adminSessionExpired = Notification.Name("adminSessionExpired")
    static let adminDataChanged = Notification.Name("adminDataChanged")
}

@MainActor
final class AdminAPI {
    static let shared = AdminAPI()
    private let session: URLSession
    private var token: TokenSession?
    private var expires = Date.distantPast
    private var refreshTask: Task<Void, Error>?
    private var generation = UUID()
    private let log = Logger(subsystem: "com.jewelindia.AdminPanel", category: "network")
    var didRefresh: ((String) -> Void)?
    var preview = AppConfiguration.preview
    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        config.urlCache = nil
        self.session = session ?? URLSession(configuration: config)
    }
    func setToken(_ value: TokenSession) {
        token = value
        expires = Date().addingTimeInterval(value.expires_in)
        didRefresh?(value.refresh_token)
    }
    func clear() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        token = nil
        expires = .distantPast
        session.getAllTasks { $0.forEach { $0.cancel() } }
    }
    func signIn(email: String, password: String) async throws {
        let stamp = generation
        let value: TokenSession = try await auth(path: "token?grant_type=password", body: ["email": email.trimmed, "password": password])
        guard stamp == generation else { throw CancellationError() }
        setToken(value)
    }
    func restore(refresh: String) async throws {
        let stamp = generation
        let value: TokenSession = try await auth(path: "token?grant_type=refresh_token", body: ["refresh_token": refresh])
        guard stamp == generation else { throw CancellationError() }
        setToken(value)
    }
    func signOut() async throws {
        guard !preview else { clear(); return }
        _ = try await authData(path: "logout?scope=local", body: [:])
        clear()
    }
    func auth<T: Decodable>(path: String, body: [String: Any], method: String = "POST") async throws -> T {
        try JSONDecoder().decode(T.self, from: await authData(path: path, body: body, method: method))
    }
    private func authData(path: String, body: [String: Any], method: String = "POST") async throws -> Data {
        let (base, key) = try AppConfiguration.connection()
        let url = URL(string: base.absoluteString + "/auth/v1/" + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token.access_token, forHTTPHeaderField: "Authorization") }
        if method != "GET" { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return try await send(request, expireSession: false)
    }
    func ensureSession() async throws {
        if preview { return }
        if let task = refreshTask { try await task.value; return }
        guard let token else { throw AdminAPIError(code: "unauthorized", message: "Your session ended. Sign in to continue.") }
        guard expires.timeIntervalSinceNow < 60 else { return }
        let task = Task { try await self.restore(refresh: token.refresh_token) }
        refreshTask = task
        defer { refreshTask = nil }
        do { try await task.value }
        catch {
            if let e = error as? AdminAPIError, ["unauthorized", "forbidden"].contains(e.code) {
                clear()
                NotificationCenter.default.post(name: .adminSessionExpired, object: nil)
            }
            throw error
        }
    }
    func call<T: Decodable>(_ action: String, _ body: [String: Any] = [:]) async throws -> T {
        try await ensureSession()
        let (base, key) = try AppConfiguration.connection()
        var request = URLRequest(url: base.appendingPathComponent("functions/v1/admin-v2"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + (token?.access_token ?? ""), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload = body
        payload["action"] = action
        payload["api_version"] = 2
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(T.self, from: await send(request, expireSession: true))
    }
    private func send(_ request: URLRequest, expireSession: Bool) async throws -> Data {
        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw AdminAPIError(code: "server", message: "The server did not return a valid response.") }
            log.info("Request completed status=\(response.statusCode) duration=\(Date().timeIntervalSince(start))")
            guard (200..<300).contains(response.statusCode) else {
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let defaultCode: String = [401: "unauthorized", 403: "forbidden", 404: "not_found", 409: "conflict", 429: "rate_limit"][response.statusCode] ?? "server"
                let code = json?["code"] as? String ?? defaultCode
                let message = json?["message"] as? String ?? json?["msg"] as? String ?? json?["error_description"] as? String ?? "The service is unavailable. Try again or contact your administrator."
                if response.statusCode == 401 && expireSession {
                    clear()
                    NotificationCenter.default.post(name: .adminSessionExpired, object: nil)
                }
                throw AdminAPIError(code: code, message: message, traceID: json?["trace_id"] as? String)
            }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw AdminAPIError.map(error) }
    }
    func profile() async throws -> AdminProfile {
        if preview { return PreviewStore.profile }
        return try await call("profile")
    }
    func counts(entity: ReviewEntity) async throws -> [String: Int] {
        if preview { return PreviewStore.shared.counts(entity) }
        return try await call("counts", ["table": entity.table])
    }
    func queue(entity: ReviewEntity, status: WholesalerStatus?, search: String, sort: String, ownership: String, cursor: String?) async throws -> QueuePage {
        if preview { return PreviewStore.shared.queue(entity, status: status, search: search, sort: sort, ownership: ownership, cursor: cursor) }
        var body: [String: Any] = ["table": entity.table, "search": search.trimmed, "sort": sort, "ownership": ownership, "limit": 30]
        if let status { body["status"] = status.rawValue }
        if let cursor { body["cursor"] = cursor }
        return try await call("queue", body)
    }
    func detail(entity: ReviewEntity, id: String) async throws -> ReviewDetail {
        if preview { return try PreviewStore.shared.detail(entity, id: id) }
        return try await call("detail", ["table": entity.table, "id": id])
    }
    func decide(entity: ReviewEntity, submission: Submission, draft: DecisionDraft) async throws -> DecisionReceipt {
        if preview { return try PreviewStore.shared.decide(entity, submission: submission, draft: draft) }
        return try await call("decision", ["table": entity.table, "id": submission.id, "expected_version": submission.version, "outcome": draft.outcome.rawValue, "reason": draft.reason.trimmed, "message": draft.message.trimmed, "documents": Array(draft.documents), "assessments": draft.assessments, "follow_up_at": ISO8601DateFormatter().string(from: draft.followUp), "request_id": draft.requestID])
    }
    func note(entity: ReviewEntity, id: String, text: String, requestID: String) async throws -> DecisionReceipt {
        if preview { return PreviewStore.shared.note(entity, id: id, text: text, requestID: requestID) }
        return try await call("note", ["table": entity.table, "id": id, "reason": text.trimmed, "request_id": requestID])
    }
    func assign(entity: ReviewEntity, submission: Submission, mine: Bool, requestID: String) async throws -> DecisionReceipt {
        if preview { return PreviewStore.shared.assign(entity, submission: submission, mine: mine) }
        return try await call("assign", ["table": entity.table, "id": submission.id, "expected_version": submission.version, "mine": mine, "request_id": requestID])
    }
    func confirmBan(entity: ReviewEntity, submission: Submission, request: BanRequest, reason: String, requestID: String) async throws -> DecisionReceipt {
        if preview { throw AdminAPIError(code: "forbidden", message: "A different supervisor must confirm the request.") }
        return try await call("confirm_ban", ["table": entity.table, "id": submission.id, "expected_version": submission.version, "ban_request_id": request.id, "reason": reason.trimmed, "request_id": requestID])
    }
    func reveal(entity: ReviewEntity, id: String) async throws -> String {
        if preview { return "0000 0000 1234" }
        struct Value: Decodable { let value: String }
        let result: Value = try await call("reveal", ["table": entity.table, "id": id])
        return result.value
    }
    func health() async throws -> [IntegrationHealth] {
        if preview { return PreviewStore.health }
        return try await call("health")
    }
    func document(entity: ReviewEntity, id: String, kind: String) async throws -> (Data, String) {
        if preview { return (PreviewStore.document(kind), "application/pdf") }
        struct Link: Decodable { let url: String }
        let link: Link = try await call("document", ["table": entity.table, "id": id, "kind": kind])
        let (base, _) = try AppConfiguration.connection()
        guard let url = URL(string: link.url), url.scheme == "https", url.host == base.host else {
            throw AdminAPIError(code: "document", message: "Evidence must be served by the approved secure storage host.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        let (bytes, response) = try await session.bytes(for: request)
        guard response.url?.scheme == "https", response.url?.host == base.host else {
            throw AdminAPIError(code: "document", message: "The document redirected outside approved storage and was not displayed.")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AdminAPIError(code: "document", message: "This document link has expired or is unavailable. Close the viewer and try again.")
        }
        let maximum = 20 * 1024 * 1024
        guard response.expectedContentLength <= maximum else { throw AdminAPIError(code: "document", message: "This document exceeds the 20 MB review limit. Request a smaller file.") }
        var data = Data()
        for try await byte in bytes {
            if data.count >= maximum { throw AdminAPIError(code: "document", message: "This document exceeds the 20 MB review limit.") }
            data.append(byte)
        }
        return (data, response.mimeType ?? "application/octet-stream")
    }
}
