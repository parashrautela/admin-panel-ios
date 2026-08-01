import Foundation
import Supabase

// Mirrors the web app's client setup (src/lib/supabase.ts): prefers the
// service-role key when configured, otherwise falls back to the anon key.
let supabase: SupabaseClient = {
    guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
          urlString.hasPrefix("http"),
          let url = URL(string: urlString) else {
        fatalError("SUPABASE_URL not found in Info.plist or is invalid.")
    }

    let serviceKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_SERVICE_ROLE_KEY") as? String
    let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
    guard let key = [serviceKey, anonKey].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
        fatalError("No Supabase key found in Info.plist.")
    }

    return SupabaseClient(supabaseURL: url, supabaseKey: key)
}()
