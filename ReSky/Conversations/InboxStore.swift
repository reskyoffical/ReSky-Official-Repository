import Foundation
import Supabase

/// Conversation list + global realtime feed of new messages (for sounds, unread badges).
@MainActor
final class InboxStore: ObservableObject {
    static let shared = InboxStore()
    @Published var conversations: [ConversationSummary] = []
    @Published var loaded = false
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    var totalUnread: Int { conversations.filter { !$0.muted }.reduce(0) { $0 + $1.unreadCount } }

    func start() {
        Task { await refresh(); await subscribe() }
    }

    func stop() {
        listenTask?.cancel()
        if let channel { Task { await supabase.removeChannel(channel) } }
        channel = nil
        conversations = []
        loaded = false
    }

    func refresh() async {
        do {
            let rows: [ConversationSummary] = try await supabase.rpc("my_conversations").execute().value
            conversations = rows
            loaded = true
            await ContactsStore.shared.ensureProfiles(rows.compactMap(\.otherUserId) + rows.compactMap(\.lastSenderId))
        } catch {
            loaded = true
        }
    }

    private func subscribe() async {
        let ch = supabase.channel("inbox-\(SessionStore.shared.userId?.lc ?? "anon")")
        // No filter: Realtime applies RLS, so we only receive messages from our conversations.
        let inserts = ch.postgresChange(InsertAction.self, schema: "public", table: "messages")
        await ch.subscribe()
        channel = ch
        listenTask = Task { [weak self] in
            for await insert in inserts {
                guard let self else { return }
                guard let msg = try? insert.decodeRecord(as: ChatMessage.self, decoder: JSONDecoder()) else { continue }
                await self.handleIncoming(msg)
            }
        }
    }

    private func handleIncoming(_ msg: ChatMessage) async {
        let mine = msg.senderId == SessionStore.shared.userId
        let muted = conversations.first { $0.id == msg.conversationId }?.muted ?? false
        if !mine && ActiveChat.current != msg.conversationId && !muted && SessionStore.shared.me?.status != .dnd {
            SoundManager.shared.play(.messageIn)
            Haptics.tap()
        }
        await refresh()
    }

    func setMuted(_ id: UUID, _ muted: Bool) async {
        guard let uid = SessionStore.shared.userId else { return }
        try? await supabase.from("conversation_members").update(["muted": muted])
            .eq("conversation_id", value: id.lc).eq("user_id", value: uid.lc).execute()
        await refresh()
    }

    func leave(_ id: UUID) async {
        try? await supabase.rpc("leave_conversation", params: ["conv": id.lc]).execute()
        await refresh()
    }
}
