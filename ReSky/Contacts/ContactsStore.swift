import Foundation
import Supabase

@MainActor
final class ContactsStore: ObservableObject {
    static let shared = ContactsStore()
    @Published var contacts: [ProfileCard] = []
    @Published var incoming: [ProfileCard] = []
    @Published var outgoing: [ProfileCard] = []
    @Published var profiles: [UUID: ProfileCard] = [:]
    @Published var loading = false
    private var pollTask: Task<Void, Never>?
    private var lastStatus: [UUID: PresenceStatus] = [:]

    func start() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        contacts = []; incoming = []; outgoing = []; profiles = [:]; lastStatus = [:]
    }

    func refresh() async {
        guard let me = SessionStore.shared.userId else { return }
        loading = contacts.isEmpty
        defer { loading = false }
        do {
            let rows: [ContactRow] = try await supabase.from("contacts").select()
                .or("owner_id.eq.\(me.lc),contact_id.eq.\(me.lc)").execute().value
            let mine = rows.filter { $0.ownerId == me }
            let accepted = Set(mine.filter { $0.status == "accepted" }.map(\.contactId))
            let outgoingIDs = Set(mine.filter { $0.status == "requested" }.map(\.contactId))
            let incomingIDs = Set(rows.filter { $0.contactId == me && $0.status == "requested" }.map(\.ownerId))
                .subtracting(accepted)
            let all = accepted.union(outgoingIDs).union(incomingIDs)
            let cards = try await loadProfiles(Array(all))
            contacts = cards.filter { accepted.contains($0.id) }.sorted(by: Self.order)
            incoming = cards.filter { incomingIDs.contains($0.id) }
            outgoing = cards.filter { outgoingIDs.contains($0.id) }
            announceStatusChanges()
        } catch {
            // keep last known list when offline
        }
    }

    private static func order(_ a: ProfileCard, _ b: ProfileCard) -> Bool {
        let ranks: [PresenceStatus: Int] = [.online: 0, .away: 1, .dnd: 2]
        let rank: (PresenceStatus) -> Int = { ranks[$0] ?? 3 }
        if rank(a.status) != rank(b.status) { return rank(a.status) < rank(b.status) }
        return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
    }

    private func announceStatusChanges() {
        let notify = SessionStore.shared.settings?.notifyContactStatus ?? true
        for c in contacts {
            let now = c.status
            if let before = lastStatus[c.id], notify {
                if before == .offline && now != .offline { SoundManager.shared.play(.contactOnline) }
                if before != .offline && now == .offline { SoundManager.shared.play(.contactOffline) }
            }
            lastStatus[c.id] = now
        }
    }

    /// Fetches (and caches) public profile cards.
    func loadProfiles(_ ids: [UUID]) async throws -> [ProfileCard] {
        guard !ids.isEmpty else { return [] }
        let cards: [ProfileCard] = try await supabase.from("profile_cards").select()
            .in("id", values: ids.map(\.lc)).execute().value
        for c in cards { profiles[c.id] = c }
        return cards
    }

    func profile(_ id: UUID?) -> ProfileCard? {
        guard let id else { return nil }
        if id == SessionStore.shared.userId { return SessionStore.shared.me }
        return profiles[id]
    }

    func ensureProfiles(_ ids: [UUID]) async {
        let missing = ids.filter { profiles[$0] == nil && $0 != SessionStore.shared.userId }
        _ = try? await loadProfiles(Array(Set(missing)))
    }

    func sendRequest(username: String) async throws -> String {
        let result: String = try await supabase.rpc("send_contact_request", params: ["target_username": username]).execute().value
        await refresh()
        return result
    }

    func respond(_ requester: UUID, accept: Bool) async {
        struct P: Encodable { let requester: UUID; let accept: Bool }
        try? await supabase.rpc("respond_contact_request", params: P(requester: requester, accept: accept)).execute()
        await refresh()
    }

    func remove(_ id: UUID) async {
        try? await supabase.rpc("remove_contact", params: ["other": id.lc]).execute()
        await refresh()
    }

    func block(_ id: UUID) async {
        try? await supabase.rpc("block_user", params: ["other": id.lc]).execute()
        await refresh()
    }

    func openDirect(_ id: UUID) async throws -> UUID {
        try await supabase.rpc("create_direct_conversation", params: ["other": id.lc]).execute().value
    }
}
