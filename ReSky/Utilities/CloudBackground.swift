import SwiftUI

/// Original cloud shape made of overlapping circles.
struct CloudShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addEllipse(in: CGRect(x: r.minX, y: r.minY + h * 0.35, width: w * 0.42, height: h * 0.6))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.2, y: r.minY + h * 0.05, width: w * 0.42, height: h * 0.8))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.45, y: r.minY + h * 0.18, width: w * 0.38, height: h * 0.7))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.62, y: r.minY + h * 0.4, width: w * 0.38, height: h * 0.55))
        p.addRoundedRect(in: CGRect(x: r.minX + w * 0.12, y: r.minY + h * 0.55, width: w * 0.78, height: h * 0.45),
                         cornerSize: CGSize(width: h * 0.2, height: h * 0.2))
        return p
    }
}

/// Classic blue sky with slowly drifting white clouds (static when Reduce Motion is on).
struct CloudBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var dimmed = false

    private let clouds: [(x: CGFloat, y: CGFloat, w: CGFloat, speed: Double, opacity: Double)] = [
        (0.05, 0.08, 0.55, 0.010, 0.95), (0.6, 0.18, 0.45, 0.014, 0.85), (-0.1, 0.42, 0.4, 0.008, 0.7),
        (0.55, 0.62, 0.6, 0.011, 0.75), (0.1, 0.82, 0.5, 0.013, 0.9), (0.75, 0.9, 0.35, 0.009, 0.6),
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    LinearGradient(colors: [Color(hex: "#0FB3F2"), Color(hex: "#47C6F5"), Color(hex: "#9EE0FA")],
                                   startPoint: .top, endPoint: .bottom)
                    ForEach(0..<clouds.count, id: \.self) { i in
                        let c = clouds[i]
                        let width = geo.size.width * c.w
                        let span = geo.size.width + width
                        let drift = reduceMotion ? 0 : CGFloat((t * c.speed).truncatingRemainder(dividingBy: 1)) * span
                        let x = (geo.size.width * c.x + drift).truncatingRemainder(dividingBy: span) - width * 0.3
                        CloudShape()
                            .fill(LinearGradient(colors: [.white, Color(hex: "#E6F6FE")], startPoint: .top, endPoint: .bottom))
                            .frame(width: width, height: width * 0.45)
                            .shadow(color: Color(hex: "#0B7FB8").opacity(0.18), radius: 8, y: 4)
                            .opacity(c.opacity * (dimmed ? 0.5 : 1))
                            .position(x: x + width / 2, y: geo.size.height * c.y)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
