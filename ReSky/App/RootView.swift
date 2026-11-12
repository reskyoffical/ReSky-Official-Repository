import SwiftUI

struct RootView: View {
    private var palette: ReSkyPalette {
        let id = session.me.map { ThemeCatalog.effectiveId(for: $0) } ?? cachedThemeId
        return ReSkyPalette.forTheme(id, accentHex: session.me?.accentColor)
    }

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var calls: CallManager
    @AppStorage("resky.themeId") private var cachedThemeId = ThemeCatalog.defaultId

    var body: some View {
        ZStack {
            Group {
                if !AppConfig.isConfigured {
                    NotConfiguredView()
                } else {
                    switch session.phase {
                    case .loading:
                        CloudBackground()
                    case .signedOut:
                        AuthFlowView()
                    case .needsMFA:
                        MFAChallengeView()
                    case .passwordRecovery:
                        ResetPasswordView()
                    case .signedIn:
                        MainShell()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: session.phase)

            if calls.activeCall != nil || calls.incoming != nil {
                CallScreen().transition(.move(edge: .bottom)).zIndex(5)
            }
        }
        .environment(\.palette, palette)
        .preferredColorScheme(palette.colorScheme)
        .onChange(of: session.me?.themeId) { _, _ in
            if let me = session.me { cachedThemeId = ThemeCatalog.effectiveId(for: me) }
        }
        .tint(Color(hex: session.me?.accentColor ?? "#00AFF0"))
        .onAppear {
            session.start()
            SoundManager.shared.play(.startup)
        }
        .overlay(alignment: .top) {
            if let text = session.banner {
                Text(text)
                    .font(.resky(.footnote, weight: .medium)).foregroundStyle(.white)
                    .padding(12).frame(maxWidth: .infinity)
                    .background(Color.reskyDeepBlue.opacity(0.95))
                    .onTapGesture { session.banner = nil }
                    .task { try? await Task.sleep(nanoseconds: 6_000_000_000); session.banner = nil }
            }
        }
    }
}

/// Shown if the build was made without Supabase settings (see README → Codemagic variables).
struct NotConfiguredView: View {
    var body: some View {
        ZStack {
            CloudBackground()
            VStack(spacing: 12) {
                Image("ReSkyLogo").resizable().scaledToFit().frame(maxWidth: 200)
                Text("Backend not configured").font(.resky(.title3, weight: .bold))
                Text("This build has no SUPABASE_HOST / SUPABASE_ANON_KEY. Add them to the resky_config group in Codemagic and rebuild.")
                    .font(.resky(.subheadline)).multilineTextAlignment(.center)
            }
            .padding(24).reskyPanel().padding(24)
        }
    }
}

/// iPhone: bottom tabs. iPad: classic desktop-style split view.
struct MainShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        if sizeClass == .regular {
            IPadShell()
        } else {
            PhoneTabs()
        }
    }
}

enum AppTab: Hashable { case contacts, conversations, calls, profile, settings }

struct ConversationRoute: Hashable { let id: UUID }

struct PhoneTabs: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var inbox = InboxStore.shared
    @State private var tab: AppTab = .conversations
    @State private var chatPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { ContactsView(onOpenConversation: open) }
                .tabItem { Label("Contacts", systemImage: "person.2.fill") }.tag(AppTab.contacts)
            NavigationStack(path: $chatPath) {
                ConversationListView()
                    .navigationDestination(for: ConversationRoute.self) { ConversationView(conversationId: $0.id) }
            }
            .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }
            .badge(inbox.totalUnread)
            .tag(AppTab.conversations)
            NavigationStack { CallHistoryView() }
                .tabItem { Label("Calls", systemImage: "phone.fill") }.tag(AppTab.calls)
            NavigationStack { MyProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(AppTab.profile)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(AppTab.settings)
        }
        .onChange(of: tab) { _, _ in Haptics.selection(); SoundManager.shared.play(.click) }
        .onChange(of: session.pendingConversation) { _, id in
            guard let id else { return }
            open(id)
            session.pendingConversation = nil
        }
    }

    private func open(_ id: UUID) {
        tab = .conversations
        chatPath = NavigationPath()
        chatPath.append(ConversationRoute(id: id))
    }
}

struct IPadShell: View {
    @EnvironmentObject private var session: SessionStore
    enum Pane: String, CaseIterable { case contacts = "Contacts", recent = "Recent", calls = "Calls" }
    @State private var pane: Pane = .recent
    @State private var selected: UUID?
    @State private var showProfile = false
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Button { showProfile = true } label: {
                    HStack(spacing: 10) {
                        AvatarView(profile: session.me, size: 46)
                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                Text(session.me?.displayName ?? "").font(.resky(.headline, weight: .bold))
                                RoleBadges(profile: session.me)
                            }
                            Text(session.me?.statusMessage?.isEmpty == false ? session.me!.statusMessage! : "Set a status message")
                                .font(.resky(.caption)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(12)
                }
                .buttonStyle(.plain)
                Picker("", selection: $pane) {
                    ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(.horizontal, 12).padding(.bottom, 8)
                switch pane {
                case .contacts: ContactsView(onOpenConversation: { selected = $0 }, embedded: true)
                case .recent: ConversationListView(selection: $selected)
                case .calls: CallHistoryView()
                }
            }
            .navigationTitle("ReSky")
            .classicNavBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
        } detail: {
            if let selected {
                NavigationStack { ConversationView(conversationId: selected).id(selected) }
            } else {
                ThemeHero().ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showProfile) { NavigationStack { MyProfileView() } }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .onChange(of: session.pendingConversation) { _, id in
            if let id { selected = id; session.pendingConversation = nil }
        }
    }
}

struct RoleBadges: View {
    let profile: ProfileCard?
    var body: some View {
        HStack(spacing: 4) {
            if profile?.isFounder == true {
                Text("FOUNDER")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#FFD86B"), .reskyGold], startPoint: .top, endPoint: .bottom)))
                    .foregroundStyle(Color(hex: "#5A3A00"))
            } else if profile?.role == "moderator" {
                Text("MOD").font(.system(size: 9, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.reskyDeepBlue)).foregroundStyle(.white)
            }
            if profile?.isPlus == true && profile?.isFounder != true {
                Text("PLUS").font(.system(size: 9, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#5CD3FF"), .reskyBlue], startPoint: .top, endPoint: .bottom)))
                    .foregroundStyle(.white)
            }
        }
    }
}
