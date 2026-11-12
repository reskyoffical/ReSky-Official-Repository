import SwiftUI
import StoreKit

struct PlusPaywallView: View {
    @EnvironmentObject private var plus: PlusStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    private let perks: [(String, String, String)] = [
        ("sparkles", "Animated profile pictures", "GIFs and animated images as your avatar"),
        ("rectangle.stack.fill", "Animated banners & backgrounds", "Bring your profile to life"),
        ("paintpalette.fill", "6 premium themes", "Sunset, Green Nature, Neon, Winter, Minimalist and Retro"),
        ("circle.hexagongrid.fill", "Exclusive borders & decorations", "Rainbow Ring, Glow Cloud, Sparkles…"),
        ("eyedropper.full", "Any accent colour", "Pick any colour for your profile"),
        ("star.circle.fill", "PLUS badge", "Show your support next to your name"),
    ]

    var body: some View {
        ZStack {
            CloudBackground()
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.9)) }
                    }
                    Image("ReSkyLogo").resizable().scaledToFit().frame(maxWidth: 170)
                    Text("ReSky Plus").font(.resky(.largeTitle, weight: .heavy)).foregroundStyle(.white)
                        .shadow(color: Color(hex: "#0B6FA8").opacity(0.5), radius: 4, y: 2)

                    if session.isFounder {
                        Label("Founder account — every premium feature is permanently unlocked.", systemImage: "crown.fill")
                            .font(.resky(.headline)).padding().reskyPanel()
                    } else if session.hasPlus {
                        VStack(spacing: 6) {
                            Label("You're a ReSky Plus member", systemImage: "checkmark.seal.fill").font(.resky(.headline))
                            if let r = plus.renewalInfo { Text(r).font(.resky(.caption)).foregroundStyle(.secondary) }
                            Button("Manage subscription") { Task { await plus.manageSubscription() } }.font(.resky(.subheadline))
                        }
                        .padding().frame(maxWidth: .infinity).reskyPanel()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(perks, id: \.1) { icon, title, sub in
                            HStack(spacing: 12) {
                                Image(systemName: icon).font(.title3).foregroundStyle(Color.reskyBlue).frame(width: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(title).font(.resky(.subheadline, weight: .bold))
                                    Text(sub).font(.resky(.caption)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).reskyPanel()

                    if !session.isFounder && !session.hasPlus {
                        Button { Task { await plus.purchase() } } label: {
                            HStack {
                                if plus.purchasing { ProgressView().tint(.white) }
                                Text(plus.product.map { "Subscribe for \($0.displayPrice)/month" } ?? "Subscribe")
                            }
                        }
                        .buttonStyle(ClassicButtonStyle(color: .reskyGreen))
                        .disabled(plus.purchasing || plus.product == nil)

                        Button("Restore purchases") { Task { await plus.restore() } }
                            .font(.resky(.subheadline, weight: .semibold)).foregroundStyle(.white)

                        Text("Monthly auto-renewing subscription. Payment is charged to your Apple ID and renews automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel in your App Store account settings.")
                            .font(.resky(.caption2)).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            Link("Terms of Use", destination: AppConfig.termsURL)
                            Link("Privacy Policy", destination: AppConfig.privacyURL)
                        }
                        .font(.resky(.caption, weight: .semibold)).foregroundStyle(.white)
                    }
                    if let e = plus.lastError { Text(e).font(.resky(.footnote)).foregroundStyle(.white).padding(8).background(Color.reskyDND.opacity(0.8).cornerRadius(8)) }
                }
                .padding(22)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            await plus.loadProduct()
            await plus.refreshRenewalInfo()
        }
        .onChange(of: session.hasPlus) { _, has in if has && !session.isFounder { Haptics.success() } }
    }
}
