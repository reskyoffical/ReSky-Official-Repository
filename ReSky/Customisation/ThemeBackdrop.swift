import SwiftUI

enum ThemeBackdropKind { case clouds, darkSwirl, sunset, nature, neon, winter, minimal, retro }

/// Original vector artwork for each theme (drawn in code — no image assets).
struct ThemeBackdrop: View {
    let kind: ThemeBackdropKind

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                switch kind {
                case .clouds: clouds(w, h)
                case .darkSwirl: darkSwirl(w, h)
                case .sunset: sunset(w, h)
                case .nature: nature(w, h)
                case .neon: neon(w, h)
                case .winter: winter(w, h)
                case .minimal: minimal(w, h)
                case .retro: retro(w, h)
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }

    // MARK: Classic Blue — bright sky with puffy clouds
    private func clouds(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#1FA6EE"), Color(hex: "#5CC4F6"), Color(hex: "#A6E0FB")], startPoint: .top, endPoint: .bottom)
            puff(w * 0.75, w * 0.2, h * 0.08, 0.95)
            puff(w * 0.5, -w * 0.12, h * 0.55, 0.9)
            puff(w * 0.55, w * 0.62, h * 0.7, 0.95)
            puff(w * 0.35, w * 0.05, h * 0.28, 0.6)
        }
    }

    // MARK: Dark Mode — deep navy with glowing blue light trails
    private func darkSwirl(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#071426"), Color(hex: "#0B2445"), Color(hex: "#081a33")], startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(0..<4, id: \.self) { i in
                Ellipse()
                    .trim(from: 0.05 + CGFloat(i) * 0.04, to: 0.55 + CGFloat(i) * 0.05)
                    .stroke(Color(hex: i % 2 == 0 ? "#2E8BFF" : "#5CC8FF").opacity(0.55 - Double(i) * 0.1),
                            style: StrokeStyle(lineWidth: max(1.5, w * 0.012) - CGFloat(i) * 0.3, lineCap: .round))
                    .frame(width: w * (1.5 - CGFloat(i) * 0.12), height: h * (0.55 + CGFloat(i) * 0.08))
                    .rotationEffect(.degrees(-18 + Double(i) * 7))
                    .offset(x: w * 0.1, y: h * (0.18 - CGFloat(i) * 0.03))
                    .blur(radius: 0.6)
                    .shadow(color: Color(hex: "#2E8BFF"), radius: 6)
            }
            Circle().fill(Color(hex: "#1E6FD9").opacity(0.35)).frame(width: w * 0.9).blur(radius: w * 0.18)
                .offset(x: w * 0.3, y: h * 0.25)
            stars(w, h, count: 26, color: .white.opacity(0.7), seed: 3)
        }
    }

    // MARK: Sunset — warm sky, sun on the sea, palm silhouettes
    private func sunset(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(hex: "#7B3FA8"), location: 0),
                .init(color: Color(hex: "#E2537A"), location: 0.38),
                .init(color: Color(hex: "#F7934C"), location: 0.6),
                .init(color: Color(hex: "#FBC25A"), location: 0.68),
                .init(color: Color(hex: "#E8714A"), location: 0.7),
                .init(color: Color(hex: "#8E3A6E"), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#FFF3B0"), Color(hex: "#FFC94A"), Color(hex: "#FF9A3C").opacity(0)],
                                     center: .center, startRadius: 0, endRadius: w * 0.22))
                .frame(width: w * 0.44, height: w * 0.44)
                .position(x: w * 0.5, y: h * 0.68)
            // reflections on the water
            ForEach(0..<7, id: \.self) { i in
                Capsule().fill(Color(hex: "#FFD27A").opacity(0.55 - Double(i) * 0.06))
                    .frame(width: w * (0.34 - CGFloat(i) * 0.04), height: max(1.5, h * 0.008))
                    .position(x: w * 0.5, y: h * (0.73 + CGFloat(i) * 0.035))
            }
            PalmShape().fill(Color(hex: "#2A0E2E")).frame(width: w * 0.42, height: h * 0.7)
                .position(x: w * 0.12, y: h * 0.62)
            PalmShape().fill(Color(hex: "#2A0E2E")).frame(width: w * 0.36, height: h * 0.6).scaleEffect(x: -1)
                .position(x: w * 0.9, y: h * 0.66)
        }
    }

    // MARK: Green Nature — layered leaves with a dew drop
    private func nature(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#B5E57E"), Color(hex: "#6CC04A"), Color(hex: "#2F8A24")], startPoint: .topTrailing, endPoint: .bottomLeading)
            leaf(w * 0.9, w * 0.35, h * 0.95, -35, "#4FA83A", "#2E7D22")
            leaf(w * 0.8, w * 0.95, h * 0.7, 30, "#7CCB52", "#3E9A2E")
            leaf(w * 0.6, w * 0.15, h * 0.2, -60, "#9ADB6A", "#58B13F")
            leaf(w * 0.7, w * 0.75, h * 0.15, 55, "#8AD45C", "#4BA536")
            // dew drop
            ZStack {
                Circle().fill(RadialGradient(colors: [.white.opacity(0.85), Color(hex: "#C8F2A8").opacity(0.5), Color(hex: "#5DB43F").opacity(0.4)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: w * 0.07))
                Circle().stroke(.white.opacity(0.6), lineWidth: 1)
            }
            .frame(width: w * 0.12, height: w * 0.12)
            .shadow(color: Color(hex: "#1E5A16").opacity(0.4), radius: 3, x: 2, y: 3)
            .position(x: w * 0.8, y: h * 0.78)
            Circle().fill(Color.white.opacity(0.25)).frame(width: w * 0.8).blur(radius: w * 0.2).position(x: w * 0.8, y: h * 0.05)
        }
    }

    // MARK: Neon — purple night with a glowing skyline
    private func neon(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#0B0418"), Color(hex: "#2A0A55"), Color(hex: "#4B0F7A"), Color(hex: "#12051F")],
                           startPoint: .top, endPoint: .bottom)
            stars(w, h * 0.5, count: 30, color: Color(hex: "#E9C9FF").opacity(0.8), seed: 7)
            Skyline(seed: 11, windows: true)
                .fill(Color(hex: "#160828"))
                .overlay(Skyline(seed: 11, windows: false).stroke(Color(hex: "#D25CFF"), lineWidth: 1.2))
                .shadow(color: Color(hex: "#C14BFF"), radius: 6)
                .frame(width: w, height: h * 0.42)
                .position(x: w / 2, y: h * 0.62)
            Skyline(seed: 11, windows: true)
                .fill(Color(hex: "#FFD36B").opacity(0.85))
                .mask(WindowsMask(seed: 11))
                .frame(width: w, height: h * 0.42)
                .position(x: w / 2, y: h * 0.62)
            // reflection
            LinearGradient(colors: [Color(hex: "#7A1FC2").opacity(0.7), Color(hex: "#12051F")], startPoint: .top, endPoint: .bottom)
                .frame(height: h * 0.17).position(x: w / 2, y: h * 0.915)
            ForEach(0..<6, id: \.self) { i in
                Capsule().fill(Color(hex: i % 2 == 0 ? "#E05CFF" : "#5CE1FF").opacity(0.5))
                    .frame(width: w * CGFloat(0.12 + Double((i * 37) % 10) / 40), height: 1.5)
                    .position(x: w * CGFloat(0.1 + Double(i) * 0.16), y: h * CGFloat(0.87 + Double(i % 3) * 0.035))
            }
        }
    }

    // MARK: Winter — icy sky, snowy pines, snowflakes
    private func winter(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#4FB0EC"), Color(hex: "#93D2F6"), Color(hex: "#E2F4FD")], startPoint: .top, endPoint: .bottom)
            Ellipse().fill(LinearGradient(colors: [.white, Color(hex: "#D6ECFA")], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 1.6, height: h * 0.45).position(x: w * 0.45, y: h * 1.02)
            Ellipse().fill(LinearGradient(colors: [Color(hex: "#F4FBFF"), Color(hex: "#C9E6F8")], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 1.2, height: h * 0.32).position(x: w * 0.95, y: h * 1.0)
            pine(w * 0.34, h * 0.55, x: w * 0.82, y: h * 0.62)
            pine(w * 0.22, h * 0.36, x: w * 0.6, y: h * 0.76)
            pine(w * 0.16, h * 0.26, x: w * 0.12, y: h * 0.84)
            pine(w * 0.12, h * 0.2, x: w * 0.28, y: h * 0.88)
            ForEach(0..<14, id: \.self) { i in
                Image(systemName: "snowflake")
                    .font(.system(size: CGFloat(8 + (i * 7) % 16)))
                    .foregroundStyle(.white.opacity(0.85))
                    .position(x: w * CGFloat(Double((i * 37) % 100) / 100), y: h * CGFloat(Double((i * 53) % 70) / 100))
            }
        }
    }

    // MARK: Minimalist — calm, almost-white gradient
    private func minimal(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#F7FBFE"), Color(hex: "#E4EFF8")], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hex: "#D3E6F6").opacity(0.7)).frame(width: w * 1.1).blur(radius: w * 0.12).position(x: w * 0.9, y: h * 0.9)
            Circle().fill(Color.white.opacity(0.9)).frame(width: w * 0.8).blur(radius: w * 0.1).position(x: w * 0.1, y: h * 0.1)
        }
    }

    // MARK: Retro — 2000s desktop: blue sky, soft clouds, rolling green hill
    private func retro(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#2B6FDB"), Color(hex: "#5C9CEE"), Color(hex: "#B7D8F7")], startPoint: .top, endPoint: .bottom)
            puff(w * 0.5, w * 0.05, h * 0.12, 0.75)
            puff(w * 0.35, w * 0.65, h * 0.2, 0.65)
            Ellipse()
                .fill(LinearGradient(colors: [Color(hex: "#7CCB3E"), Color(hex: "#4AA52A"), Color(hex: "#2F7E1C")], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 1.9, height: h * 0.75)
                .position(x: w * 0.35, y: h * 1.02)
            Ellipse()
                .fill(LinearGradient(colors: [Color(hex: "#68BB33"), Color(hex: "#3B8F22")], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 1.4, height: h * 0.5)
                .position(x: w * 1.05, y: h * 1.05)
        }
    }

    // MARK: helpers

    private func puff(_ width: CGFloat, _ x: CGFloat, _ y: CGFloat, _ opacity: Double) -> some View {
        CloudShape()
            .fill(LinearGradient(colors: [.white, Color(hex: "#E3F4FD")], startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: width * 0.45)
            .shadow(color: Color(hex: "#0B6FA8").opacity(0.15), radius: 6, y: 3)
            .opacity(opacity)
            .position(x: x + width / 2, y: y + width * 0.225)
    }

    private func leaf(_ length: CGFloat, _ x: CGFloat, _ y: CGFloat, _ angle: Double, _ light: String, _ dark: String) -> some View {
        ZStack {
            LeafShape().fill(LinearGradient(colors: [Color(hex: light), Color(hex: dark)], startPoint: .top, endPoint: .bottom))
            Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1.2).padding(.vertical, length * 0.06)
        }
        .frame(width: length * 0.42, height: length)
        .rotationEffect(.degrees(angle))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
        .position(x: x, y: y)
    }

    private func pine(_ width: CGFloat, _ height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        PineShape()
            .fill(LinearGradient(colors: [Color(hex: "#3E7FA0"), Color(hex: "#1F5370")], startPoint: .top, endPoint: .bottom))
            .overlay(PineShape(snow: true).fill(Color.white.opacity(0.9)))
            .frame(width: width, height: height)
            .position(x: x, y: y)
    }

    private func stars(_ w: CGFloat, _ h: CGFloat, count: Int, color: Color, seed: Int) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(color)
                    .frame(width: CGFloat(1 + (i * seed) % 3), height: CGFloat(1 + (i * seed) % 3))
                    .position(x: w * CGFloat(Double((i * 47 + seed * 13) % 100) / 100),
                              y: h * CGFloat(Double((i * 71 + seed * 29) % 100) / 100))
            }
        }
    }
}

