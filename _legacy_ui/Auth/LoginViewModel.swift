import Foundation
import Combine
import Supabase

@MainActor
final class LoginViewModel: ObservableObject {
    // We hardcode the admin email behind the scenes since the UI only requires a password
    private let adminEmail = "admin@example.com" // TODO: Update this to your actual admin email
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    var isFormValid: Bool {
        !password.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    func signIn() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await supabase.auth.signIn(email: adminEmail, password: password)
            // If successful, SessionManager will detect the state change automatically
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
