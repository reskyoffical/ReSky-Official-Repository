import SwiftUI
import Supabase

/// Founder / moderator tools. Every action is re-checked on the server (is_staff / is_founder).
struct AdminDashboardView: View {
    @EnvironmentObject private var session: SessionStore
    enum Tab: String, CaseIterable { case overview = "Overview", reports = "Reports", users = "Users", cosmetics = "Cosmetics" }
    @State private var tab: Tab = .overview

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases.filter { $0 != .cosmetics || session.isFounder }, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding()
            switch tab {
            case .overview: AdminOverview()
            case .reports: AdminReportsView()
            case .users: AdminUsersView()
            case .cosmetics: AdminCosmeticsView()
            }
        }
        .navigationTitle("Admin dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AdminOverview: View {
    @State private var stats: [String: Int] = [:]
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(Color.reskyDND) }
            ForEach([("users", "Registered users", "person.3.fill"), ("online", "Online now", "dot.radiowaves.left.and.right"),
                     ("plus", "ReSky Plus members", "sparkles"), ("open_reports", "Open reports", "flag.fill"),
                     ("suspended", "Suspended accounts", "hand.raised.fill"), ("messages_24h", "Messages (24h)", "bubble.left.fill")], id: \.0) { key, title, icon in
                LabeledContent { Text("\(stats[key] ?? 0)").font(.resky(.title3, weight: .bold)) } label: { Label(title, systemImage: icon) }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            stats = try await supabase.rpc("admin_stats").execute().value
            error = nil
        } catch {
            self.error = "Admin access denied. If you enabled 2FA, sign out and back in with your code."
        }
    }
}

struct AdminReportsView: View {
    @State private var reports: [ReportRow] = []
    @State private var showClosed = false
    @StateObject private var contacts = ContactsStore.shared

