import Foundation
import SwiftUI
import Supabase
import UIKit

/// Owns the signed-in state, the current user's profile, presence heartbeat and device registration.
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    enum Phase: Equatable { case loading, signedOut, needsMFA, passwordRecovery, signedIn }

    @Published var phase: Phase = .loading
    @Published var userId: UUID?
    @Published var me: ProfileCard?
    @Published var settings: AccountPrivate?
    @Published var ownRow: OwnProfileRow?
    @Published var entitlement: EntitlementRow?
    @Published var pendingConversation: UUID?
    @Published var banner: String?

    private var heartbeatTask: Task<Void, Never>?
    private var started = false

    var isFounder: Bool { me?.isFounder ?? false }
    var hasPlus: Bool { me?.isPlus ?? false }
    var isSuspended: Bool { DateParser.parse(ownRow?.suspendedUntil) > Date() }

    func start() {
        guard !started else { return }
        started = true
        Task {
            for await (event, session) in supabase.auth.authStateChanges {
                switch event {
                case .passwordRecovery:
                    phase = .passwordRecovery
                case .signedOut:
                    await handleSignedOut()
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
                    if phase == .passwordRecovery && event != .userUpdated { continue }
                    await evaluate(session)
                default:
                    break
                }
            }
        }
    }

    private func evaluate(_ session: Session?) async {
        guard let session else {
            await handleSignedOut()
            return
        }
        userId = session.user.id
        // If the user has 2FA enabled the session must be upgraded to aal2 first.
        let aal = await AuthREST.currentAAL()
        if aal == "aal1", let factors = try? await AuthREST.factors(), factors.contains(where: { $0.status == "verified" }) {
            phase = .needsMFA
            return
        }
        await loadProfile()
        if phase != .signedIn {
            phase = .signedIn
            startHeartbeat()
            await registerDevice()
            await Outbox.shared.flush()
            CallManager.shared.start()
            InboxStore.shared.start()
            ContactsStore.shared.start()
            Task { await PlusStore.shared.syncOnLaunch() }
            Task { await PushManager.shared.requestPermission() }
        }
    }

    private func handleSignedOut() async {
        heartbeatTask?.cancel()
        CallManager.shared.stop()
        InboxStore.shared.stop()
        ContactsStore.shared.stop()
        LocalStore.clearAll()
        userId = nil
        me = nil
        settings = nil
        phase = .signedOut
    }

    func loadProfile() async {
        guard let uid = userId else { return }
        do {
            me = try await supabase.from("profile_cards").select().eq("id", value: uid.lc).single().execute().value
            settings = try? await supabase.from("account_private").select().eq("user_id", value: uid.lc).single().execute().value
            ownRow = try? await supabase.from("profiles").select("profile_visibility, suspended_until, presence")
                .eq("id", value: uid.lc).single().execute().value
            let ents: [EntitlementRow] = (try? await supabase.from("entitlements").select("plus_expires_at, auto_renew, product_id")
                .eq("user_id", value: uid.lc).execute().value) ?? []
            entitlement = ents.first
        } catch {
            banner = ReSkyError.message(error)
        }
    }

    // MARK: Auth actions

    struct LoginResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let suspended_until: String?
    }

    func signIn(identifier: String, password: String) async throws {
        struct Body: Encodable { let identifier: String; let password: String }
        let res: LoginResponse = try await supabase.functions.invoke(
            "login", options: FunctionInvokeOptions(body: Body(identifier: identifier, password: password)))
        _ = try await supabase.auth.setSession(accessToken: res.access_token, refreshToken: res.refresh_token)
        if let s = res.suspended_until { banner = "Your account is suspended until \(DateParser.parse(s).formatted()). You can read but not send." }
    }

    func signUp(displayName: String, username: String, email: String, password: String, dob: Date) async throws -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let res = try await supabase.auth.signUp(
            email: email, password: password,
            data: ["username": .string(username.lowercased()), "display_name": .string(displayName),
                   "date_of_birth": .string(f.string(from: dob))],
            redirectTo: AppConfig.authCallbackURL)
        return res.session != nil // false => email confirmation required
    }

    func sendPasswordReset(email: String) async {
        try? await supabase.auth.resetPasswordForEmail(email, redirectTo: AppConfig.authCallbackURL)
    }

    func setNewPassword(_ password: String) async throws {
        _ = try await supabase.auth.update(user: UserAttributes(password: password))
        phase = .loading
        await evaluate(try? await supabase.auth.session)
    }

    func verifyMFA(code: String) async throws {
        let factors = try await AuthREST.factors().filter { $0.status == "verified" }
        guard let f = factors.first else { return }
        try await AuthREST.verify(factorID: f.id, code: code)
    }

    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "resky" else { return }
        do {
            _ = try await supabase.auth.session(from: url)
        } catch {
            banner = "That link has expired. Please request a new one."
        }
    }

    func signOut() async {
        try? await supabase.from("user_devices").update(["push_token": AnyJSON.null]).eq("id", value: AppConfig.installID.lc).execute()
        try? await supabase.auth.signOut()
        await handleSignedOut()
    }

    func signOutOtherDevices() async throws {
        try await supabase.auth.signOut(scope: .others)
        if let uid = userId {
            try? await supabase.from("user_devices").delete()
                .eq("user_id", value: uid.lc).neq("id", value: AppConfig.installID.lc).execute()
        }
    }

    func deleteAccount() async throws {
        struct Body: Encodable { let confirm = "DELETE" }
        struct Res: Decodable { let deleted: Bool }
        let _: Res = try await supabase.functions.invoke("delete-account", options: FunctionInvokeOptions(body: Body()))
        try? await supabase.auth.signOut(scope: .local)
        await handleSignedOut()
    }

    // MARK: Presence

    func setPresence(_ status: PresenceStatus) async {
        UserDefaults.standard.set(status.rawValue, forKey: "resky.chosenPresence")
        try? await supabase.rpc("heartbeat", params: ["new_presence": status.rawValue]).execute()
        await loadProfile()
    }

    var chosenPresence: PresenceStatus {
        PresenceStatus(rawValue: UserDefaults.standard.string(forKey: "resky.chosenPresence") ?? "online") ?? .online
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            let initial = settings?.onlineVisible == false ? PresenceStatus.invisible : chosenPresence
            try? await supabase.rpc("heartbeat", params: ["new_presence": initial.rawValue]).execute()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if UIApplication.shared.applicationState == .active {
                    try? await supabase.rpc("heartbeat").execute()
                }
            }
        }
    }

    func appBecameActive() {
        guard phase == .signedIn else { return }
        Task {
            try? await supabase.rpc("heartbeat").execute()
            await registerDevice()
            await Outbox.shared.flush()
            await InboxStore.shared.refresh()
        }
    }

    // MARK: Devices / push

    func registerDevice() async {
        guard let uid = userId else { return }
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        let row = DeviceRow(id: AppConfig.installID, userId: uid,
                            deviceName: "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)",
                            platform: "ios", appVersion: AppConfig.appVersion,
                            pushToken: PushManager.shared.deviceToken, pushEnvironment: env,
                            lastActiveAt: ISO8601DateFormatter().string(from: Date()))
        try? await supabase.from("user_devices").upsert(row, onConflict: "id").execute()
    }
}
