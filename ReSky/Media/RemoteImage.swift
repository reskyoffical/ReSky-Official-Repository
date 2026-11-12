import SwiftUI
import Supabase

/// Loads images from Supabase Storage with memory + disk caching.
/// Public bucket ("profile") uses public URLs; private bucket ("media") uses signed URLs.
actor ImageLoader {
    static let shared = ImageLoader()
    private let memory = NSCache<NSString, NSData>()
    private var inflight: [String: Task<Data, Error>] = [:]
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ReSkyImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func data(bucket: String, path: String) async throws -> Data {
        let key = "\(bucket)/\(path)"
        if let d = memory.object(forKey: key as NSString) { return d as Data }
        let file = dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_"))
        if let d = try? Data(contentsOf: file) {
            memory.setObject(d as NSData, forKey: key as NSString)
            return d
        }
        if let t = inflight[key] { return try await t.value }
        let task = Task<Data, Error> {
            let url = try await StorageURLs.url(bucket: bucket, path: path)
            let (d, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return d
        }
        inflight[key] = task
        defer { inflight[key] = nil }
        let d = try await task.value
        memory.setObject(d as NSData, forKey: key as NSString)
        try? d.write(to: file)
        return d
    }

    func store(_ data: Data, bucket: String, path: String) {
        let key = "\(bucket)/\(path)"
        memory.setObject(data as NSData, forKey: key as NSString)
        try? data.write(to: dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_")))
    }
}

enum StorageURLs {
    static func url(bucket: String, path: String) async throws -> URL {
        if bucket == "profile" {
            return try supabase.storage.from(bucket).getPublicURL(path: path)
        }
        return try await supabase.storage.from(bucket).createSignedURL(path: path, expiresIn: 3600)
    }
}

struct RemoteImage: View {
    let bucket: String
    let path: String?
    var animate = true
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                if image.images != nil {
                    AnimatedImageView(image: image, contentMode: contentMode == .fill ? .scaleAspectFill : .scaleAspectFit)
                } else {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                }
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else if path != nil {
                ProgressView()
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        guard let path else { image = nil; return }
        do {
            let d = try await ImageLoader.shared.data(bucket: bucket, path: path)
            let shouldAnimate = animate
            let img = await Task.detached { ImageInspector.uiImage(d, animate: shouldAnimate) }.value
            image = img
        } catch {
            failed = true
        }
    }
}

/// Round avatar with presence badge and optional cosmetic border.
struct AvatarView: View {
    let profile: ProfileCard?
    var size: CGFloat = 44
    var showStatus = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let path = profile?.avatarPath {
                    RemoteImage(bucket: "profile", path: path, animate: profile?.avatarAnimated ?? false)
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(hex: "#8FD8F8"), .reskyBlue], startPoint: .top, endPoint: .bottom)
                        Text(initials).font(.system(size: size * 0.38, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay(ProfileBorder(borderId: profile?.borderId ?? "none", cornerRadius: size * 0.22))

            if showStatus, let p = profile {
                StatusIcon(status: p.status, size: max(12, size * 0.32)).offset(x: size * 0.08, y: size * 0.08)
            }
        }
    }

    private var initials: String {
        let name = profile?.displayName ?? "?"
        return name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

/// Draws the selected border cosmetic (animated ones rotate their gradient).
struct ProfileBorder: View {
    let borderId: String
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        let colors = BorderCatalog.colors(for: borderId)
        if colors.isEmpty {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Color.white.opacity(0.8), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AngularGradient(colors: colors + [colors[0]], center: .center, angle: .degrees(spin ? 360 : 0)), lineWidth: 3)
                .shadow(color: (colors.first ?? .clear).opacity(BorderCatalog.glows(borderId) ? 0.8 : 0), radius: 4)
                .onAppear {
                    guard BorderCatalog.animated(borderId), !reduceMotion else { return }
                    withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true }
                }
        }
    }
}

enum BorderCatalog {
    static func colors(for id: String) -> [Color] {
        switch id {
        case "classic_blue": return [.reskyBlue]
        case "online_green": return [.reskyGreen]
        case "rainbow": return ["#FF5F6D", "#FFC371", "#7FBA00", "#00AFF0", "#8E44AD"].map { Color(hex: $0) }
        case "glow_cloud": return [.white, .reskyBlue]
        case "founder_gold": return ["#FFD86B", "#F5A623", "#FFF4C2"].map { Color(hex: $0) }
        default: return []
        }
    }
    static func animated(_ id: String) -> Bool { ["rainbow", "glow_cloud", "founder_gold"].contains(id) }
    static func glows(_ id: String) -> Bool { ["glow_cloud", "founder_gold"].contains(id) }
}
