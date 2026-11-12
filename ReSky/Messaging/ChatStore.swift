import Foundation
import Supabase
import UniformTypeIdentifiers

/// State for one open conversation: history, realtime updates, typing, receipts, reactions.
@MainActor
final class ChatStore: ObservableObject {
    let conversationId: UUID
    @Published var messages: [ChatMessage] = []
    @Published var reactions: [UUID: [Reaction]] = [:]
    @Published var members: [MemberState] = []
    @Published var typingUsers: [UUID: Date] = [:]
    @Published var isGroup = false
    @Published var title: String?
    @Published var hasMore = true
    @Published var loadError: String?

    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []
    private var lastTypingSent = Date.distantPast

    init(conversationId: UUID) { self.conversationId = conversationId }

    var me: UUID? { SessionStore.shared.userId }
    var otherMember: UUID? { members.first { $0.userId != me }?.userId }

    func open() async {
        messages = merge(LocalStore.cached(conversation: conversationId), Outbox.shared.pending(for: conversationId))
        await loadMeta()
        await loadLatest()
        await subscribe()
        await markRead()
    }

    func close() {
        tasks.forEach { $0.cancel() }
        tasks = []
        if let channel { Task { await supabase.removeChannel(channel) } }
        channel = nil
    }

    private func loadMeta() async {
        struct Conv: Decodable { let is_group: Bool; let title: String? }
        if let c: Conv = try? await supabase.from("conversations").select("is_group, title")
            .eq("id", value: conversationId.lc).single().execute().value {
            isGroup = c.is_group
            title = c.title
        }
        members = (try? await supabase.from("conversation_members").select()
            .eq("conversation_id", value: conversationId.lc).execute().value) ?? []
        await ContactsStore.shared.ensureProfiles(members.map(\.userId))
    }

    func loadLatest() async {
        do {
            let rows: [ChatMessage] = try await supabase.from("messages").select()
                .eq("conversation_id", value: conversationId.lc)
                .order("created_at", ascending: false).limit(60).execute().value
            hasMore = rows.count == 60
            LocalStore.cache(rows)
            messages = merge(messages.filter { m in !rows.contains { $0.id == m.id } }, rows)
            await loadReactions(for: rows.map(\.id))
            loadError = nil
        } catch {
            loadError = messages.isEmpty ? "You're offline — showing saved messages." : nil
        }
    }

    func loadOlder() async {
        guard hasMore, let oldest = messages.first(where: { !Outbox.shared.pendingIDs.contains($0.id) }) else { return }
        let rows: [ChatMessage] = (try? await supabase.from("messages").select()
            .eq("conversation_id", value: conversationId.lc)
            .lt("created_at", value: oldest.createdAt)
            .order("created_at", ascending: false).limit(60).execute().value) ?? []
        hasMore = rows.count == 60
        LocalStore.cache(rows)
        messages = merge(messages, rows)
        await loadReactions(for: rows.map(\.id))
    }

    private func loadReactions(for ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        let rows: [Reaction] = (try? await supabase.from("message_reactions").select()
            .in("message_id", values: ids.map(\.lc)).execute().value) ?? []
        for id in ids { reactions[id] = rows.filter { $0.messageId == id } }
    }

    private func merge(_ a: [ChatMessage], _ b: [ChatMessage]) -> [ChatMessage] {
        var byId: [UUID: ChatMessage] = [:]
        for m in a { byId[m.id] = m }
        for m in b { byId[m.id] = m }
        return byId.values.sorted { $0.date < $1.date }
    }

