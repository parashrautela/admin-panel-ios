import Foundation

enum AppConfiguration {
    static var environment: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "ADMIN_ENVIRONMENT") as? String
        return value?.nonblank.flatMap { $0.contains("$(") ? nil : $0 } ?? "Environment not set"
    }
    static var preview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--preview-data")
        #else
        return false
        #endif
    }
    static func connection() throws -> (URL, String) {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: raw), url.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty, !key.contains("$(") else {
            throw AdminAPIError(code: "configuration", message: "The server connection is not configured. Check the build configuration with your administrator.")
        }
        return (url, key)
    }
}
