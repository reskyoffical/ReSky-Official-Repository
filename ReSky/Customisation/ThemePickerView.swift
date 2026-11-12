import SwiftUI
import Supabase

/// Grid of theme previews. Classic Blue and Dark Mode are free; the rest need ReSky Plus.
/// The founder (and Plus members) see everything unlocked. The server re-checks on save.
struct ThemePickerView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var plus: PlusStore
    @Environment(\.palette) private var palette
    @State private var saving: String?
    @State private var error: String?

    private var unlocked: Bool { session.isFounder || session.hasPlus }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView {
            if session.isFounder {
                Label("Founder — every theme is unlocked", systemImage: "crown.fill")
                    .font(.resky(.subheadline, weight: .semibold)).foregroundStyle(Color.reskyGold)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 8)
            } else if !session.hasPlus {
                Button { plus.showPaywall = true } label: {
                    Label("Unlock all themes with ReSky Plus", systemImage: "sparkles")
                }
                .buttonStyle(ClassicButtonStyle(color: .reskyGreen))
                .padding(.horizontal).padding(.top, 8)
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(ThemeCatalog.all) { theme in
                    Button { Task { await choose(theme) } } label: {
                        VStack(spacing: 6) {
                            ThemePreviewCard(theme: theme,
                                             selected: (session.me?.themeId ?? ThemeCatalog.defaultId) == theme.id,
                                             locked: theme.isPremium && !unlocked,
                                             saving: saving == theme.id)
                            HStack(spacing: 4) {
                                Text(theme.name).font(.resky(.subheadline, weight: .semibold)).foregroundStyle(palette.text)
                                if !theme.isPremium {
                                    Text("FREE").font(.system(size: 9, weight: .heavy, design: .rounded))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.reskyGreen)).foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            if let error { Text(error).font(.footnote).foregroundStyle(Color.reskyDND).padding(.horizontal) }
        }
        .background(palette.background)
        .navigationTitle("Themes")
        .classicNavBar()
        .sheet(isPresented: $plus.showPaywall) { PlusPaywallView() }
    }

    private func choose(_ theme: ThemeCatalog.Def) async {
        if theme.isPremium && !plus.requirePlus() { return }   // founder/Plus pass straight through
        guard let uid = session.userId else { return }
        saving = theme.id
        defer { saving = nil }
        do {
            try await supabase.from("profiles").update(["theme_id": theme.id]).eq("id", value: uid.lc).execute()
            UserDefaults.standard.set(theme.id, forKey: "resky.themeId")
            await session.loadProfile()
            Haptics.success()
            error = nil
        } catch {
            if ReSkyError.code(error) == "plus_required" { plus.showPaywall = true } else { self.error = ReSkyError.message(error) }
        }
    }
}

/// Mini ReSky window drawn in the theme's colours (title bar, contact list, hero, composer).
struct ThemePreviewCard: View {
    let theme: ThemeCatalog.Def
    var selected = false
    var locked = false
    var saving = false

    var body: some View {
        let p = ReSkyPalette.forTheme(theme.id)
        VStack(spacing: 0) {
            // title bar
            HStack(spacing: 3) {
                Text("ReSky").font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(p.titleIsDark ? .white : Color.reskyDeepBlue)
                Spacer()
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(i == 2 ? Color(hex: "#E5533D") : Color.white.opacity(p.titleIsDark ? 0.35 : 0.0))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(p.titleIsDark ? .clear : Color.gray.opacity(0.4), lineWidth: 0.5))
                        .frame(width: 9, height: 7)
                }
            }
            .padding(.horizontal, 6).frame(height: 18)
            .background(LinearGradient(colors: [p.titleTop, p.titleBottom], startPoint: .top, endPoint: .bottom))

            HStack(spacing: 0) {
                // contact list
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        HStack(spacing: 3) {
                            Circle().fill(i < 3 ? Color.reskyGreen : Color.reskyOffline).frame(width: 5, height: 5)
                            RoundedRectangle(cornerRadius: 1).fill(p.text.opacity(0.55)).frame(width: CGFloat(22 + (i * 9) % 14), height: 3)
                        }
                    }
                    Spacer()
                }
                .padding(5)
                .frame(width: 52)
                .frame(maxHeight: .infinity)
                .background(p.sidebar)

                ZStack {
                    ThemeBackdrop(kind: theme.backdrop)
                    VStack(spacing: 4) {
                        Image("ReSkyLogo").resizable().scaledToFit().frame(width: 58)
                        HStack(spacing: 3) {
                            Capsule().fill(Color.reskyGreen).frame(width: 22, height: 8)
                            Capsule().fill(Color.reskyGreen).frame(width: 28, height: 8)
                        }
                    }
                }
            }
            // composer
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(p.panel).overlay(RoundedRectangle(cornerRadius: 3).stroke(p.border, lineWidth: 0.5))
                Capsule().fill(p.primary).frame(width: 22)
            }
            .frame(height: 12).padding(4)
            .background(p.sidebar)
        }
        .frame(height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.reskyGreen : p.border, lineWidth: selected ? 3 : 1))
        .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
        .overlay(alignment: .topTrailing) {
            if locked {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill")
                    Text("PLUS")
                }
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(Color.reskyBlue)).foregroundStyle(.white)
                .padding(6).offset(y: 18)
            } else if selected {
                Image(systemName: "checkmark.circle.fill").font(.title3)
                    .foregroundStyle(.white, Color.reskyGreen).padding(6).offset(y: 18)
            }
        }
        .overlay { if saving { ProgressView().padding(8).background(.regularMaterial, in: Circle()) } }
        .accessibilityLabel("\(theme.name) theme\(locked ? ", requires ReSky Plus" : "")\(selected ? ", selected" : "")")
    }
}
