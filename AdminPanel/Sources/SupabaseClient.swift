import Foundation
import Supabase

// Anon key only — this app never holds the service-role key. Privileged
// admin reads/writes go through password-gated Edge Functions instead (see
// AdminAPI.swift), which hold the service-role key server-side.
let supabase: SupabaseClient = {
    guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
          urlString.hasPrefix("http"),
          let url = URL(string: urlString) else {
        fatalError("SUPABASE_URL not found in Info.plist or is invalid.")
    }

    guard let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
          !anonKey.isEmpty else {
        fatalError("SUPABASE_ANON_KEY not found in Info.plist.")
    }

    return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
}()
