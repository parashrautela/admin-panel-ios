import Foundation
import Combine

@MainActor
final class SessionManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    
    init() {
        // Check if previously authenticated in this session/app launch
        self.isAuthenticated = UserDefaults.standard.bool(forKey: "isAdminAuthenticated")
    }
    
    func login(password: String) throws {
        // Match the web app's fallback password
        let correctPassword = "admin123"
        
        if password == correctPassword {
            isAuthenticated = true
            UserDefaults.standard.set(true, forKey: "isAdminAuthenticated")
        } else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Incorrect password"])
        }
    }
    
    func signOut() {
        isAuthenticated = false
        UserDefaults.standard.set(false, forKey: "isAdminAuthenticated")
    }
}
