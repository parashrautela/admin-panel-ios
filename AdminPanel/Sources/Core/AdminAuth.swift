import Foundation
import Combine

// Mirrors the web's AdminProtected gate: a simple password check that lasts
// for the app session only (the web equivalent uses sessionStorage).
@MainActor
final class AdminAuth: ObservableObject {
    @Published var isAuthenticated = false

    private let adminPassword =
        (Bundle.main.object(forInfoDictionaryKey: "ADMIN_PASSWORD") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "admin123"

    /// Returns true when the password matches, mirroring the web's handleLogin.
    func login(password: String) -> Bool {
        guard password == adminPassword else { return false }
        isAuthenticated = true
        return true
    }
}
