import SwiftUI
import Supabase

struct CreateAccountForm: View {
    @EnvironmentObject private var session: SessionStore
    var onBack: () -> Void
    var onCheckEmail: (String) -> Void

    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var agreed = false
    @State private var usernameStatus: String?
    @State private var usernameOK = false
    @State private var busy = false
    @State private var error: String?
    @State private var checkTask: Task<Void, Never>?

    private var ageOK: Bool {
        (Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0) >= 13
    }

    private var agreementText: String {
        "I agree to the [Terms of Use](\(AppConfig.termsURL.absoluteString)) and [Privacy Policy](\(AppConfig.privacyURL.absoluteString))."
    }

    private var canSubmit: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && usernameOK && UsernameRules.isValidEmail(email)
            && UsernameRules.passwordProblems(password).isEmpty && password == confirm && ageOK && agreed && !busy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Button(action: onBack) { Image(systemName: "chevron.left").font(.headline) }
                Text("Create your ReSky account").font(.resky(.title3, weight: .bold))
            }
            field("Display name") {
                TextField("How friends see you", text: $displayName).textFieldStyle(ReSkyTextFieldStyle()).textContentType(.name)
            }
            field("ReSky Name (username)") {
                TextField("e.g. cloud.walker", text: $username)
                    .textFieldStyle(ReSkyTextFieldStyle())
                    .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    .onChange(of: username) { _, v in scheduleCheck(v) }
                if let usernameStatus {
                    Label(usernameStatus, systemImage: usernameOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.resky(.caption)).foregroundStyle(usernameOK ? Color.reskyGreenDark : Color.reskyDND)
                }
            }
            field("Email address") {
                TextField("you@example.com", text: $email)
                    .textFieldStyle(ReSkyTextFieldStyle())
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            field("Password") {
                SecureField("", text: $password).textFieldStyle(ReSkyTextFieldStyle()).textContentType(.newPassword)
            }
            field("Confirm password") {
                SecureField("", text: $confirm).textFieldStyle(ReSkyTextFieldStyle()).textContentType(.newPassword)
                PasswordChecklist(password: password, confirm: confirm)
            }
            field("Date of birth") {
                DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact)
                if !ageOK {
                    Text("You must be at least 13 to use ReSky.").font(.resky(.caption)).foregroundStyle(Color.reskyDND)
                }
            }
            Toggle(isOn: $agreed) {
                Text(LocalizedStringKey(agreementText))
                    .font(.resky(.footnote))
            }
            .toggleStyle(.switch).tint(.reskyGreen)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.resky(.footnote)).foregroundStyle(Color.reskyDND)
            }
            Button { Task { await submit() } } label: {
                HStack { if busy { ProgressView().tint(.white) }; Text("Create account") }
            }
            .buttonStyle(ClassicButtonStyle(color: .reskyGreen))
            .disabled(!canSubmit)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.95)))
        .shadow(color: Color(hex: "#0B6FA8").opacity(0.25), radius: 14, y: 6)
        .foregroundStyle(Color(hex: "#1B2A36"))
    }

    @ViewBuilder
    private func field<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.resky(.caption, weight: .semibold)).foregroundStyle(Color(hex: "#4A6577"))
            content()
        }
    }

    private func scheduleCheck(_ value: String) {
        checkTask?.cancel()
        usernameOK = false
        if let problem = UsernameRules.formatProblem(value) {
            usernameStatus = value.isEmpty ? nil : problem
            return
        }
        usernameStatus = "Checking…"
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            do {
                let result: String = try await supabase.rpc("check_username", params: ["candidate": value.lowercased()]).execute().value
                guard !Task.isCancelled else { return }
                usernameOK = result == "ok"
                usernameStatus = result == "ok" ? "Available" : (ReSkyError.codes["username_\(result)"] ?? "Not available")
            } catch {
                usernameStatus = "Couldn't check right now"
            }
        }
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let signedIn = try await session.signUp(displayName: displayName.trimmingCharacters(in: .whitespaces),
                                                    username: username, email: email.trimmingCharacters(in: .whitespaces),
                                                    password: password, dob: dob)
            Haptics.success()
            if !signedIn { onCheckEmail(email) }
        } catch {
            let text = String(describing: error)
            if text.contains("already registered") || text.contains("already been registered") {
                self.error = "Couldn't create the account. If you already have one, try signing in or resetting your password."
            } else if text.contains("Database error") {
                self.error = "That username or display name isn't allowed. Please choose another."
            } else {
                self.error = ReSkyError.message(error)
            }
            SoundManager.shared.play(.error)
        }
    }
}