    var body: some View {
        List {
            Toggle("Show resolved", isOn: $showClosed).onChange(of: showClosed) { _, _ in Task { await load() } }
            if reports.isEmpty { Text("No reports 🎉").foregroundStyle(.secondary) }
            ForEach(reports) { r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(r.category.replacingOccurrences(of: "_", with: " ").capitalized).font(.resky(.headline))
                        Spacer()
                        Text(r.status.uppercased()).font(.caption2.bold())
                            .foregroundStyle(r.status == "open" ? Color.reskyDND : .secondary)
                    }
                    if let t = r.targetUserId {
                        Text("Reported: \(contacts.profile(t).map { "\($0.displayName) (@\($0.username))" } ?? t.lc)").font(.resky(.caption))
                    }
                    if let snap = r.snapshot {
                        Text(snapshotText(snap)).font(.resky(.subheadline)).padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.reskySky))
                    }
                    if let d = r.details { Text("“\(d)”").font(.resky(.caption)).italic() }
                    Text(DateParser.parse(r.createdAt).formatted()).font(.caption2).foregroundStyle(.secondary)
                    if r.status == "open" {
                        HStack {
                            Button("Dismiss") { Task { await resolve(r, "dismissed") } }.buttonStyle(.bordered)
                            Menu("Take action") {
                                if let t = r.targetUserId {
                                    Button("Suspend 7 days") { Task { await suspend(t, 7, r) } }
                                    Button("Suspend 30 days") { Task { await suspend(t, 30, r) } }
                                    Button("Suspend permanently") { Task { await suspend(t, 36500, r) } }
                                    Button("Reset username & display name") { Task { await resetIdentity(t, r) } }
                                }
                                if let a = r.assetId { Button("Remove image", role: .destructive) { Task { await removeAsset(a, r) } } }
                                Button("Mark actioned") { Task { await resolve(r, "actioned") } }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func snapshotText(_ s: [String: AnyJSON]) -> String {
        if let body = s["body"]?.stringValue { return body }
        if let path = s["attachment_path"]?.stringValue { return "Attachment: \(path)" }
        let parts = ["username", "display_name", "status_message"].compactMap { k in s[k]?.stringValue.map { "\(k): \($0)" } }
        return parts.joined(separator: "\n")
    }

    private func load() async {
        reports = (try? await supabase.rpc("admin_list_reports", params: ["only_open": !showClosed]).execute().value) ?? []
        await contacts.ensureProfiles(reports.compactMap(\.targetUserId))
    }

    private func resolve(_ r: ReportRow, _ status: String) async {
        struct P: Encodable { let report: UUID; let new_status: String; let note: String? }
        try? await supabase.rpc("admin_resolve_report", params: P(report: r.id, new_status: status, note: nil)).execute()
        await load()
    }

    private func suspend(_ user: UUID, _ days: Int, _ r: ReportRow) async {
        struct P: Encodable { let target: UUID; let days: Int; let reason: String }
        do {
            try await supabase.rpc("admin_suspend_user", params: P(target: user, days: days, reason: "Report \(r.category)")).execute()
            await resolve(r, "actioned")
        } catch { SessionStore.shared.banner = ReSkyError.message(error) }
    }

    private func resetIdentity(_ user: UUID, _ r: ReportRow) async {
        _ = try? await supabase.rpc("admin_reset_identity", params: ["target": user.lc]).execute()
        await resolve(r, "actioned")
    }

    private func removeAsset(_ asset: UUID, _ r: ReportRow) async {
        _ = try? await supabase.rpc("admin_remove_asset", params: ["asset": asset.lc]).execute()
        await resolve(r, "actioned")
    }
}

struct AdminUsersView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var query = ""
    @State private var users: [AdminUserRow] = []
    @State private var message: String?

    var body: some View {
        List {
            if let message { Text(message).font(.footnote) }
            ForEach(users) { u in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(u.displayName).font(.resky(.headline))
                        Text("@\(u.username)").foregroundStyle(.secondary)
                        Spacer()
                        Text(u.role.uppercased()).font(.caption2.bold())
                    }
                    if let s = u.suspendedUntil, DateParser.parse(s) > Date() {
                        Text("Suspended until \(DateParser.parse(s).formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Color.reskyDND)
                    }
                    if u.role != "founder" {
                        HStack {
                            Menu("Moderate") {
                                Button("Suspend 7 days") { Task { await call("admin_suspend_user", u, days: 7) } }
                                Button("Suspend 30 days") { Task { await call("admin_suspend_user", u, days: 30) } }
                                Button("Lift suspension") { Task { await call("admin_unsuspend_user", u) } }
                                Button("Reset username & display name", role: .destructive) { Task { await call("admin_reset_identity", u) } }
                                if session.isFounder {
                                    Divider()
                                    Button(u.role == "moderator" ? "Remove moderator" : "Make moderator") {
                                        Task { await setModerator(u, u.role != "moderator") }
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search username or display name")
        .onSubmit(of: .search) { Task { await search() } }
        .task { await search() }
    }

    private func search() async {
        users = (try? await supabase.rpc("admin_find_user", params: ["q": query]).execute().value) ?? []
    }

    private func call(_ fn: String, _ u: AdminUserRow, days: Int? = nil) async {
        do {
            if let days {
                struct P: Encodable { let target: UUID; let days: Int; let reason: String }
                try await supabase.rpc(fn, params: P(target: u.id, days: days, reason: "Manual moderation")).execute()
            } else {
                try await supabase.rpc(fn, params: ["target": u.id.lc]).execute()
            }
            message = "Done."
            await search()
        } catch { message = ReSkyError.message(error) }
    }

    private func setModerator(_ u: AdminUserRow, _ value: Bool) async {
        struct P: Encodable { let target: UUID; let make_moderator: Bool }
        do { try await supabase.rpc("admin_set_moderator", params: P(target: u.id, make_moderator: value)).execute(); await search() }
        catch { message = ReSkyError.message(error) }
    }
}

struct AdminCosmeticsView: View {
    @State private var items: [CosmeticItem] = []
    @State private var editing: CosmeticItem?
    @State private var showNew = false

    var body: some View {
        List {
            ForEach(items) { item in
                Button { editing = item } label: {
                    HStack {
                        CosmeticSwatch(item: item)
                        VStack(alignment: .leading) {
                            Text(item.name).font(.resky(.body, weight: .semibold))
                            Text("\(item.kind) · \(item.id)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.isPremium { PlusTag() }
                        if !item.isReleased { Text("UNRELEASED").font(.caption2.bold()).foregroundStyle(.orange) }
                        if item.founderOnly { Image(systemName: "crown.fill").foregroundStyle(Color.reskyGold) }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }
        .sheet(item: $editing) { item in CosmeticEditor(item: item) { await load() } }
        .sheet(isPresented: $showNew) {
            CosmeticEditor(item: CosmeticItem(id: "", kind: "theme", name: "", isPremium: true, isReleased: false, founderOnly: false,
                                              payload: CosmeticPayload(primary: "#00AFF0", background: "#EAF6FD", bubble: "#D9F1FD"),
                                              sortOrder: 50), isNew: true) { await load() }
        }
        .task { await load() }
    }

    private func load() async {
        items = (try? await supabase.from("cosmetic_items").select().order("kind").order("sort_order").execute().value) ?? []
    }
}

struct CosmeticEditor: View {
    @State var item: CosmeticItem
    var isNew = false
    var onSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var colors = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if isNew { TextField("id (e.g. ocean_wave)", text: $item.id).textInputAutocapitalization(.never) }
                TextField("Name", text: $item.name)
                Picker("Kind", selection: $item.kind) { Text("Theme").tag("theme"); Text("Border").tag("border"); Text("Decoration").tag("decoration") }
                Toggle("Premium (Plus)", isOn: $item.isPremium)
                Toggle("Released to users", isOn: $item.isReleased)
                Toggle("Founder only", isOn: $item.founderOnly)
                TextField("Colours (comma separated hex)", text: $colors).textInputAutocapitalization(.never)
                Stepper("Sort order: \(item.sortOrder)", value: $item.sortOrder)
                if let error { Text(error).foregroundStyle(Color.reskyDND) }
            }
            .navigationTitle(isNew ? "New cosmetic" : "Edit cosmetic")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(item.id.isEmpty || item.name.isEmpty) }
            }
            .onAppear {
                colors = (item.payload.colors ?? [item.payload.primary, item.payload.background, item.payload.bubble].compactMap { $0 }).joined(separator: ", ")
            }
        }
    }

    private func save() async {
        let list = colors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var payload = item.payload
        if item.kind == "theme" {
            payload.primary = list.first ?? payload.primary
            payload.background = list.count > 1 ? list[1] : payload.background
            payload.bubble = list.count > 2 ? list[2] : payload.bubble
        } else {
            payload.colors = list
        }
        struct P: Encodable {
            let p_id: String, p_kind: String, p_name: String, p_is_premium: Bool, p_is_released: Bool
            let p_founder_only: Bool, p_payload: CosmeticPayload, p_sort: Int
        }
        do {
            try await supabase.rpc("admin_upsert_cosmetic", params: P(p_id: item.id, p_kind: item.kind, p_name: item.name,
                                                                     p_is_premium: item.isPremium, p_is_released: item.isReleased,
                                                                     p_founder_only: item.founderOnly, p_payload: payload,
                                                                     p_sort: item.sortOrder)).execute()
            await onSave()
            dismiss()
        } catch {
            self.error = ReSkyError.message(error)
        }
    }
}