    private func subscribe() async {
        let ch = supabase.channel("conv-\(conversationId.lc)")
        let filter = "conversation_id=eq.\(conversationId.lc)"
        let changes = ch.postgresChange(AnyAction.self, schema: "public", table: "messages", filter: filter)
        let memberChanges = ch.postgresChange(UpdateAction.self, schema: "public", table: "conversation_members", filter: filter)
        let reactionChanges = ch.postgresChange(AnyAction.self, schema: "public", table: "message_reactions")
        let typing = ch.broadcastStream(event: "typing")
        await ch.subscribe()
        channel = ch

        tasks.append(Task { [weak self] in
            for await change in changes {
                guard let self else { return }
                switch change {
                case .insert(let a):
                    if let m = try? a.decodeRecord(as: ChatMessage.self, decoder: JSONDecoder()) { await self.received(m) }
                case .update(let a):
                    if let m = try? a.decodeRecord(as: ChatMessage.self, decoder: JSONDecoder()) { self.upsert(m) }
                case .delete(let a):
                    if let s = a.oldRecord["id"]?.stringValue, let id = UUID(uuidString: s) { self.messages.removeAll { $0.id == id } }
                }
            }
        })
        tasks.append(Task { [weak self] in
            for await change in memberChanges {
                guard let self else { return }
                if let m = try? change.decodeRecord(as: MemberState.self, decoder: JSONDecoder()) {
                    if let i = self.members.firstIndex(where: { $0.userId == m.userId }) { self.members[i] = m } else { self.members.append(m) }
                }
            }
        })
        tasks.append(Task { [weak self] in
            for await change in reactionChanges {
                guard let self else { return }
                switch change {
                case .insert(let a):
                    if let r = try? a.decodeRecord(as: Reaction.self, decoder: JSONDecoder()), self.messages.contains(where: { $0.id == r.messageId }) {
                        var list = self.reactions[r.messageId] ?? []
                        if !list.contains(r) { list.append(r) }
                        self.reactions[r.messageId] = list
                    }
                case .delete:
                    await self.loadReactions(for: self.messages.suffix(80).map(\.id))
                default: break
                }
            }
        })
        tasks.append(Task { [weak self] in
            for await msg in typing {
                guard let self else { return }
                guard let payload = msg["payload"]?.objectValue,
                      let s = payload["user_id"]?.stringValue, let uid = UUID(uuidString: s), uid != self.me else { continue }
                self.typingUsers[uid] = Date()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let t = self.typingUsers[uid], Date().timeIntervalSince(t) >= 4.9 { self.typingUsers[uid] = nil }
            }
        })
    }

    private func received(_ m: ChatMessage) async {
        upsert(m)
        typingUsers[m.senderId ?? UUID()] = nil
        if m.senderId != me { await markRead() }
        await loadReactions(for: [m.id])
    }

    private func upsert(_ m: ChatMessage) {
        LocalStore.cache([m])
        if let i = messages.firstIndex(where: { $0.id == m.id }) { messages[i] = m } else { messages = merge(messages, [m]) }
    }

    func markRead() async {
        try? await supabase.rpc("mark_read", params: ["conv": conversationId.lc]).execute()
        await InboxStore.shared.refresh()
    }

    // MARK: Sending

    func sendText(_ text: String, replyTo: UUID?) async {
        guard let me else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let msg = NewMessage(id: UUID(), conversationId: conversationId, senderId: me, kind: "text",
                             body: String(trimmed.prefix(4000)), attachmentPath: nil, attachmentMeta: nil,
                             replyTo: replyTo, forwardedFrom: nil)
        appendLocal(msg)
        SoundManager.shared.play(.messageOut)
        await Outbox.shared.enqueue(msg)
    }

    func sendAttachment(data: Data, filename: String, contentType: UTType?, width: Double? = nil, height: Double? = nil) async {
        guard let me else { return }
        guard data.count <= AppConfig.maxAttachmentBytes else {
            SessionStore.shared.banner = "Files must be 50 MB or smaller."
            SoundManager.shared.play(.error)
            return
        }
        let type = contentType ?? UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data
        let kind: String = type.conforms(to: .image) ? "image" : type.conforms(to: .movie) ? "video" : type.conforms(to: .audio) ? "audio" : "file"
        let ext = type.preferredFilenameExtension ?? ((filename as NSString).pathExtension.isEmpty ? "bin" : (filename as NSString).pathExtension)
        let id = UUID()
        let path = "\(conversationId.lc)/\(id.lc).\(ext)"
        let meta = AttachmentMeta(name: filename, size: data.count, mime: type.preferredMIMEType ?? "application/octet-stream",
                                  width: width, height: height, duration: nil)
        let msg = NewMessage(id: id, conversationId: conversationId, senderId: me, kind: kind, body: nil,
                             attachmentPath: path, attachmentMeta: meta, replyTo: nil, forwardedFrom: nil)
        if kind == "image" { await ImageLoader.shared.store(data, bucket: "media", path: path) }
        appendLocal(msg)
        SoundManager.shared.play(.messageOut)
        await Outbox.shared.enqueue(msg, attachment: (data, meta.mime ?? "application/octet-stream"))
    }

