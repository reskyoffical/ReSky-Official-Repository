import SwiftUI
import Supabase

struct ReportSheet: View {
    let targetUser: UUID?
    let message: UUID?
    var category: String
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String
    @State private var details = ""
    @State private var sent = false
    @State private var error: String?

    init(targetUser: UUID?, message: UUID?, category: String) {
        self.targetUser = targetUser
        self.message = message
        self.category = category
        _selected = State(initialValue: category)
    }

    private let categories: [(String, String)] = [
        ("message", "Inappropriate message"), ("image", "Inappropriate image"), ("harassment", "Harassment or bullying"),
        ("username", "Offensive username"), ("display_name", "Offensive display name"), ("profile", "Inappropriate profile"),
        ("spam", "Spam or scam"), ("other", "Something else"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("Thanks — our moderators will review this report.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Color.reskyGreenDark)
                    }
                } else {
                    Section("What's wrong?") {
                        Picker("Reason", selection: $selected) {
                            ForEach(categories, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .pickerStyle(.inline).labelsHidden()
                    }
                    Section("Details (optional)") {
                        TextField("Tell us more", text: $details, axis: .vertical).lineLimit(3...6)
                    }
                    if let error { Section { Text(error).foregroundStyle(Color.reskyDND) } }
                    Section {
                        Button("Send report") { Task { await send() } }
                    } footer: {
                        Text("Reports are confidential. You can also block this person.")
                    }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(sent ? "Done" : "Cancel") { dismiss() } } }
        }
    }

    private func send() async {
        struct P: Encodable {
            let p_category: String
            let p_target_user: UUID?
            let p_message: UUID?
            let p_asset: UUID?
            let p_details: String?
        }
        do {
            try await supabase.rpc("report_content", params: P(p_category: selected, p_target_user: targetUser, p_message: message,
                                                              p_asset: nil, p_details: details.isEmpty ? nil : details)).execute()
            withAnimation { sent = true }
            Haptics.success()
        } catch {
            self.error = ReSkyError.message(error)
        }
    }
}

struct BlockedUsersView: View {
    @State private var blocked: [ProfileCard] = []
    var body: some View {
        List {
            if blocked.isEmpty { Text("You haven't blocked anyone.").foregroundStyle(.secondary) }
            ForEach(blocked) { p in
                HStack {
                    AvatarView(profile: p, size: 34, showStatus: false)
                    Text(p.displayName)
                    Spacer()
                    Button("Unblock") {
                        Task {
                            guard let me = SessionStore.shared.userId else { return }
                            try? await supabase.from("blocks").delete().eq("blocker_id", value: me.lc).eq("blocked_id", value: p.id.lc).execute()
                            await load()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Blocked users")
        .task { await load() }
    }

    private func load() async {
        struct Row: Decodable { let blocked_id: UUID }
        let rows: [Row] = (try? await supabase.from("blocks").select("blocked_id").execute().value) ?? []
        blocked = (try? await ContactsStore.shared.loadProfiles(rows.map(\.blocked_id))) ?? []
    }
}
