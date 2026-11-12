import SwiftUI
import PhotosUI

/// Profile header: banner, avatar with border, badges, status — used for self and others.
struct ProfileHeader: View {
    let profile: ProfileCard
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let banner = profile.bannerPath {
                        RemoteImage(bucket: "profile", path: banner, animate: profile.bannerAnimated)
                    } else {
                        ThemeBackdrop(kind: ThemeCatalog.theme(ThemeCatalog.effectiveId(for: profile)).backdrop)
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()

                AvatarView(profile: profile, size: 96)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(palette.panel))
                    .offset(x: 18, y: 48)
                if let deco = profile.decorationId, let symbol = DecorationCatalog.symbol(deco) {
                    DecorationOverlay(symbol: symbol)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(profile.displayName).font(.resky(.title2, weight: .bold))
                    RoleBadges(profile: profile)
                }
                Text("@\(profile.username)").font(.resky(.subheadline)).foregroundStyle(palette.secondaryText)
                HStack(spacing: 6) {
                    StatusIcon(status: profile.status, size: 12)
                    Text(profile.status.label).font(.resky(.caption, weight: .medium))
                }
                if let s = profile.statusMessage, !s.isEmpty {
                    Text("“\(s)”").font(.resky(.body)).italic().padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 56).padding(.horizontal, 18).padding(.bottom, 14)
        }
        .background(
            ZStack {
                palette.panel
                if let bg = profile.backgroundPath {
                    RemoteImage(bucket: "profile", path: bg, animate: profile.backgroundAnimated).opacity(0.25)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(profile.isFounder ? Color.reskyGold : palette.border, lineWidth: profile.isFounder ? 2 : 1))
        .shadow(color: (profile.isFounder ? Color.reskyGold : .black).opacity(profile.isFounder ? 0.35 : 0.06), radius: 8, y: 2)
    }
}

enum DecorationCatalog {
    static func symbol(_ id: String) -> String? {
        ["sparkles": "sparkles", "clouds": "cloud.fill", "hearts": "heart.fill"][id]
    }
}

struct DecorationOverlay: View {
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var float = false
    var body: some View {
        HStack(spacing: 26) {
            ForEach(0..<4) { i in
                Image(systemName: symbol).foregroundStyle(.white.opacity(0.9))
                    .font(.system(size: CGFloat(12 + (i % 2) * 6)))
                    .offset(y: float ? -8 : 8)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever().delay(Double(i) * 0.3), value: float)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 20).padding(.bottom, 100)
        .onAppear { float = true }
        .allowsHitTesting(false)
    }
}

struct MyProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var plus: PlusStore
    @Environment(\.palette) private var palette
    @State private var showEdit = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let me = session.me {
                    ProfileHeader(profile: me)
                    Button("Edit profile") { showEdit = true }.buttonStyle(ClassicButtonStyle())
                    if !me.isPlus {
                        Button { plus.showPaywall = true } label: { Label("Get ReSky Plus", systemImage: "sparkles") }
                            .buttonStyle(ClassicButtonStyle(color: .reskyGreen))
                    }
                    if me.isFounder {
                        NavigationLink { FounderSettingsView() } label: {
                            Label("Founder Settings", systemImage: "crown.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ClassicButtonStyle(color: .reskyGold))
                    }
                    if me.isStaff {
                        NavigationLink { AdminDashboardView() } label: {
                            Label("Admin dashboard", systemImage: "shield.lefthalf.filled").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ClassicButtonStyle(color: .reskyDeepBlue))
                    }
                } else {
                    ProgressView()
                }
            }
            .padding(16)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
        .navigationTitle("Profile")
        .classicNavBar()
        .sheet(isPresented: $showEdit) { NavigationStack { EditProfileView() } }
        .sheet(isPresented: Binding(get: { plus.showPaywall && !showEdit }, set: { plus.showPaywall = $0 })) { PlusPaywallView() }
        .refreshable { await session.loadProfile() }
    }
}

/// Another user's profile, with message/call/report/block actions.
struct ProfileDetailView: View {
    let profile: ProfileCard
    @EnvironmentObject private var calls: CallManager
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var reporting = false
    @State private var confirmBlock = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ProfileHeader(profile: profile)
                if profile.id != session.userId {
                    HStack(spacing: 10) {
                        Button { Task { if let c = try? await ContactsStore.shared.openDirect(profile.id) { dismiss(); session.pendingConversation = c } } } label: {
                            Label("Message", systemImage: "bubble.left.fill")
                        }.buttonStyle(ClassicButtonStyle())
                        Button { dismiss(); calls.startCall(to: profile, video: false) } label: { Label("Call", systemImage: "phone.fill") }
                            .buttonStyle(ClassicButtonStyle(color: .reskyGreen))
                        Button { dismiss(); calls.startCall(to: profile, video: true) } label: { Label("Video", systemImage: "video.fill") }
                            .buttonStyle(ClassicButtonStyle(color: .reskyGreen))
                    }
                    HStack(spacing: 10) {
                        Button { reporting = true } label: { Label("Report", systemImage: "exclamationmark.bubble") }
                            .buttonStyle(ClassicButtonStyle(prominent: false))
                        Button { confirmBlock = true } label: { Label("Block", systemImage: "hand.raised.fill") }
                            .buttonStyle(ClassicButtonStyle(color: .reskyDND, prominent: false))
                    }
                }
            }
            .padding(16)
        }
        .background(palette.background)
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .sheet(isPresented: $reporting) { ReportSheet(targetUser: profile.id, message: nil, category: "profile") }
        .confirmationDialog("Block \(profile.displayName)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await ContactsStore.shared.block(profile.id); dismiss() } }
        } message: { Text("They won't be able to message or call you, and they'll be removed from your contacts.") }
    }
}

