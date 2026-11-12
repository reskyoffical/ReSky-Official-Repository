import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    static let reskyBlue = Color(hex: "#00AFF0")
    static let reskyDeepBlue = Color(hex: "#0078C8")
    static let reskySky = Color(hex: "#EAF6FD")
    static let reskyBubble = Color(hex: "#D9F1FD")
    static let reskyGreen = Color(hex: "#7FBA00")
    static let reskyGreenDark = Color(hex: "#5E9A00")
    static let reskyAway = Color(hex: "#FDB900")
    static let reskyDND = Color(hex: "#E2231A")
    static let reskyOffline = Color(hex: "#B7C3CC")
    static let reskyGold = Color(hex: "#F5A623")
}

/// The palette used across the app, built from the user's theme (+ optional accent colour).
struct ReSkyPalette {
    var themeId: String
    var isDark: Bool
    var primary: Color
    var background: Color
    var panel: Color
    var sidebar: Color
    var ownBubble: Color
    var otherBubble: Color
    var text: Color
    var secondaryText: Color
    var border: Color
    var titleTop: Color
    var titleBottom: Color
    var titleIsDark: Bool
    var backdrop: ThemeBackdropKind

    static func forTheme(_ themeId: String?, accentHex: String? = nil) -> ReSkyPalette {
        let t = ThemeCatalog.theme(themeId)
        return ReSkyPalette(themeId: t.id, isDark: t.dark,
                            primary: accentHex.map { Color(hex: $0) } ?? Color(hex: t.primary),
                            background: Color(hex: t.background), panel: Color(hex: t.panel), sidebar: Color(hex: t.sidebar),
                            ownBubble: Color(hex: t.ownBubble), otherBubble: Color(hex: t.otherBubble),
                            text: Color(hex: t.text), secondaryText: Color(hex: t.secondaryText), border: Color(hex: t.border),
                            titleTop: Color(hex: t.titleTop), titleBottom: Color(hex: t.titleBottom),
                            titleIsDark: t.titleIsDark, backdrop: t.backdrop)
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

/// The 8 ReSky themes. Must match public.cosmetic_items (kind = 'theme') in the database;
/// the server decides which are premium, the app only uses this for drawing.
enum ThemeCatalog {
    struct Def: Identifiable {
        let id: String
        let name: String
        let isPremium: Bool
        let dark: Bool
        let primary: String
        let background: String
        let panel: String
        let sidebar: String
        let ownBubble: String
        let otherBubble: String
        let text: String
        let secondaryText: String
        let border: String
        let titleTop: String
        let titleBottom: String
        let titleIsDark: Bool   // true = dark title bar (white text)
        let backdrop: ThemeBackdropKind
    }

    static let defaultId = "classic_blue"
    static let freeIds: Set<String> = ["classic_blue", "dark_mode"]

    static let all: [Def] = [
        Def(id: "classic_blue", name: "Classic Blue", isPremium: false, dark: false, primary: "#00AFF0",
            background: "#EAF6FD", panel: "#FFFFFF", sidebar: "#EEF8FE", ownBubble: "#D9F1FD", otherBubble: "#FFFFFF",
            text: "#1B2A36", secondaryText: "#6C8394", border: "#C9E6F7",
            titleTop: "#4CC2F7", titleBottom: "#1A9BE6", titleIsDark: true, backdrop: .clouds),
        Def(id: "dark_mode", name: "Dark Mode", isPremium: false, dark: true, primary: "#1E9BF0",
            background: "#0E1621", panel: "#152130", sidebar: "#111A26", ownBubble: "#173149", otherBubble: "#1B2838",
            text: "#FFFFFF", secondaryText: "#93A8BC", border: "#24364A",
            titleTop: "#1F2B3A", titleBottom: "#121B26", titleIsDark: true, backdrop: .darkSwirl),
        Def(id: "sunset", name: "Sunset", isPremium: true, dark: false, primary: "#F0743E",
            background: "#FFF3EA", panel: "#FFFFFF", sidebar: "#FFEADC", ownBubble: "#FFE0C7", otherBubble: "#FFFFFF",
            text: "#3A2416", secondaryText: "#9A7360", border: "#F7D3BC",
            titleTop: "#F48FB1", titleBottom: "#F79A5E", titleIsDark: true, backdrop: .sunset),
        Def(id: "green_nature", name: "Green Nature", isPremium: true, dark: false, primary: "#3FA535",
            background: "#F1F9EA", panel: "#FFFFFF", sidebar: "#EEF7E5", ownBubble: "#DDF2CF", otherBubble: "#FFFFFF",
            text: "#1E3318", secondaryText: "#6B8A60", border: "#CFE8BF",
            titleTop: "#8BD35E", titleBottom: "#45A332", titleIsDark: true, backdrop: .nature),
        Def(id: "neon", name: "Neon", isPremium: true, dark: true, primary: "#B44CFF",
            background: "#0D0A16", panel: "#16121F", sidebar: "#121019", ownBubble: "#2A1840", otherBubble: "#1C1828",
            text: "#FFFFFF", secondaryText: "#A99BC2", border: "#2E2340",
            titleTop: "#1E1A28", titleBottom: "#0F0C16", titleIsDark: true, backdrop: .neon),
        Def(id: "winter", name: "Winter", isPremium: true, dark: false, primary: "#2E9BE0",
            background: "#EEF7FD", panel: "#FFFFFF", sidebar: "#EAF5FC", ownBubble: "#DCEFFB", otherBubble: "#FFFFFF",
            text: "#17303F", secondaryText: "#6A8BA0", border: "#CBE4F4",
            titleTop: "#8FD0F5", titleBottom: "#4BA6E6", titleIsDark: true, backdrop: .winter),
        Def(id: "minimalist", name: "Minimalist", isPremium: true, dark: false, primary: "#1E88E5",
            background: "#F6F9FC", panel: "#FFFFFF", sidebar: "#F7F9FB", ownBubble: "#EAF2FB", otherBubble: "#FFFFFF",
            text: "#1A2530", secondaryText: "#7A8896", border: "#E1E8EF",
            titleTop: "#FFFFFF", titleBottom: "#F1F5F9", titleIsDark: false, backdrop: .minimal),
        Def(id: "retro", name: "Retro", isPremium: true, dark: false, primary: "#2A6EDB",
            background: "#EEF3FC", panel: "#FFFFFF", sidebar: "#E8EFFB", ownBubble: "#DCE8FA", otherBubble: "#FFFFFF",
            text: "#16243A", secondaryText: "#5F7395", border: "#C6D6F2",
            titleTop: "#4C8BF0", titleBottom: "#2556C9", titleIsDark: true, backdrop: .retro),
    ]

    /// The theme actually shown for a profile: premium themes need an active Plus (founder always has it).
    static func effectiveId(for profile: ProfileCard) -> String {
        let t = theme(profile.themeId)
        return (t.isPremium && !profile.isPlus) ? defaultId : t.id
    }

    static func theme(_ id: String?) -> Def {
        all.first { $0.id == id } ?? all[0]
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = ReSkyPalette.forTheme(ThemeCatalog.defaultId)
}

extension EnvironmentValues {
    var palette: ReSkyPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Font {
    static func resky(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

/// Glossy Windows-era button.
struct ClassicButtonStyle: ButtonStyle {
    var color: Color = .reskyBlue
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.resky(.headline, weight: .semibold))
            .foregroundStyle(prominent ? .white : color)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(prominent
                              ? LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)
                              : LinearGradient(colors: [.white, Color(hex: "#EEF7FD")], startPoint: .top, endPoint: .bottom))
                    if prominent {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                            .padding(1)
                    }
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(prominent ? color.opacity(0.9) : Color(hex: "#9FD6F2"), lineWidth: 1)
                }
            )
            .shadow(color: color.opacity(0.25), radius: 3, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { SoundManager.shared.play(.click) }
            }
    }
}

/// White rounded panel with a light blue rim, like classic Skype panes.
struct PanelModifier: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 12).fill(palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

extension View {
    func reskyPanel() -> some View { modifier(PanelModifier()) }

    /// Title-bar style navigation bar in the current theme's colours.
    func classicNavBar() -> some View { modifier(ThemedNavBar()) }
}

struct ThemedNavBar: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content
            .toolbarBackground(LinearGradient(colors: [palette.titleTop, palette.titleBottom], startPoint: .top, endPoint: .bottom),
                               for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(palette.titleIsDark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(palette.panel, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}

struct ReSkyTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.resky(.body))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#9FD6F2"), lineWidth: 1))
            .foregroundStyle(Color(hex: "#1B2A36"))
    }
}
