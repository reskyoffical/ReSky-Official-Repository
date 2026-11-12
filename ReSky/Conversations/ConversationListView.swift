import SwiftUI

struct ConversationListView: View {
    var selection: Binding<UUID?>? = nil
    @StateObject private var inbox = InboxStore.shared
    @StateObject private var contacts = ContactsStore.shared
    @Environment(\.palette) private var palette
    @State private var showNewGroup = false
    @State private var showSearch = false

    var body: some View {
        List {
            if inbox.loaded && inbox.conversations.isEmpty {
                VStack(spacing: 10) {
                    ThemeHero().frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 14))
                    Text("No conversations yet").font(.resky(.headline))
                    Text("Open a contact to start chatting.").font(.resky(.subheadline)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(inbox.conversations) { c in
                row(c)
                    .swipeActions(edge: .trailing) {
                        Button { Task { await inbox.setMuted(c.id, !c.muted) } } label: {
                            Label(c.muted ? "Unmute" : "Mute", systemImage: c.muted ? "bell.fill" : "bell.slash.fill")
                        }.tint(.orange)
                        if c.isGroup {
                            Button(role: .destructive) { Task { await inbox.leave(c.id) } } label: { Label("Leave", systemImage: "rectangle.portrait.and.arrow.right") }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .refreshable { await inbox.refresh() }
        .navigationTitle("Conversations")
        .classicNavBar()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                Button { showNewGroup = true } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $showNewGroup) { NewGroupView { id in open(id) } }
        .sheet(isPresented: $showSearch) { SearchMessagesView { id in open(id) } }
        .task { await inbox.refresh() }
    }

    @ViewBuilder
    private func row(_ c: ConversationSummary) -> some View {
        let content = ConversationRow(summary: c, other: contacts.profile(c.otherUserId))
        if let selection {
            Button { selection.wrappedValue = c.id } label: { content }
                .buttonStyle(.plain)
                .listRowBackground(selection.wrappedValue == c.id ? Color.reskyBubble : Color.clear)
        } else {
            NavigationLink(value: ConversationRoute(id: c.id)) { content }
                .listRowBackground(Color.clear)
        }
    }

    private func open(_ id: UUID) {
        if let selection { selection.wrappedValue = id } else { SessionStore.shared.pendingConversation = id }
    }
}

struct ConversationRow: View {
    let summary: ConversationSummary
    let other: ProfileCard?

    var body: some View {
        HStack(spacing: 12) {
            if summary.isGroup {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Color(hex: "#8FD8F8"), .reskyBlue], startPoint: .top, endPoint: .bottom))
                    Image(systemName: "person.3.fill").foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
            } else {
                AvatarView(profile: other, size: 46)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.resky(.body, weight: summary.unreadCount > 0 ? .bold : .semibold)).lineLimit(1)
                    if summary.muted { Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                    Text(DateParser.shortTime(DateParser.parse(summary.lastMessageAt)))
                        .font(.resky(.caption)).foregroundStyle(summary.unreadCount > 0 ? Color.reskyBlue : .secondary)
                }
                HStack {
                    Text(preview).font(.resky(.subheadline)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if summary.unreadCount > 0 {
                        Text("\(summary.unreadCount)")
                            .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(summary.muted ? Color.reskyOffline : Color.reskyBlue))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var title: String {
        if summary.isGroup { return summary.title ?? "Group chat" }
        return other?.displayName ?? "Conversation"
    }

    private var preview: String {
        switch summary.lastKind {
        case "image": return "📷 Photo"
        case "video": return "🎬 Video"
        case "audio": return "🎵 Audio"
        case "file": return "📎 File"
        case nil: return "Say hello 👋"
        default: return summary.lastBody ?? "Message deleted"
        }
    }
}

struct NewGroupView: View {
    var onCreated: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var contacts = ContactsStore.shared
    @State private var title = ""
    @State private var selected: Set<UUID> = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section { TextField("Group name", text: $title) }
                Section("Members") {
                    ForEach(contacts.contacts) { p in
                        Button {
                            if selected.contains(p.id) { selected.remove(p.id) } else { selected.insert(p.id) }
                        } label: {
                            HStack {
                                ContactRowView(profile: p)
                                Image(systemName: selected.contains(p.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(p.id) ? Color.reskyBlue : .secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Color.reskyDND) } }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
                }
            }
        }
    }

    private func create() async {
        struct P: Encodable { let group_title: String; let member_ids: [UUID] }
        do {
            let id: UUID = try await supabase.rpc("create_group_conversation",
                                                  params: P(group_title: title, member_ids: Array(selected))).execute().value
            await InboxStore.shared.refresh()
            dismiss()
            onCreated(id)
        } catch {
            self.error = ReSkyError.message(error)
        }
    }
}

struct SearchMessagesView: View {
    var onOpen: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var contacts = ContactsStore.shared
    @State private var query = ""
    @State private var results: [ChatMessage] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List(results) { m in
                Button {
                    dismiss()
                    onOpen(m.conversationId)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(contacts.profile(m.senderId)?.displayName ?? "Someone").font(.resky(.caption, weight: .bold))
                            Spacer()
                            Text(DateParser.shortTime(m.date)).font(.resky(.caption)).foregroundStyle(.secondary)
                        }
                        Text(m.body ?? "").font(.resky(.subheadline)).lineLimit(3)
                    }
                }
            }
            .overlay { if searching { ProgressView() } else if results.isEmpty && !query.isEmpty { Text("No results").foregroundStyle(.secondary) } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search message history")
            .onSubmit(of: .search) { Task { await run() } }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func run() async {
        searching = true
        defer { searching = false }
        struct P: Encodable { let q: String; let max_results: Int }
        results = (try? await supabase.rpc("search_messages", params: P(q: query, max_results: 100)).execute().value) ?? []
        await contacts.ensureProfiles(results.compactMap(\.senderId))
    }
}