struct EditProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var plus: PlusStore
    @StateObject private var custom = CustomisationStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var status = ""
    @State private var customColor = Color.reskyBlue
    @State private var pickerItem: PhotosPickerItem?
    @State private var uploadKind = "avatar"
    @State private var showPicker = false

    var body: some View {
        Form {
            Section("About you") {
                TextField("Display name", text: $displayName)
                TextField("Status message", text: $status)
                Button("Save") {
                    Task {
                        if await custom.update(["display_name": .string(String(displayName.prefix(40))),
                                                "status_message": .string(String(status.prefix(140)))]) { Haptics.success() }
                    }
                }
            }
            Section {
                uploadRow("Profile picture", kind: "avatar")
                uploadRow("Banner", kind: "banner")
                uploadRow("Background", kind: "background")
            } header: { Text("Pictures") } footer: {
                Text("Static images are free. Animated GIF / WebP / APNG artwork needs ReSky Plus — if you upload one without Plus it's saved and locked until you subscribe.")
            }
            if !custom.assets.isEmpty {
                Section("Your uploads") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(custom.assets) { a in
                                VStack(spacing: 4) {
                                    ZStack(alignment: .topTrailing) {
                                        RemoteImage(bucket: "profile", path: a.isAnimated && !(session.me?.isPlus ?? false) ? (a.staticPath ?? a.path) : a.path, animate: true)
                                            .frame(width: 74, height: 74).clipShape(RoundedRectangle(cornerRadius: 12))
                                        if a.isAnimated {
                                            Image(systemName: (session.me?.isPlus ?? false) ? "sparkles" : "lock.fill")
                                                .font(.caption2).padding(4).background(Circle().fill(.black.opacity(0.6))).foregroundStyle(.white)
                                        }
                                    }
                                    Text(a.kind.capitalized).font(.caption2)
                                }
                                .contextMenu {
                                    Button { Task { await custom.apply(a) } } label: { Label("Use", systemImage: "checkmark") }
                                    Button(role: .destructive) { Task { await custom.delete(a) } } label: { Label("Delete", systemImage: "trash") }
                                }
                                .onTapGesture { Task { await custom.apply(a) } }
                            }
                        }
                    }
                }
            }
            Section("Accent colour") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(CustomisationStore.freeAccents, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.white, lineWidth: session.me?.accentColor?.uppercased() == hex ? 3 : 0))
                                .shadow(radius: 1)
                                .onTapGesture { Task { _ = await custom.update(["accent_color": .string(hex)]) } }
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack {
                    ColorPicker("Custom colour", selection: $customColor, supportsOpacity: false)
                    Button("Apply") {
                        guard plus.requirePlus() else { return }
                        Task { _ = await custom.update(["accent_color": .string(customColor.hexString)]) }
                    }
                    PlusTag()
                }
            }
            Section("Theme") {
                NavigationLink { ThemePickerView() } label: {
                    HStack {
                        Text("App theme")
                        Spacer()
                        Text(ThemeCatalog.theme(session.me?.themeId).name).foregroundStyle(.secondary)
                    }
                }
            }
            cosmeticSection("Profile border", kind: "border")
            cosmeticSection("Decoration", kind: "decoration")
            if let m = custom.message { Section { Text(m).font(.footnote) } }
        }
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await custom.upload(data, kind: uploadKind) }
                pickerItem = nil
            }
        }
        .overlay { if custom.uploading { ProgressView("Uploading…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .sheet(isPresented: $plus.showPaywall) { PlusPaywallView() }
        .task {
            displayName = session.me?.displayName ?? ""
            status = session.me?.statusMessage ?? ""
            if let a = session.me?.accentColor { customColor = Color(hex: a) }
            await custom.load()
        }
    }

    private func uploadRow(_ title: String, kind: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button("Upload") { uploadKind = kind; showPicker = true }
            Button(role: .destructive) { Task { await custom.clear(kind) } } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
    }

    private func cosmeticSection(_ title: String, kind: String) -> some View {
        Section(title) {
            ForEach(custom.items(kind)) { item in
                Button { Task { await custom.choose(item) } } label: {
                    HStack {
                        CosmeticSwatch(item: item)
                        Text(item.name)
                        if !item.isReleased { Text("PREVIEW").font(.caption2.bold()).foregroundStyle(.orange) }
                        Spacer()
                        if item.isPremium { PlusTag() }
                        if isSelected(item) { Image(systemName: "checkmark").foregroundStyle(Color.reskyBlue) }
                    }
                }
                .foregroundStyle(.primary)
            }
            if kind == "decoration", session.me?.decorationId != nil {
                Button("Remove decoration") { Task { _ = await custom.update(["decoration_id": .null]) } }
            }
        }
    }

    private func isSelected(_ item: CosmeticItem) -> Bool {
        guard let me = session.me else { return false }
        switch item.kind {
        case "theme": return me.themeId == item.id
        case "border": return me.borderId == item.id
        default: return me.decorationId == item.id
        }
    }
}

struct CosmeticSwatch: View {
    let item: CosmeticItem
    var body: some View {
        let colors = (item.payload.colors ?? [item.payload.primary, item.payload.background].compactMap { $0 }).map { Color(hex: $0) }
        ZStack {
            if let symbol = item.payload.symbol {
                Image(systemName: symbol).foregroundStyle(Color.reskyBlue)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: colors.isEmpty ? [.gray.opacity(0.2)] : (colors.count == 1 ? colors + colors : colors),
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: 28, height: 28)
    }
}

struct PlusTag: View {
    var body: some View {
        Text("PLUS").font(.system(size: 9, weight: .heavy, design: .rounded))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(Color.reskyBlue)).foregroundStyle(.white)
    }
}

extension Color {
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}
