import SwiftUI

struct ContactsView: View {
    var onOpenConversation: (UUID) -> Void
    var embedded = false
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var calls: CallManager
    @StateObject private var store = ContactsStore.shared
    @Environment(\.palette) private var palette
    @State private var search = ""
    @State private var showAdd = false
    @State private var viewing: ProfileCard?
    @State private var error: String?

    private var filtered: [ProfileCard] {
        guard !search.isEmpty else { return store.contacts }
        return store.contacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) || $0.username.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            if !embedded {
                Section { MyStatusHeader() }
                    .listRowBackground(palette.panel)
            }
            if !store.incoming.isEmpty {
                Section("Contact requests") {
                    ForEach(store.incoming) { p in
                        HStack {
                            AvatarView(profile: p, size: 36, showStatus: false)
                            VStack(alignment: .leading) {
                                Text(p.displayName).font(.resky(.body, weight: .semibold))
                                Text("@\(p.username) wants to add you").font(.resky(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { Task { await store.respond(p.id, accept: true); Haptics.success() } } label: {
                                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Color.reskyGreen)
                            }.buttonStyle(.plain)
                            Button { Task { await store.respond(p.id, accept: false) } } label: {
                                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Color.reskyOffline)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Section(store.contacts.isEmpty ? "" : "Contacts (\(store.contacts.filter { $0.status != .offline }.count)/\(store.contacts.count) online)") {
                if store.contacts.isEmpty && !store.loading {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus").font(.largeTitle).foregroundStyle(Color.reskyBlue)
                        Text("No contacts yet").font(.resky(.headline))
                        Text("Add friends by their ReSky Name.").font(.resky(.subheadline)).foregroundStyle(.secondary)
                        Button("Add a contact") { showAdd = true }.buttonStyle(ClassicButtonStyle()).frame(maxWidth: 220)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                ForEach(filtered) { p in
                    Button { Task { await open(p) } } label: { ContactRowView(profile: p) }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.sidebar)
                        .swipeActions(edge: .trailing) {
                            Button { calls.startCall(to: p, video: false) } label: { Label("Call", systemImage: "phone.fill") }.tint(.reskyGreen)
                            Button { calls.startCall(to: p, video: true) } label: { Label("Video", systemImage: "video.fill") }.tint(.reskyBlue)
                        }
                        .contextMenu {
                            Button { Task { await open(p) } } label: { Label("Send message", systemImage: "bubble.left.fill") }
                            Button { calls.startCall(to: p, video: false) } label: { Label("Call", systemImage: "phone.fill") }
                            Button { calls.startCall(to: p, video: true) } label: { Label("Video call", systemImage: "video.fill") }
                            Button { viewing = p } label: { Label("View profile", systemImage: "person.crop.circle") }
                            Divider()
                            Button(role: .destructive) { Task { await store.remove(p.id) } } label: { Label("Remove contact", systemImage: "person.badge.minus") }
                            Button(role: .destructive) { Task { await store.block(p.id) } } label: { Label("Block", systemImage: "hand.raised.fill") }
                        }
                }
            }
            if !store.outgoing.isEmpty {
                Section("Waiting for approval") {
                    ForEach(store.outgoing) { p in
                        HStack {
                            AvatarView(profile: p, size: 32, showStatus: false)
                            Text(p.displayName).font(.resky(.body))
                            Spacer()
                            Text("Pending").font(.resky(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .searchable(text: $search, prompt: "Search contacts")
        .refreshable { await store.refresh() }
        .navigationTitle("Contacts")
        .classicNavBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddContactView() }
        .sheet(item: $viewing) { p in NavigationStack { ProfileDetailView(profile: p) } }
        .alert("Couldn't open chat", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func open(_ p: ProfileCard) async {
        do { onOpenConversation(try await store.openDirect(p.id)) } catch { self.error = ReSkyError.message(error) }
    }
}

struct ContactRowView: View {
    let profile: ProfileCard
    var body: some View {
        HStack(spacing: 12) {
            AvatarView(profile: profile, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.displayName).font(.resky(.body, weight: .semibold)).lineLimit(1)
                    RoleBadges(profile: profile)
                }
                Text((profile.statusMessage?.isEmpty == false ? profile.statusMessage : profile.status.label) ?? "")
                    .font(.resky(.caption)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

/// Top-of-list "me" row with presence menu and status message, like classic Skype.
struct MyStatusHeader: View {
    @EnvironmentObject private var session: SessionStore
    @State private var editing = false
    @State private var text = ""

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(profile: session.me, size: 50)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(session.me?.displayName ?? "").font(.resky(.headline, weight: .bold))
                    RoleBadges(profile: session.me)
                }
                Menu {
                    ForEach([PresenceStatus.online, .away, .dnd, .invisible]) { s in
                        Button { Task { await session.setPresence(s) } } label: { Label(s.label, systemImage: "circle.fill") }
                    }
                } label: {
                    HStack(spacing: 4) {
                        StatusIcon(status: session.me?.status ?? .offline, size: 12)
                        Text(session.chosenPresence.label).font(.resky(.caption, weight: .medium))
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                }
                if editing {
                    TextField("What's on your mind?", text: $text)
                        .font(.resky(.caption)).submitLabel(.done)
                        .onSubmit { save() }
                } else {
                    Button { text = session.me?.statusMessage ?? ""; editing = true } label: {
                        Text(session.me?.statusMessage?.isEmpty == false ? session.me!.statusMessage! : "Set a status message…")
                            .font(.resky(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }

    private func save() {
        editing = false
        guard let uid = session.userId else { return }
        Task {
            do {
                try await supabase.from("profiles").update(["status_message": String(text.prefix(140))]).eq("id", value: uid.lc).execute()
                await session.loadProfile()
            } catch {
                session.banner = ReSkyError.message(error)
            }
        }
    }
}

struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ContactsStore.shared
    @State private var username = ""
    @State private var result: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ReSky Name", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text("Ask your friend for their ReSky Name — it's shown on their profile.")
                }
                if let result { Section { Text(result) } }
                Section {
                    Button { Task { await send() } } label: {
                        HStack { if busy { ProgressView() }; Text("Send contact request") }
                    }
                    .disabled(username.count < 3 || busy)
                }
            }
            .navigationTitle("Add a contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func send() async {
        busy = true
        defer { busy = false }
        do {
            switch try await store.sendRequest(username: username.trimmingCharacters(in: .whitespaces).lowercased()) {
            case "requested": result = "Request sent! They'll appear in your contacts once they accept."; Haptics.success()
            case "accepted": result = "You're now contacts!"; Haptics.success()
            default: result = "We couldn't find anyone with that ReSky Name."
            }
        } catch {
            result = ReSkyError.message(error)
        }
    }
}
