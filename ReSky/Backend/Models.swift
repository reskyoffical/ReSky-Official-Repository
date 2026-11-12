import Foundation
import Supabase

enum PresenceStatus: String, CaseIterable, Identifiable {
    case online, away, dnd, invisible, offline
    var id: String { rawValue }
    var label: String {
        switch self {
        case .online: return "Online"
        case .away: return "Away"
        case .dnd: return "Do Not Disturb"
        case .invisible: return "Invisible"
        case .offline: return "Offline"
        }
    }
}

struct ProfileCard: Codable, Identifiable, Hashable {
    let id: UUID
    var username: String
    var displayName: String
    var statusMessage: String?
    var presence: String
    var lastSeenAt: String?
    var role: String
    var isPlus: Bool
    var accentColor: String?
    var themeId: String
    var borderId: String
    var decorationId: String?
    var avatarPath: String?
    var avatarAnimated: Bool
    var bannerPath: String?
    var bannerAnimated: Bool
    var backgroundPath: String?
    var backgroundAnimated: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, presence, role
        case displayName = "display_name"
        case statusMessage = "status_message"
        case lastSeenAt = "last_seen_at"
        case isPlus = "is_plus"
        case accentColor = "accent_color"
        case themeId = "theme_id"
        case borderId = "border_id"
        case decorationId = "decoration_id"
        case avatarPath = "avatar_path"
        case avatarAnimated = "avatar_animated"
        case bannerPath = "banner_path"
        case bannerAnimated = "banner_animated"
        case backgroundPath = "background_path"
        case backgroundAnimated = "background_animated"
    }

    var isFounder: Bool { role == "founder" }
    var isStaff: Bool { role == "founder" || role == "moderator" }
    var status: PresenceStatus { PresenceStatus(rawValue: presence) ?? .offline }
}

struct AccountPrivate: Codable, Hashable {
    var userId: UUID
    var dateOfBirth: String?
    var suspensionReason: String?
    var notifyMessages: Bool
    var notifyCalls: Bool
    var notifyContactStatus: Bool
    var notifySounds: Bool
    var showPreviews: Bool
    var readReceiptsEnabled: Bool
    var typingEnabled: Bool
    var onlineVisible: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dateOfBirth = "date_of_birth"
        case suspensionReason = "suspension_reason"
        case notifyMessages = "notify_messages"
        case notifyCalls = "notify_calls"
        case notifyContactStatus = "notify_contact_status"
        case notifySounds = "notify_sounds"
        case showPreviews = "show_previews"
        case readReceiptsEnabled = "read_receipts_enabled"
        case typingEnabled = "typing_enabled"
        case onlineVisible = "online_visible"
    }
}

struct OwnProfileRow: Codable {
    var profileVisibility: String
    var suspendedUntil: String?
    var presence: String
    enum CodingKeys: String, CodingKey {
        case profileVisibility = "profile_visibility"
        case suspendedUntil = "suspended_until"
        case presence
    }
}

struct EntitlementRow: Codable {
    var plusExpiresAt: String?
    var autoRenew: Bool?
    var productId: String?
    enum CodingKeys: String, CodingKey {
        case plusExpiresAt = "plus_expires_at"
        case autoRenew = "auto_renew"
        case productId = "product_id"
    }
}

struct ContactRow: Codable, Hashable {
    let ownerId: UUID
    let contactId: UUID
    var status: String
    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id", contactId = "contact_id", status
    }
}

struct ConversationSummary: Codable, Identifiable, Hashable {
    let id: UUID
    var isGroup: Bool
    var title: String?
    var lastMessageAt: String
    var unreadCount: Int
    var lastBody: String?
    var lastKind: String?
    var lastSenderId: UUID?
    var otherUserId: UUID?
    var muted: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, muted
        case isGroup = "is_group"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
        case lastBody = "last_body"
        case lastKind = "last_kind"
        case lastSenderId = "last_sender_id"
        case otherUserId = "other_user_id"
    }
}

struct AttachmentMeta: Codable, Hashable {
    var name: String?
    var size: Int?
    var mime: String?
    var width: Double?
    var height: Double?
    var duration: Double?
}

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: UUID
    let conversationId: UUID
    var senderId: UUID?
    var kind: String
    var body: String?
    var attachmentPath: String?
    var attachmentMeta: AttachmentMeta?
    var replyTo: UUID?
    var forwardedFrom: UUID?
    var createdAt: String
    var editedAt: String?
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case attachmentPath = "attachment_path"
        case attachmentMeta = "attachment_meta"
        case replyTo = "reply_to"
        case forwardedFrom = "forwarded_from"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
    }

    var date: Date { DateParser.parse(createdAt) }
    var isDeleted: Bool { deletedAt != nil }
    var isMedia: Bool { ["image", "video", "audio", "file"].contains(kind) }
}

