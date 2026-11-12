import SwiftUI

/// Classic sky-and-clouds sign-in screen with smooth switching to Create Account.
struct AuthFlowView: View {
    enum Screen { case signIn, create, forgot, checkEmail(String) }
    @State private var screen: Screen = .signIn
    @State private var forward = true

    var body: some View {
        ZStack {
            CloudBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Image("ReSkyLogo")
                        .resizable().scaledToFit()
                        .frame(maxWidth: 230)
                        .shadow(color: Color(hex: "#0B6FA8").opacity(0.35), radius: 8, y: 4)
                        .padding(.top, 36)
                    Text("The conversations never ended.")
                        .font(.resky(.subheadline, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

                    Group {
                        switch screen {
                        case .signIn:
                            SignInForm(onCreate: { go(.create) }, onForgot: { go(.forgot) })
                        case .create:
                            CreateAccountForm(onBack: { go(.signIn, back: true) }, onCheckEmail: { go(.checkEmail($0)) })
                        case .forgot:
                            ForgotPasswordForm(onBack: { go(.signIn, back: true) })
                        case .checkEmail(let email):
                            CheckEmailPanel(email: email, onBack: { go(.signIn, back: true) })
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                    .padding(.horizontal, 22)
                    .frame(maxWidth: 460)
                }
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func go(_ s: Screen, back: Bool = false) {
        forward = !back
        Haptics.selection()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { screen = s }
    }
}

struct SignInForm: View {
    @EnvironmentObject private var session: SessionStore
    var onCreate: () -> Void
    var onForgot: () -> Void
    @State private var identifier = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to ReSky").font(.resky(.title3, weight: .bold)).foregroundStyle(Color(hex: "#1B2A36"))
            VStack(alignment: .leading, spacing: 4) {
                Text("ReSky Name or email").font(.resky(.caption, weight: .semibold)).foregroundStyle(Color(hex: "#4A6577"))
                TextField("", text: $identifier)
                    .textFieldStyle(ReSkyTextFieldStyle())
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: 0).submitLabel(.next).onSubmit { focus = 1 }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Password").font(.resky(.caption, weight: .semibold)).foregroundStyle(Color(hex: "#4A6577"))
                SecureField("", text: $password)
                    .textFieldStyle(ReSkyTextFieldStyle())
                    .textContentType(.password)
                    .focused($focus, equals: 1).submitLabel(.go).onSubmit { Task { await submit() } }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.resky(.footnote)).foregroundStyle(Color.reskyDND)
            }
            Button { Task { await submit() } } label: {
                HStack { if busy { ProgressView().tint(.white) }; Text("Sign in") }
            }
            .buttonStyle(ClassicButtonStyle(color: .reskyGreen))
            .disabled(busy || identifier.isEmpty || password.isEmpty)

            Button("Create an account", action: onCreate).buttonStyle(ClassicButtonStyle(prominent: false))
            HStack {
                Spacer()
                Button("Forgot your password?", action: onForgot)
                    .font(.resky(.footnote, weight: .medium)).foregroundStyle(Color.reskyDeepBlue)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 1.5))
        .shadow(color: Color(hex: "#0B6FA8").opacity(0.25), radius: 14, y: 6)
    }

    private func submit() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.signIn(identifier: identifier.trimmingCharacters(in: .whitespaces), password: password)
            Haptics.success()
        } catch {
            self.error = ReSkyError.message(error)
            SoundManager.shared.play(.error)
            Haptics.error()
        }
    }
}

struct CheckEmailPanel: View {
    let email: String
    var onBack: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.badge.fill").font(.system(size: 44)).foregroundStyle(Color.reskyBlue)
            Text("Verify your email").font(.resky(.title3, weight: .bold))
            Text("We sent a verification link to \(email). Open it on this device to finish creating your account, then sign in.")
                .font(.resky(.subheadline)).multilineTextAlignment(.center).foregroundStyle(Color(hex: "#4A6577"))
            Button("Back to sign in", action: onBack).buttonStyle(ClassicButtonStyle())
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.95)))
    }
}

