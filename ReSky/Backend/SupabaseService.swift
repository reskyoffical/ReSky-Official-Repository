import Foundation
import Supabase

/// Single shared Supabase client. The session (access + refresh token) is stored
/// in the iOS Keychain by the Supabase SDK.
let supabase = SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseAnonKey)

extension UUID {
    /// Postgres returns lowercase UUIDs; use this for filters and comparisons.
    var lc: String { uuidString.lowercased() }
}

/// Maps backend errors to user-facing text.
enum ReSkyError {
    static let codes: [String: String] = [
        "plus_required": "This needs ReSky Plus.",
        "username_format": "Usernames are 3–24 characters: letters, numbers, dots and underscores.",
        "username_taken": "That username is already taken.",
        "username_reserved": "That username is reserved.",
        "username_offensive": "That username isn't allowed.",
        "display_name_offensive": "That display name isn't allowed.",
        "status_offensive": "That status message isn't allowed.",
        "title_offensive": "That group name isn't allowed.",
        "age_requirement": "You must be at least 13 to use ReSky.",
        "not_a_contact": "You can only do that with your contacts.",
        "cosmetic_unavailable": "That item isn't available.",
        "invalid_credentials": "Incorrect username or password.",
        "too_many_attempts": "Too many attempts. Please wait 15 minutes and try again.",
        "email_not_confirmed": "Please verify your email address first — check your inbox.",
        "forbidden": "You don't have permission to do that.",
        "file_too_large": "That file is too large.",
        "unsupported_format": "That file format isn't supported.",
        "call_unavailable": "That call is no longer available.",
        "transaction_bound_to_other_account": "This subscription is already linked to another ReSky account.",
        "cannot_suspend_founder": "The founder account can't be suspended.",
    ]

    static func code(_ error: Error) -> String? {
        let text = String(describing: error) + " " + error.localizedDescription
        if case let FunctionsError.httpError(_, data) = error,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = obj["error"] as? String {
            return code
        }
        return codes.keys.first { text.contains($0) }
    }

    static func message(_ error: Error) -> String {
        if let c = code(error), let m = codes[c] { return m }
        if (error as? URLError) != nil { return "You appear to be offline." }
        return error.localizedDescription
    }
}

/// Minimal client for Supabase Auth endpoints used for 2FA (TOTP), called over HTTPS.
enum AuthREST {
    struct Factor: Decodable, Identifiable {
        let id: String
        let status: String
        let factorType: String?
        let friendlyName: String?
        enum CodingKeys: String, CodingKey {
            case id, status
            case factorType = "factor_type"
            case friendlyName = "friendly_name"
        }
    }
    struct EnrollResponse: Decodable {
        struct TOTP: Decodable { let secret: String; let uri: String }
        let id: String
        let totp: TOTP
    }
    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token" }
    }

    private static func request(_ path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
        let token = try await supabase.auth.session.accessToken
        var req = URLRequest(url: AppConfig.supabaseURL.appendingPathComponent("auth/v1/\(path)"))
        req.httpMethod = method
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            let text = (msg?["msg"] as? String) ?? (msg?["message"] as? String) ?? (msg?["error_description"] as? String) ?? "Request failed"
            throw NSError(domain: "ReSkyAuth", code: (resp as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: text])
        }
        return data
    }

    static func factors() async throws -> [Factor] {
        struct UserResp: Decodable { let factors: [Factor]? }
        let data = try await request("user", method: "GET")
        return try JSONDecoder().decode(UserResp.self, from: data).factors ?? []
    }

    static func enrollTOTP() async throws -> EnrollResponse {
        let name = "ReSky \(Int(Date().timeIntervalSince1970))"
        let data = try await request("factors", method: "POST", body: ["factor_type": "totp", "issuer": "ReSky", "friendly_name": name])
        return try JSONDecoder().decode(EnrollResponse.self, from: data)
    }

    /// Challenges and verifies a TOTP code, then installs the upgraded (aal2) session.
    static func verify(factorID: String, code: String) async throws {
        struct Challenge: Decodable { let id: String }
        let cData = try await request("factors/\(factorID)/challenge", method: "POST", body: [:])
        let challenge = try JSONDecoder().decode(Challenge.self, from: cData)
        let vData = try await request("factors/\(factorID)/verify", method: "POST", body: ["challenge_id": challenge.id, "code": code])
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: vData)
        _ = try await supabase.auth.setSession(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
    }

    static func unenroll(factorID: String) async throws {
        _ = try await request("factors/\(factorID)", method: "DELETE")
    }

    /// Reads the "aal" claim of the current access token.
    static func currentAAL() async -> String {
        guard let token = try? await supabase.auth.session.accessToken else { return "aal1" }
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return "aal1" }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "aal1" }
        return obj["aal"] as? String ?? "aal1"
    }
}