    private func appendLocal(_ m: NewMessage) {
        let local = ChatMessage(id: m.id, conversationId: m.conversationId, senderId: m.senderId, kind: m.kind, body: m.body,
                                attachmentPath: m.attachmentPath, attachmentMeta: m.attachmentMeta, replyTo: m.replyTo,
                                forwardedFrom: m.forwardedFrom, createdAt: ISO8601DateFormatter().string(from: Date()),
                                editedAt: nil, deletedAt: nil)
        messages = merge(messages, [local])
    }

    func userIsTyping() {
        guard SessionStore.shared.settings?.typingEnabled ?? true, let me,
              Date().timeIntervalSince(lastTypingSent) > 3, let channel else { return }
        lastTypingSent = Date()
        let payload: [String: AnyJSON] = ["user_id": .string(me.lc)]
        Task { try? await channel.broadcast(event: "typing", message: payload) }
    }

    // MARK: Message actions

    func edit(_ m: ChatMessage, to text: String) async throws {
        struct P: Encodable { let msg: UUID; let new_body: String }
        try await supabase.rpc("edit_message", params: P(msg: m.id, new_body: text)).execute()
    }

    func delete(_ m: ChatMessage) async throws {
        if Outbox.shared.pendingIDs.contains(m.id) {
            Outbox.shared.discard(m.id)
            messages.removeAll { $0.id == m.id }
            return
        }
        try await supabase.rpc("delete_message", params: ["msg": m.id.lc]).execute()
    }

    func toggleReaction(_ emoji: String, on m: ChatMessage) async {
        guard let me else { return }
        let mine = reactions[m.id]?.contains { $0.userId == me && $0.emoji == emoji } ?? false
        if mine {
            try? await supabase.from("message_reactions").delete()
                .eq("message_id", value: m.id.lc).eq("user_id", value: me.lc).eq("emoji", value: emoji).execute()
            reactions[m.id]?.removeAll { $0.userId == me && $0.emoji == emoji }
        } else {
            let r = Reaction(messageId: m.id, userId: me, emoji: emoji)
            reactions[m.id, default: []].append(r)
            try? await supabase.from("message_reactions").insert(r).execute()
        }
        Haptics.selection()
    }

    static func forward(_ m: ChatMessage, to target: UUID) async throws {
        guard let me = SessionStore.shared.userId else { return }
        let newId = UUID()
        if let path = m.attachmentPath {
            let ext = (path as NSString).pathExtension
            let newPath = "\(target.lc)/\(newId.lc).\(ext)"
            try await TransferService.copy(bucket: "media", from: path, to: newPath)
            let msg = NewMessage(id: newId, conversationId: target, senderId: me, kind: m.kind, body: m.body,
                                 attachmentPath: newPath, attachmentMeta: m.attachmentMeta, replyTo: nil, forwardedFrom: m.id)
            try await supabase.from("messages").insert(msg).execute()
        } else {
            struct P: Encodable { let msg: UUID; let target_conv: UUID; let new_id: UUID }
            try await supabase.rpc("forward_message", params: P(msg: m.id, target_conv: target, new_id: newId)).execute()
        }
    }

    // MARK: Receipts

    /// "Seen" for my latest message in a 1:1 chat (respects the reader's privacy setting).
    var seenMessageId: UUID? {
        guard !isGroup, let other = members.first(where: { $0.userId != me }),
              let seenAt = other.sharedReadAt.map(DateParser.parse) else { return nil }
        return messages.last { $0.senderId == me && $0.date <= seenAt && !Outbox.shared.pendingIDs.contains($0.id) }?.id
    }
}
