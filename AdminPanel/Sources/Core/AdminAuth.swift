import Foundation
import Combine
import Security
import LocalAuthentication

enum SessionKeychain {
    static var service: String { (Bundle.main.bundleIdentifier ?? "com.jewelindia.AdminPanel") + ".session" }
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "refresh"] }
    static func save(_ value: String) {
        remove()
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
    static func read() -> String? {
        var item = query
        item[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func remove() { SecItemDelete(query as CFDictionary) }
}

@MainActor
final class AdminAuth: ObservableObject {
    @Published private(set) var profile: AdminProfile?
    @Published var busy = false
    @Published var error: AdminAPIError?
    @Published var needsMFA = false
    @Published var enrollmentSecret: String?
    @Published var savedSession = SessionKeychain.read() != nil
    @Published var remember = false
    private var factorID: String?
    private var pendingProfile: AdminProfile?
    private var generation = UUID()
    var isAuthenticated: Bool { profile != nil }
    init() {
        AdminAPI.shared.didRefresh = { [weak self] refresh in
            guard self?.remember == true else { return }
            SessionKeychain.save(refresh)
            self?.savedSession = true
        }
        if AppConfiguration.preview { profile = PreviewStore.profile }
    }
    func login(email: String, password: String) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        let stamp = generation
        do {
            if !remember { SessionKeychain.remove(); savedSession = false }
            try await AdminAPI.shared.signIn(email: email, password: password)
            guard generation == stamp else { return }
            try await completeLogin()
        } catch {
            self.error = AdminAPIError.map(error)
        }
    }
    private func completeLogin() async throws {
        let stamp = generation
        let value = try await AdminAPI.shared.profile()
        guard stamp == generation else { throw CancellationError() }
        pendingProfile = value
        // MFA is required for staff by default and is enforced again by the server.
        if value.require_mfa {
            struct Factor: Decodable { let id: String; let status: String; let factor_type: String }
            struct User: Decodable { let factors: [Factor]? }
            let user: User = try await AdminAPI.shared.auth(path: "user", body: [:], method: "GET")
            if let factor = user.factors?.first(where: { $0.status == "verified" && $0.factor_type == "totp" }) {
                factorID = factor.id
            } else {
                // Remove only incomplete TOTP enrollments from this user's previous attempts.
                for factor in user.factors ?? [] where factor.status != "verified" && factor.factor_type == "totp" {
                    struct Removed: Decodable {}
                    let _: Removed = try await AdminAPI.shared.auth(path: "factors/" + factor.id, body: [:], method: "DELETE")
                }
                struct Enrollment: Decodable {
                    let id: String
                    let totp: TOTP
                    struct TOTP: Decodable { let secret: String }
                }
                let enrollment: Enrollment = try await AdminAPI.shared.auth(path: "factors", body: ["factor_type": "totp", "friendly_name": "Jewel India Admin"])
                factorID = enrollment.id
                enrollmentSecret = enrollment.totp.secret
            }
            guard stamp == generation else { throw CancellationError() }
            needsMFA = true
        } else { profile = value }
    }
    func verifyMFA(code: String) async {
        guard !busy, let factorID else { return }
        busy = true; error = nil
        defer { busy = false }
        let stamp = generation
        do {
            struct Challenge: Decodable { let id: String }
            let challenge: Challenge = try await AdminAPI.shared.auth(path: "factors/" + factorID + "/challenge", body: [:])
            let session: TokenSession = try await AdminAPI.shared.auth(path: "factors/" + factorID + "/verify", body: ["challenge_id": challenge.id, "code": code.trimmed])
            guard stamp == generation else { return }
            AdminAPI.shared.setToken(session)
            let value = try await AdminAPI.shared.profile()
            guard stamp == generation else { return }
            profile = value
            pendingProfile = nil; enrollmentSecret = nil; needsMFA = false
        } catch { self.error = AdminAPIError.map(error) }
    }
    func unlock() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let context = LAContext()
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your saved Jewel India admin session")
            guard success, let refresh = SessionKeychain.read() else { return }
            remember = true
            try await AdminAPI.shared.restore(refresh: refresh)
            // A server membership check happens on every unlock.
            try await completeLogin()
        } catch { self.error = AdminAPIError.map(error) }
    }
    func logout() async {
        guard !busy else { return }
        busy = true
        // A failed revocation is surfaced even though local access is always removed.
        var logoutError: AdminAPIError?
        do { try await AdminAPI.shared.signOut() }
        catch { logoutError = AdminAPIError(code: "offline", message: "Signed out on this device. Server revocation could not be confirmed; contact your administrator if the device or account is compromised.") }
        reset(removeSaved: true)
        error = logoutError
        busy = false
    }
    func reset(removeSaved: Bool = true) {
        generation = UUID()
        AdminAPI.shared.clear()
        profile = nil; pendingProfile = nil; needsMFA = false; factorID = nil; enrollmentSecret = nil
        if removeSaved { SessionKeychain.remove(); savedSession = false; remember = false }
    }
}