/// What the app sends when posting a message (the server sets sender and time).
struct NewMessage: Codable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let kind: String
    let body: String?
    let attachmentPath: String?
    let attachmentMeta: AttachmentMeta?
    let replyTo: UUID?
    let forwardedFrom: UUID?

    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case attachmentPath = "attachment_path"
        case attachmentMeta = "attachment_meta"
        case replyTo = "reply_to"
        case forwardedFrom = "forwarded_from"
    }
}

struct Reaction: Codable, Hashable {
    let messageId: UUID
    let userId: UUID
    let emoji: String
    enum CodingKeys: String, CodingKey { case messageId = "message_id", userId = "user_id", emoji }
}

struct MemberState: Codable, Hashable {
    let conversationId: UUID
    let userId: UUID
    var lastReadAt: String?
    var sharedReadAt: String?
    var muted: Bool
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id", userId = "user_id", muted
        case lastReadAt = "last_read_at", sharedReadAt = "shared_read_at"
    }
}

struct CallRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let callerId: UUID
    let calleeId: UUID
    let kind: String
    var status: String
    let createdAt: String
    var answeredAt: String?
    var endedAt: String?
    var durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind, status
        case callerId = "caller_id"
        case calleeId = "callee_id"
        case createdAt = "created_at"
        case answeredAt = "answered_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
    }
    var isVideo: Bool { kind == "video" }
}

struct CosmeticPayload: Codable, Hashable {
    var primary: String?
    var background: String?
    var bubble: String?
    var dark: Bool?
    var colors: [String]?
    var glow: Bool?
    var animated: Bool?
    var symbol: String?
    var glass: Bool?
    var gloss: Bool?
}

struct CosmeticItem: Codable, Identifiable, Hashable {
    var id: String
    var kind: String
    var name: String
    var isPremium: Bool
    var isReleased: Bool
    var founderOnly: Bool
    var payload: CosmeticPayload
    var sortOrder: Int
    enum CodingKeys: String, CodingKey {
        case id, kind, name, payload
        case isPremium = "is_premium"
        case isReleased = "is_released"
        case founderOnly = "founder_only"
        case sortOrder = "sort_order"
    }
}

struct ProfileAsset: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let kind: String
    let path: String
    let staticPath: String?
    let isAnimated: Bool
    let mimeType: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, kind, path
        case userId = "user_id"
        case staticPath = "static_path"
        case isAnimated = "is_animated"
        case mimeType = "mime_type"
        case createdAt = "created_at"
    }
}

struct DeviceRow: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var deviceName: String
    var platform: String
    var appVersion: String?
    var pushToken: String?
    var pushEnvironment: String?
    var lastActiveAt: String?
    enum CodingKeys: String, CodingKey {
        case id, platform
        case userId = "user_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
        case pushToken = "push_token"
        case pushEnvironment = "push_environment"
        case lastActiveAt = "last_active_at"
    }
}

struct ReportRow: Codable, Identifiable, Hashable {
    let id: UUID
    let reporterId: UUID
    let targetUserId: UUID?
    let messageId: UUID?
    let assetId: UUID?
    let category: String
    let details: String?
    let snapshot: [String: AnyJSON]?
    var status: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, category, details, snapshot, status
        case reporterId = "reporter_id"
        case targetUserId = "target_user_id"
        case messageId = "message_id"
        case assetId = "asset_id"
        case createdAt = "created_at"
    }
}

struct AdminUserRow: Codable, Identifiable, Hashable {
    let id: UUID
    let username: String
    let displayName: String
    let role: String
    let suspendedUntil: String?
    enum CodingKeys: String, CodingKey {
        case id, username, role
        case displayName = "display_name"
        case suspendedUntil = "suspended_until"
    }
}

enum DateParser {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses Postgres timestamps such as 2026-11-12T20:07:00.123456+00:00
    static func parse(_ s: String?) -> Date {
        guard var s, !s.isEmpty else { return .distantPast }
        s = s.replacingOccurrences(of: " ", with: "T")
        var fraction = 0.0
        if let dot = s.firstIndex(of: ".") {
            var end = s.index(after: dot)
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            fraction = Double("0" + String(s[dot..<end])) ?? 0
            s.removeSubrange(dot..<end)
        }
        if s.range(of: #"(Z|[+-]\d\d(:?\d\d)?)$"#, options: .regularExpression) == nil { s += "Z" }
        if s.range(of: #"[+-]\d\d$"#, options: .regularExpression) != nil { s += ":00" }
        guard let d = iso.date(from: s) else { return .distantPast }
        return d.addingTimeInterval(fraction)
    }

    static func shortTime(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: d, to: Date()).day, days < 7 {
            return d.formatted(.dateTime.weekday(.abbreviated))
        }
        return d.formatted(date: .numeric, time: .omitted)
    }
}
