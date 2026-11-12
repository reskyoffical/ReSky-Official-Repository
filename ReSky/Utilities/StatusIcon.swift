import SwiftUI

/// Classic status bubble: green tick (online), yellow clock (away), red bar (DND), grey (offline).
struct StatusIcon: View {
    let status: PresenceStatus
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().fill(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center))
            Image(systemName: symbol)
                .font(.system(size: size * 0.55, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white, lineWidth: size * 0.12))
        .accessibilityLabel(status.label)
    }

    private var fill: Color {
        switch status {
        case .online: return .reskyGreen
        case .away: return .reskyAway
        case .dnd: return .reskyDND
        case .invisible, .offline: return .reskyOffline
        }
    }

    private var symbol: String {
        switch status {
        case .online: return "checkmark"
        case .away: return "clock"
        case .dnd: return "minus"
        case .invisible, .offline: return "xmark"
        }
    }
}
