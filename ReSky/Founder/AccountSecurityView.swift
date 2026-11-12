import SwiftUI
import CoreImage.CIFilterBuiltins
import Supabase

/// Change username / password / email, 2FA, active sessions, sign out other devices, delete account.
/// Used by every user, and wrapped by FounderSettingsView for the founder.
struct AccountSecurityView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var newUsername = ""
    @State private var usernameMsg: String?
    @State private var newEmail = ""
    @State private var emailMsg: String?
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordMsg: String?
    @State private var confirmDelete = false
    @State private var deleteText = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Current", value: "@\(session.me?.username ?? "")")
                TextField("New username", text: $newUsername).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Change username") { Task { await changeUsername() } }
                    .disabled(UsernameRules.formatProblem(newUsername) != nil)
                if let usernameMsg { Text(usernameMsg).font(.footnote) }
            } header: { Text("Username") } footer: {
                Text(session.isFounder
                     ? "Your Founder role is tied to your account, not your username — renaming never removes Founder privileges."
                     : "Your username updates everywhere instantly. Contacts keep you in their list.")
            }

            Section("Email") {
                TextField("New email address", text: $newEmail).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Change email") { Task { await changeEmail() } }.disabled(!UsernameRules.isValidEmail(newEmail))
                if let emailMsg { Text(emailMsg).font(.footnote) }
            }

            Section("Password") {
                SecureField("New password", text: $newPassword).textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword).textContentType(.newPassword)
                PasswordChecklist(password: newPassword, confirm: confirmPassword)
                Button("Change password") { Task { await changePassword() } }
                    .disabled(!UsernameRules.passwordProblems(newPassword).isEmpty || newPassword != confirmPassword)
                if let passwordMsg { Text(passwordMsg).font(.footnote) }
            }

            Section("Security") {
                NavigationLink { TwoFactorView() } label: { Label("Two-factor authentication", systemImage: "lock.shield.fill") }
                NavigationLink { SessionsView() } label: { Label("Active sessions", systemImage: "iphone.and.arrow.forward") }
            }

            Section {
                Button("Delete account…", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Permanently deletes your account, messages you sent, uploads and subscription link. Cancel any App Store subscription separately in your Apple ID settings.")
            }
        }
        .navigationTitle("Account & security")
        .alert("Delete your account?", isPresented: $confirmDelete) {
            TextField("Type DELETE", text: $deleteText)
            Button("Delete", role: .destructive) {
                guard deleteText == "DELETE" else { return }
                Task { try? await session.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This can't be undone. Type DELETE to confirm.") }
    }

    private func changeUsername() async {
        do {
            let name: String = try await supabase.rpc("change_username", params: ["new_username": newUsername.lowercased()]).execute().value
            usernameMsg = "Username changed to @\(name)."
            newUsername = ""
            await session.loadProfile()
            Haptics.success()
        } catch {
            usernameMsg = ReSkyError.message(error)
        }
    }

    private func changeEmail() async {
        do {
            _ = try await supabase.auth.update(user: UserAttributes(email: newEmail), redirectTo: AppConfig.authCallbackURL)
            emailMsg = "Check both your old and new inbox to confirm the change."
        } catch {
            emailMsg = ReSkyError.message(error)
        }
    }

    private func changePassword() async {
        do {
            _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
            passwordMsg = "Password changed."
            newPassword = ""; confirmPassword = ""
            Haptics.success()
        } catch {
            passwordMsg = ReSkyError.message(error)
        }
    }
}

struct TwoFactorView: View {
    @State private var factors: [AuthREST.Factor] = []
    @State private var enrolling: AuthREST.EnrollResponse?
    @State private var code = ""
    @State private var message: String?
    @State private var loading = true

    private var verified: [AuthREST.Factor] { factors.filter { $0.status == "verified" } }

    var body: some View {
        Form {
            if loading {
                ProgressView()
            } else if let enrolling {
                Section("1. Scan with your authenticator app") {
                    if let img = qr(enrolling.totp.uri) {
                        Image(uiImage: img).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 220).frame(maxWidth: .infinity)
                    }
                    if let url = URL(string: enrolling.totp.uri) { Link("Open in authenticator app", destination: url) }
                    LabeledContent("Setup key") { Text(enrolling.totp.secret).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
                }
                Section("2. Enter the 6-digit code") {
                    TextField("123456", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    Button("Verify and turn on") { Task { await verify(enrolling.id) } }.disabled(code.count != 6)
                }
            } else if verified.isEmpty {
                Section {
                    Text("Protect your account with a code from an authenticator app (Google Authenticator, 1Password, Authy…) whenever you sign in.")
                    Button("Set up two-factor authentication") { Task { await enroll() } }
                }
            } else {
                Section {
                    Label("Two-factor authentication is ON", systemImage: "checkmark.shield.fill").foregroundStyle(Color.reskyGreenDark)
                    ForEach(verified) { f in
                        HStack {
                            Text(f.friendlyName ?? "Authenticator")
                            Spacer()
                            Button("Remove", role: .destructive) { Task { try? await AuthREST.unenroll(factorID: f.id); await load() } }
                        }
                    }
                } footer: { Text("Removing requires a session that has already passed two-factor verification.") }
            }
            if let message { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle("Two-factor authentication")
        .task { await load() }
    }

    private func load() async {
        loading = true
        factors = (try? await AuthREST.factors()) ?? []
        // Clean up abandoned, unverified enrolments
        for f in factors where f.status != "verified" { try? await AuthREST.unenroll(factorID: f.id) }
        factors = factors.filter { $0.status == "verified" }
        loading = false
    }

    private func enroll() async {
        do { enrolling = try await AuthREST.enrollTOTP() } catch { message = error.localizedDescription }
    }

    private func verify(_ id: String) async {
        do {
            try await AuthREST.verify(factorID: id, code: code)
            enrolling = nil
            code = ""
            message = "Two-factor authentication is now on."
            Haptics.success()
            await load()
        } catch {
            message = "That code didn't work — check your device clock and try again."
        }
    }

    private func qr(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct SessionsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var devices: [DeviceRow] = []
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(devices) { d in
                    HStack {
                        Image(systemName: "iphone").foregroundStyle(Color.reskyBlue)
                        VStack(alignment: .leading) {
                            Text(d.deviceName + (d.id == AppConfig.installID ? " (this device)" : "")).font(.resky(.body, weight: .semibold))
                            Text("ReSky \(d.appVersion ?? "") · active \(DateParser.parse(d.lastActiveAt).formatted(.relative(presentation: .named)))")
                                .font(.resky(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Signing out other devices revokes their sessions; they'll need your password (and 2FA code) to sign back in.")
            }
            Section {
                Button("Log out all other devices", role: .destructive) {
                    Task {
                        do { try await session.signOutOtherDevices(); message = "Other devices have been signed out."; await load() }
                        catch { message = ReSkyError.message(error) }
                    }
                }
                if let message { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Active sessions")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        devices = (try? await supabase.from("user_devices").select().order("last_active_at", ascending: false).execute().value) ?? []
    }
}

struct FounderSettingsView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AvatarView(profile: session.me, size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(session.me?.displayName ?? "").font(.resky(.title3, weight: .bold)); RoleBadges(profile: session.me) }
                        Text("@\(session.me?.username ?? "")").foregroundStyle(.secondary)
                        Label("All premium features unlocked permanently", systemImage: "crown.fill")
                            .font(.resky(.caption, weight: .semibold)).foregroundStyle(Color.reskyGold)
                    }
                }
                .padding(.vertical, 6)
            }
            Section("Founder credentials") {
                NavigationLink { AccountSecurityView() } label: { Label("Change username, password & email", systemImage: "key.fill") }
                NavigationLink { TwoFactorView() } label: { Label("Two-factor authentication", systemImage: "lock.shield.fill") }
                NavigationLink { SessionsView() } label: { Label("Active sessions & log out other devices", systemImage: "iphone.and.arrow.forward") }
            }
            Section("Administration") {
                NavigationLink { AdminDashboardView() } label: { Label("Admin dashboard", systemImage: "shield.lefthalf.filled") }
            }
            Section {
                Text("Founder status is stored as a server-side role on your account id. It is verified by the database on every privileged action and is unaffected by username changes. With 2FA on, admin actions require a 2FA-verified session.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Founder Settings")
    }
}
