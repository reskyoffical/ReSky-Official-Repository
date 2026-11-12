import Foundation
import SwiftData

/// Offline cache of messages so conversations open instantly and work without a connection.
@Model
final class CachedMessage {
    @Attribute(.unique) var id: UUID
    var conversationId: UUID
    var createdAt: Date
    var payload: Data

    init(id: UUID, conversationId: UUID, createdAt: Date, payload: Data) {
        self.id = id
        self.conversationId = conversationId
        self.createdAt = createdAt
        self.payload = payload
    }
}

/// Messages written while offline (or whose send failed) waiting to be delivered.
@Model
final class OutboxItem {
    @Attribute(.unique) var id: UUID
    var conversationId: UUID
    var createdAt: Date
    var payload: Data
    /// Persistent local copy of an attachment that still needs uploading (Application Support, not tmp).
    var localFilePath: String?
    var contentType: String?
    var attempts: Int

    init(id: UUID, conversationId: UUID, payload: Data, localFilePath: String? = nil, contentType: String? = nil) {
        self.id = id
        self.conversationId = conversationId
        self.createdAt = Date()
        self.payload = payload
        self.localFilePath = localFilePath
        self.contentType = contentType
        self.attempts = 0
    }
}

@MainActor
enum LocalStore {
    static let container: ModelContainer = {
        let schema = Schema([CachedMessage.self, OutboxItem.self])
        if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema)) { return c }
        // Fallback to in-memory if the on-disk store is unreadable (e.g. after a schema change)
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }()

    static var context: ModelContext { container.mainContext }

    static func cache(_ messages: [ChatMessage]) {
        let enc = JSONEncoder()
        for m in messages {
            guard let data = try? enc.encode(m) else { continue }
            let id = m.id
            let existing = try? context.fetch(FetchDescriptor<CachedMessage>(predicate: #Predicate { $0.id == id }))
            if let row = existing?.first {
                row.payload = data
            } else {
                context.insert(CachedMessage(id: m.id, conversationId: m.conversationId, createdAt: m.date, payload: data))
            }
        }
        try? context.save()
    }

    static func cached(conversation: UUID, limit: Int = 200) -> [ChatMessage] {
        var d = FetchDescriptor<CachedMessage>(predicate: #Predicate { $0.conversationId == conversation },
                                              sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        d.fetchLimit = limit
        let rows = (try? context.fetch(d)) ?? []
        let dec = JSONDecoder()
        return rows.compactMap { try? dec.decode(ChatMessage.self, from: $0.payload) }.reversed()
    }

    static func clearAll() {
        try? context.delete(model: CachedMessage.self)
        try? context.delete(model: OutboxItem.self)
        try? context.save()
    }

    static var attachmentsDir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}
