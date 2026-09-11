import Foundation
import Combine

// Mirrors the web's AdminProtected gate: a password check that lasts for the
// app session only (the web equivalent uses sessionStorage). The password
// itself is verified server-side by AdminAPI.verifyPassword — this class
// never knows or stores a "correct" value locally.
@MainActor
final class AdminAuth: ObservableObject {
    @Published var isAuthenticated = false

    /// Returns true when the password is accepted by the server, mirroring
    /// the web's handleLogin. Throws (rather than returning false) on
    /// network/transport failures so the login screen can show why.
    func login(password: String) async throws -> Bool {
        do {
            try await AdminAPI.verifyPassword(password)
        } catch let error as AdminAPIError where error.message.lowercased().contains("unauthorized") {
            return false
        }
        AdminAPI.adminPassword = password
        isAuthenticated = true
        return true
    }
}
