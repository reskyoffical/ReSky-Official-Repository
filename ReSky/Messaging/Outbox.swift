import Foundation
import Network
import SwiftData
import Supabase

/// Reliable delivery: every outgoing message is written to the outbox first, then
/// uploaded. Message ids are generated on the device, so retries never duplicate.
@MainActor
final class Outbox: ObservableObject {
    static let shared = Outbox()
    @Published private(set) var pendingIDs: Set<UUID> = []
    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()
    private var flushing = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline { await self.flush() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "resky.network"))
        refreshPending()
    }

    func refreshPending() {
        let items = (try? LocalStore.context.fetch(FetchDescriptor<OutboxItem>())) ?? []
        pendingIDs = Set(items.map(\.id))
    }

    func pending(for conversation: UUID) -> [ChatMessage] {
        let items = (try? LocalStore.context.fetch(FetchDescriptor<OutboxItem>(
            predicate: #Predicate { $0.conversationId == conversation },
            sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let dec = JSONDecoder()
        return items.compactMap { item -> ChatMessage? in
            guard let m = try? dec.decode(NewMessage.self, from: item.payload) else { return nil }
            return ChatMessage(id: m.id, conversationId: m.conversationId, senderId: m.senderId, kind: m.kind, body: m.body,
                               attachmentPath: m.attachmentPath, attachmentMeta: m.attachmentMeta, replyTo: m.replyTo,
                               forwardedFrom: m.forwardedFrom, createdAt: ISO8601DateFormatter().string(from: item.createdAt),
                               editedAt: nil, deletedAt: nil)
        }
    }

    /// Queue a message (and optional local attachment file) and try to send immediately.
    func enqueue(_ message: NewMessage, attachment: (data: Data, contentType: String)? = nil) async {
        var localPath: String?
        if let attachment {
            let url = LocalStore.attachmentsDir.appendingPathComponent(message.id.uuidString)
            try? attachment.data.write(to: url, options: .atomic)
            localPath = url.lastPathComponent
        }
        guard let payload = try? JSONEncoder().encode(message) else { return }
        LocalStore.context.insert(OutboxItem(id: message.id, conversationId: message.conversationId, payload: payload,
                                             localFilePath: localPath, contentType: attachment?.contentType))
        try? LocalStore.context.save()
        refreshPending()
        await flush()
    }

    func flush() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        let items = (try? LocalStore.context.fetch(FetchDescriptor<OutboxItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for item in items {
            do {
                try await deliver(item)
                if let p = item.localFilePath {
                    try? FileManager.default.removeItem(at: LocalStore.attachmentsDir.appendingPathComponent(p))
                }
                LocalStore.context.delete(item)
                try? LocalStore.context.save()
            } catch {
                item.attempts += 1
                try? LocalStore.context.save()
                // Permanent errors (permission/validation) are dropped after several tries
                if item.attempts >= 8 {
                    LocalStore.context.delete(item)
                    try? LocalStore.context.save()
                    SoundManager.shared.play(.error)
                }
                if (error as? URLError) != nil { break } // offline: stop and wait for connectivity
            }
        }
        refreshPending()
    }

    private func deliver(_ item: OutboxItem) async throws {
        let message = try JSONDecoder().decode(NewMessage.self, from: item.payload)
        if let p = item.localFilePath, let path = message.attachmentPath {
            let data = try Data(contentsOf: LocalStore.attachmentsDir.appendingPathComponent(p))
            try await TransferService.upload(bucket: "media", path: path, data: data,
                                             contentType: item.contentType ?? "application/octet-stream", id: message.id)
            if let mime = item.contentType, mime.hasPrefix("image/") {
                await ImageLoader.shared.store(data, bucket: "media", path: path)
            }
        }
        try await supabase.from("messages").upsert(message, onConflict: "id", ignoreDuplicates: true).execute()
    }

    func retry(_ id: UUID) async {
        await flush()
    }

    func discard(_ id: UUID) {
        let items = (try? LocalStore.context.fetch(FetchDescriptor<OutboxItem>(predicate: #Predicate { $0.id == id }))) ?? []
        items.forEach { LocalStore.context.delete($0) }
        try? LocalStore.context.save()
        refreshPending()
    }
}
