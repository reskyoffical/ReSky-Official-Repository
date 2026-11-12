import SwiftUI
import Supabase

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.palette) private var palette

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    AvatarView(profile: session.me, size: 48)
                    VStack(alignment: .leading) {
                        HStack(spacing: 4) { Text(session.me?.displayName ?? "").font(.resky(.headline, weight: .bold)); RoleBadges(profile: session.me) }
                        Text("@\(session.me?.username ?? "")").font(.resky(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            if session.isFounder {
                Section {
                    NavigationLink { FounderSettingsView() } label: { Label("Founder Settings", systemImage: "crown.fill").foregroundStyle(Color.reskyGold) }
                }
            }
            if session.me?.isStaff == true {
                Section { NavigationLink { AdminDashboardView() } label: { Label("Admin dashboard", systemImage: "shield.lefthalf.filled") } }
            }
            Section("Account") {
                NavigationLink { AccountSecurityView() } label: { Label("Account & security", systemImage: "person.badge.key.fill") }
                NavigationLink { PlusPaywallView() } label: {
                    Label(session.isFounder ? "ReSky Plus (Founder — included)" : "ReSky Plus", systemImage: "sparkles")
                }
            }
            Section("Appearance") {
                NavigationLink { ThemePickerView() } label: {
                    HStack {
                        Label("Themes", systemImage: "paintbrush.fill")
                        Spacer()
                        Text(ThemeCatalog.theme(session.me?.themeId).name).foregroundStyle(.secondary)
                    }
                }
                NavigationLink { AppearanceSettingsView() } label: { Label("Accent colour, borders & decorations", systemImage: "paintpalette.fill") }
                NavigationLink { SoundSettingsView() } label: { Label("Sounds", systemImage: "speaker.wave.2.fill") }
            }
            Section("Notifications & privacy") {
                NavigationLink { NotificationPrivacyView() } label: { Label("Notifications & privacy", systemImage: "bell.badge.fill") }
                NavigationLink { BlockedUsersView() } label: { Label("Blocked users", systemImage: "hand.raised.fill") }
            }
            Section("About") {
                LabeledContent("Version", value: AppConfig.appVersion)
                Link("Terms of Use", destination: AppConfig.termsURL)
                Link("Privacy Policy", destination: AppConfig.privacyURL)
                NavigationLink("Security & encryption") { EncryptionInfoView() }
            }
            Section {
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            }
        }
        .navigationTitle("Settings")
        .classicNavBar()
    }
}

struct AppearanceSettingsView: View {
    var body: some View { EditProfileView() }
}

struct SoundSettingsView: View {
    @AppStorage("sound.master") private var master = 0.8
    @AppStorage("sound.notification") private var notification = 1.0
    @AppStorage("sound.call") private var call = 1.0
    @AppStorage("sound.ui") private var ui = 0.6
    @State private var refresh = false
    @AppStorage("sound.ignoreSilentSwitch") private var playInSilent = true

    var body: some View {
        Form {
            Section {
                Toggle("Play sounds in silent mode", isOn: $playInSilent)
                    .onChange(of: playInSilent) { _, _ in SoundManager.shared.configureSession() }
            } footer: {
                Text("When off, ReSky sounds are muted while your iPhone's ring/silent switch is on silent.")
            }
            Section("Volume") {
                slider("Master", $master)
                slider("Notifications & messages", $notification)
                slider("Calls", $call)
                slider("Interface", $ui)
            }
            Section {
                ForEach(SoundManager.Sound.allCases) { s in
                    HStack {
                        Toggle(s.label, isOn: Binding(
                            get: { _ = refresh; return SoundManager.shared.isEnabled(s) },
                            set: { UserDefaults.standard.set($0, forKey: s.enabledKey); refresh.toggle() }))
                        Button { SoundManager.shared.play(s) } label: { Image(systemName: "play.circle") }.buttonStyle(.borderless)
                    }
                }
            } header: { Text("Individual sounds") } footer: {
                Text("Turn off any sound you don't want. The startup intro plays once each time the app opens.")
            }
        }
        .navigationTitle("Sounds")
    }

    private func slider(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.resky(.subheadline))
            Slider(value: value, in: 0...1, onEditingChanged: { editing in if !editing { SoundManager.shared.play(.notification) } })
        }
    }
}

struct NotificationPrivacyView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var s: AccountPrivate?
    @State private var visibility = "everyone"
    @State private var error: String?

    var body: some View {
        Form {
            if s != nil {
                Section("Notifications") {
                    toggle("Message notifications", \.notifyMessages)
                    toggle("Call notifications", \.notifyCalls)
                    toggle("Contact online/offline alerts", \.notifyContactStatus)
                    toggle("Notification sounds", \.notifySounds)
                    toggle("Show message previews", \.showPreviews)
                }
                Section("Privacy") {
                    toggle("Show when I'm online", \.onlineVisible)
                    toggle("Send read receipts", \.readReceiptsEnabled)
                    toggle("Send typing indicators", \.typingEnabled)
                    Picker("Who can see my full profile", selection: $visibility) {
                        Text("Everyone").tag("everyone")
                        Text("Contacts only").tag("contacts")
                    }
                    .onChange(of: visibility) { _, _ in Task { await save() } }
                }
                Section("Your data") {
                    Text("Messages, media and call history are stored on ReSky's servers so they sync across your devices. Deleting your account permanently removes them.")
                        .font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("Delete account…") { AccountSecurityView() }
                }
                if let error { Section { Text(error).foregroundStyle(Color.reskyDND) } }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Notifications & privacy")
        .task {
            s = session.settings
            visibility = session.ownRow?.profileVisibility ?? "everyone"
        }
    }

    private func toggle(_ title: String, _ key: WritableKeyPath<AccountPrivate, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { s?[keyPath: key] ?? true },
            set: { v in s?[keyPath: key] = v; Task { await save() } }))
        .tint(.reskyGreen)
    }

    private func save() async {
        guard let s else { return }
        struct P: Encodable {
            let p_read_receipts: Bool, p_typing: Bool, p_online_visible: Bool, p_profile_visibility: String
            let p_notify_messages: Bool, p_notify_calls: Bool, p_notify_contact_status: Bool, p_notify_sounds: Bool, p_show_previews: Bool
        }
        do {
            try await supabase.rpc("update_privacy", params: P(
                p_read_receipts: s.readReceiptsEnabled, p_typing: s.typingEnabled, p_online_visible: s.onlineVisible,
                p_profile_visibility: visibility, p_notify_messages: s.notifyMessages, p_notify_calls: s.notifyCalls,
                p_notify_contact_status: s.notifyContactStatus, p_notify_sounds: s.notifySounds, p_show_previews: s.showPreviews)).execute()
            await session.loadProfile()
        } catch {
            self.error = ReSkyError.message(error)
        }
    }
}

struct EncryptionInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("How ReSky protects your data").font(.resky(.title3, weight: .bold))
                Text("• All traffic between the app and ReSky's servers uses HTTPS/TLS.\n• Voice and video calls are encrypted in transit with WebRTC (DTLS-SRTP) via LiveKit.\n• Messages and files are encrypted at rest by our hosting provider (Supabase / AWS).\n• Passwords are hashed by Supabase Auth (bcrypt); they are never stored in plain text.\n• Sign-in tokens are kept in the iOS Keychain.\n\nReSky is NOT end-to-end encrypted: messages are stored on the server so they can sync across your devices and be reviewed when reported. Don't send anything you wouldn't want stored on a server.")
                    .font(.resky(.body))
            }
            .padding()
        }
        .navigationTitle("Security")
    }
}