struct ForgotPasswordForm: View {
    @EnvironmentObject private var session: SessionStore
    var onBack: () -> Void
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reset your password").font(.resky(.title3, weight: .bold))
            if sent {
                Text("If an account exists for that email, a reset link is on its way. Open it on this device.")
                    .font(.resky(.subheadline)).foregroundStyle(Color(hex: "#4A6577"))
            } else {
                Text("Enter the email address on your account.").font(.resky(.subheadline)).foregroundStyle(Color(hex: "#4A6577"))
                TextField("Email", text: $email)
                    .textFieldStyle(ReSkyTextFieldStyle())
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Send reset link") {
                    Task { await session.sendPasswordReset(email: email); withAnimation { sent = true } }
                }
                .buttonStyle(ClassicButtonStyle())
                .disabled(!UsernameRules.isValidEmail(email))
            }
            Button("Back to sign in", action: onBack).buttonStyle(ClassicButtonStyle(prominent: false))
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.94)))
    }
}

/// Shown after opening a password-reset link.
struct ResetPasswordView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            CloudBackground()
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose a new password").font(.resky(.title3, weight: .bold))
                SecureField("New password", text: $password).textFieldStyle(ReSkyTextFieldStyle()).textContentType(.newPassword)
                SecureField("Confirm password", text: $confirm).textFieldStyle(ReSkyTextFieldStyle()).textContentType(.newPassword)
                PasswordChecklist(password: password, confirm: confirm)
                if let error { Text(error).font(.resky(.footnote)).foregroundStyle(Color.reskyDND) }
                Button("Save password") {
                    Task {
                        do { try await session.setNewPassword(password) } catch { self.error = ReSkyError.message(error) }
                    }
                }
                .buttonStyle(ClassicButtonStyle())
                .disabled(!UsernameRules.passwordProblems(password).isEmpty || password != confirm)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.95)))
            .padding(22)
            .frame(maxWidth: 460)
        }
    }
}

struct PasswordChecklist: View {
    let password: String
    let confirm: String
    var body: some View {
        let problems = UsernameRules.passwordProblems(password)
        VStack(alignment: .leading, spacing: 3) {
            ForEach(["8+ characters", "an uppercase letter", "a lowercase letter", "a number"], id: \.self) { item in
                Label(String(item.prefix(1)).uppercased() + String(item.dropFirst()), systemImage: problems.contains(item) ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(problems.contains(item) ? Color(hex: "#8DA2B2") : Color.reskyGreenDark)
            }
            if !confirm.isEmpty {
                Label("Passwords match", systemImage: password == confirm ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(password == confirm ? Color.reskyGreenDark : Color.reskyDND)
            }
        }
        .font(.resky(.caption))
    }
}

/// Second step when the account has two-factor authentication enabled.
struct MFAChallengeView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            CloudBackground()
            VStack(spacing: 14) {
                Image(systemName: "lock.shield.fill").font(.system(size: 44)).foregroundStyle(Color.reskyBlue)
                Text("Two-factor authentication").font(.resky(.title3, weight: .bold))
                Text("Enter the 6-digit code from your authenticator app.").font(.resky(.subheadline)).multilineTextAlignment(.center)
                TextField("123456", text: $code)
                    .textFieldStyle(ReSkyTextFieldStyle())
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(6)) }
                if let error { Text(error).font(.resky(.footnote)).foregroundStyle(Color.reskyDND) }
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do { try await session.verifyMFA(code: code) } catch { self.error = "That code didn't work. Try again."; Haptics.error() }
                    }
                } label: { HStack { if busy { ProgressView().tint(.white) }; Text("Verify") } }
                .buttonStyle(ClassicButtonStyle())
                .disabled(code.count != 6 || busy)
                Button("Sign out") { Task { await session.signOut() } }.font(.resky(.footnote))
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.95)))
            .padding(22)
            .frame(maxWidth: 460)
        }
    }
}