/// Theme hero: backdrop + logo + tagline (like the welcome pane of classic Skype).
struct ThemeHero: View {
    @Environment(\.palette) private var palette
    var showTagline = true

    var body: some View {
        ZStack {
            ThemeBackdrop(kind: palette.backdrop)
            VStack(spacing: 8) {
                Image("ReSkyLogo").resizable().scaledToFit().frame(maxWidth: 240)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                if showTagline {
                    Text("The conversations never ended.")
                        .font(.resky(.headline, weight: .semibold))
                        .foregroundStyle(palette.backdrop == .minimal ? Color.reskyDeepBlue : .white)
                        .shadow(color: .black.opacity(palette.backdrop == .minimal ? 0 : 0.25), radius: 2, y: 1)
                }
            }
            .padding()
        }
    }
}

// MARK: - Shapes

struct PalmShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let base = CGPoint(x: r.minX + r.width * 0.35, y: r.maxY)
        let top = CGPoint(x: r.minX + r.width * 0.55, y: r.minY + r.height * 0.22)
        // trunk (tapered, slightly curved)
        p.move(to: CGPoint(x: base.x - r.width * 0.045, y: base.y))
        p.addQuadCurve(to: CGPoint(x: top.x - r.width * 0.015, y: top.y),
                       control: CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: top.x + r.width * 0.015, y: top.y))
        p.addQuadCurve(to: CGPoint(x: base.x + r.width * 0.045, y: base.y),
                       control: CGPoint(x: r.minX + r.width * 0.36, y: r.minY + r.height * 0.55))
        p.closeSubpath()
        // fronds
        let fronds: [(Double, Double)] = [(-170, 0.62), (-140, 0.55), (-110, 0.4), (-60, 0.42), (-25, 0.56), (5, 0.6), (35, 0.45), (150, 0.48)]
        for (deg, len) in fronds {
            let a = CGFloat(deg * .pi / 180)
            let L = r.width * CGFloat(len)
            let tip = CGPoint(x: top.x + cos(a) * L, y: top.y + sin(a) * L * 0.75 + L * 0.25)
            let mid = CGPoint(x: (top.x + tip.x) / 2, y: (top.y + tip.y) / 2 - L * 0.18)
            let nx: CGFloat = -sin(a) * L * 0.09
            let ny: CGFloat = cos(a) * L * 0.09
            p.move(to: top)
            p.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
            p.addQuadCurve(to: top, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
        }
        return p
    }
}

struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX + r.width * 0.25, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX - r.width * 0.25, y: r.midY))
        return p
    }
}

struct PineShape: Shape {
    var snow = false
    func path(in r: CGRect) -> Path {
        var p = Path()
        let tiers = 4
        for i in 0..<tiers {
            let topY = r.minY + r.height * CGFloat(i) * 0.2
            let botY = r.minY + r.height * (0.32 + CGFloat(i) * 0.2)
            let half = r.width * (0.2 + CGFloat(i) * 0.1)
            if snow {
                // snow caps on the upper part of each tier
                let capY = topY + (botY - topY) * 0.38
                let capHalf = half * 0.38
                p.move(to: CGPoint(x: r.midX, y: topY))
                p.addLine(to: CGPoint(x: r.midX + capHalf, y: capY))
                p.addQuadCurve(to: CGPoint(x: r.midX - capHalf, y: capY), control: CGPoint(x: r.midX, y: capY - (botY - topY) * 0.12))
                p.closeSubpath()
            } else {
                p.move(to: CGPoint(x: r.midX, y: topY))
                p.addLine(to: CGPoint(x: r.midX + half, y: botY))
                p.addLine(to: CGPoint(x: r.midX - half, y: botY))
                p.closeSubpath()
            }
        }
        if !snow {
            p.addRect(CGRect(x: r.midX - r.width * 0.05, y: r.maxY - r.height * 0.1, width: r.width * 0.1, height: r.height * 0.1))
        }
        return p
    }
}

