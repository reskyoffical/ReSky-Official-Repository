import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ConversationView: View {
    let conversationId: UUID
    @StateObject private var store: ChatStore
    @StateObject private var contacts = ContactsStore.shared
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var calls: CallManager
    @EnvironmentObject private var outbox: Outbox
    @Environment(\.palette) private var palette

    @State private var draft = ""
    @State private var replyTo: ChatMessage?
    @State private var editing: ChatMessage?
    @State private var forwarding: ChatMessage?
    @State private var reporting: ChatMessage?
    @State private var viewerMessage: ChatMessage?
    @State private var showProfile = false
    @State private var actionError: String?

    init(conversationId: UUID) {
        self.conversationId = conversationId
        _store = StateObject(wrappedValue: ChatStore(conversationId: conversationId))
    }

    private var other: ProfileCard? { contacts.profile(store.otherMember) }

    var body: some View {
        VStack(spacing: 0) {
            if let err = store.loadError {
                Text(err).font(.resky(.caption)).frame(maxWidth: .infinity).padding(6).background(Color.reskyAway.opacity(0.3))
            }
            if !outbox.isOnline {
                Label("Offline — messages will send when you reconnect", systemImage: "wifi.slash")
                    .font(.resky(.caption)).frame(maxWidth: .infinity).padding(6).background(Color.reskyAway.opacity(0.3))
            }
            messageList
            typingLine
            Composer(text: $draft, replyTo: $replyTo, editing: $editing, store: store, otherName: other?.displayName)
        }
        .background(
            ZStack {
                palette.background
                ThemeBackdrop(kind: palette.backdrop).opacity(palette.isDark ? 0.35 : 0.22)
            }
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
        .classicNavBar()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showProfile = !store.isGroup } label: {
                    HStack(spacing: 8) {
                        if !store.isGroup { AvatarView(profile: other, size: 30) }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(store.isGroup ? (store.title ?? "Group chat") : (other?.displayName ?? ""))
                                .font(.resky(.headline, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                            Text(subtitle).font(.resky(.caption2)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if let other, !store.isGroup {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { calls.startCall(to: other, video: false) } label: { Image(systemName: "phone.fill") }
                    Button { calls.startCall(to: other, video: true) } label: { Image(systemName: "video.fill") }
                }
            }
        }
        .sheet(isPresented: $showProfile) { if let other { NavigationStack { ProfileDetailView(profile: other) } } }
        .sheet(item: $forwarding) { m in ForwardSheet(message: m) }
        .sheet(item: $reporting) { m in ReportSheet(targetUser: m.senderId, message: m.id, category: "message") }
        .fullScreenCover(item: $viewerMessage) { m in MediaViewer(message: m) }
        .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(actionError ?? "") }
        .task { await store.open() }
        .onAppear { ActiveChat.current = conversationId }
        .onDisappear {
            if ActiveChat.current == conversationId { ActiveChat.current = nil }
            store.close()
        }
    }

    private var subtitle: String {
        if store.isGroup { return "\(store.members.count) members" }
        guard let other else { return "" }
        if other.status == .offline, let seen = other.lastSeenAt {
            return "Last seen \(DateParser.parse(seen).formatted(.relative(presentation: .named)))"
        }
        return other.statusMessage?.isEmpty == false ? other.statusMessage! : other.status.label
    }

    private var typingLine: some View {
        let names = store.typingUsers.keys.compactMap { contacts.profile($0)?.displayName }
        return Group {
            if !names.isEmpty {
                HStack(spacing: 6) {
                    TypingDots()
                    Text(names.count == 1 ? "\(names[0]) is typing…" : "Several people are typing…")
                        .font(.resky(.caption)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: names)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                if store.hasMore && !store.messages.isEmpty {
                    Button("Load earlier messages") { Task { await store.loadOlder() } }
                        .font(.resky(.footnote)).frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, m in
                    let prev = index > 0 ? store.messages[index - 1] : nil
                    VStack(spacing: 4) {
                        if prev == nil || !Calendar.current.isDate(prev!.date, inSameDayAs: m.date) {
                            DayDivider(date: m.date)
                        }
                        MessageBubble(
                            message: m,
                            sender: contacts.profile(m.senderId),
                            isMine: m.senderId == session.userId,
                            showHeader: prev?.senderId != m.senderId || m.date.timeIntervalSince(prev?.date ?? .distantPast) > 300,
                            replied: m.replyTo.flatMap { id in store.messages.first { $0.id == id } },
                            reactions: store.reactions[m.id] ?? [],
                            pending: outbox.pendingIDs.contains(m.id),
                            seen: store.seenMessageId == m.id,
                            onReact: { e in Task { await store.toggleReaction(e, on: m) } },
                            onOpenMedia: { viewerMessage = m }
                        )
                        .contextMenu { menu(for: m) }
                    }
                    .id(m.id)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                    .swipeActions(edge: .leading) {
                        if !m.isDeleted {
                            Button { replyTo = m; Haptics.tap() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left.fill") }
                                .tint(.reskyBlue)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func menu(for m: ChatMessage) -> some View {
        if !m.isDeleted {
            ControlGroup {
                ForEach(["👍", "😂", "❤️", "😮", "😢", "🎉"], id: \.self) { e in
                    Button(e) { Task { await store.toggleReaction(e, on: m) } }
                }
            }
            Button { replyTo = m } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
            if let body = m.body { Button { UIPasteboard.general.string = body } label: { Label("Copy", systemImage: "doc.on.doc") } }
            Button { forwarding = m } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
            if m.senderId == session.userId {
                if m.kind == "text" {
                    Button { editing = m; draft = m.body ?? "" } label: { Label("Edit", systemImage: "pencil") }
                }
                Button(role: .destructive) {
                    Task { do { try await store.delete(m) } catch { actionError = ReSkyError.message(error) } }
                } label: { Label("Delete", systemImage: "trash") }
            } else {
                Button(role: .destructive) { reporting = m } label: { Label("Report", systemImage: "exclamationmark.bubble") }
            }
        }
    }
}

struct DayDivider: View {
    let date: Date
    var body: some View {
        HStack {
            Rectangle().fill(Color.reskyBlue.opacity(0.2)).frame(height: 1)
            Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(date: .abbreviated, time: .omitted))
                .font(.resky(.caption2, weight: .semibold)).foregroundStyle(.secondary)
            Rectangle().fill(Color.reskyBlue.opacity(0.2)).frame(height: 1)
        }
        .padding(.vertical, 6)
    }
}

struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle().fill(Color.reskyBlue).frame(width: 5, height: 5)
                    .opacity(on ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .onAppear { on = true }
    }
}
