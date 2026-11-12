import Foundation

enum AppConfig {
    static var supabaseHost: String {
        (Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String) ?? ""
    }

    static var isConfigured: Bool {
        !supabaseHost.isEmpty && !supabaseHost.contains("not-configured") && !supabaseHost.contains("$(")
    }

    static var supabaseURL: URL {
        URL(string: "https://\(isConfigured ? supabaseHost : "not-configured.invalid")")!
    }

    static var supabaseAnonKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String) ?? ""
    }

    static let plusProductID = "com.oopsware.resky.plus.monthly"
    static let authCallbackURL = URL(string: "resky://auth-callback")!
    static let termsURL = URL(string: "https://oopsware.studio/resky/terms")!
    static let privacyURL = URL(string: "https://oopsware.studio/resky/privacy")!
    static let maxAttachmentBytes = 50 * 1024 * 1024
    static let maxProfileImageBytes = 10 * 1024 * 1024

    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// Stable per-install id used for the "active sessions" list.
    static var installID: UUID {
        let key = "resky.installID"
        if let s = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: s) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }
}