/// Deterministic city skyline silhouette.
struct Skyline: Shape {
    var seed: Int
    var windows: Bool
    static func buildings(_ seed: Int) -> [(x: Double, w: Double, h: Double)] {
        var out: [(Double, Double, Double)] = []
        var x = 0.0, i = 0
        while x < 1.0 {
            let w = 0.05 + Double((i * 37 + seed * 11) % 9) / 100
            let h = 0.3 + Double((i * 53 + seed * 7) % 70) / 100
            out.append((x, w, h))
            x += w + 0.004
            i += 1
        }
        return out.map { (x: $0.0, w: $0.1, h: $0.2) }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        for b in Skyline.buildings(seed) {
            let rect = CGRect(x: r.minX + r.width * b.x, y: r.maxY - r.height * b.h, width: r.width * b.w, height: r.height * b.h)
            p.addRect(rect)
        }
        return p
    }
}

/// Lit windows for the neon skyline.
struct WindowsMask: Shape {
    var seed: Int
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (bi, b) in Skyline.buildings(seed).enumerated() {
            let bw = r.width * b.w, bh = r.height * b.h
            let x0 = r.minX + r.width * b.x, y0 = r.maxY - bh
            let cols = max(1, Int(bw / 6)), rows = max(1, Int(bh / 9))
            for row in 0..<rows {
                for col in 0..<cols where (row * 7 + col * 3 + bi * 5) % 4 == 0 {
                    p.addRect(CGRect(x: x0 + 2 + CGFloat(col) * 6, y: y0 + 4 + CGFloat(row) * 9, width: 2.4, height: 3.2))
                }
            }
        }
        return p
    }
}
