import Foundation
import Supabase
import UIKit

@MainActor
final class CustomisationStore: ObservableObject {
    static let shared = CustomisationStore()
    @Published var items: [CosmeticItem] = []
    @Published var assets: [ProfileAsset] = []
    @Published var uploading = false
    @Published var message: String?

    static let freeAccents = ["#00AFF0", "#7FBA00", "#FF8C00", "#E3008C", "#8E44AD", "#2C3E50"]

    func load() async {
        items = (try? await supabase.from("cosmetic_items").select().order("sort_order").execute().value) ?? []
        if let uid = SessionStore.shared.userId {
            assets = (try? await supabase.from("profile_assets").select().eq("user_id", value: uid.lc)
                .order("created_at", ascending: false).execute().value) ?? []
        }
    }

    func items(_ kind: String) -> [CosmeticItem] { items.filter { $0.kind == kind } }

    /// Updates profile columns; the server rejects premium choices without Plus ("plus_required").
    func update(_ values: [String: AnyJSON]) async -> Bool {
        guard let uid = SessionStore.shared.userId else { return false }
        do {
            try await supabase.from("profiles").update(values).eq("id", value: uid.lc).execute()
            await SessionStore.shared.loadProfile()
            Haptics.success()
            return true
        } catch {
            if ReSkyError.code(error) == "plus_required" {
                PlusStore.shared.showPaywall = true
            } else {
                message = ReSkyError.message(error)
                SoundManager.shared.play(.error)
            }
            return false
        }
    }

    func choose(_ item: CosmeticItem) async {
        let column: String
        switch item.kind {
        case "theme": column = "theme_id"
        case "border": column = "border_id"
        default: column = "decoration_id"
        }
        if item.isPremium && !PlusStore.shared.requirePlus() { return }
        _ = await update([column: .string(item.id)])
    }

    /// Uploads profile artwork. Animated uploads are kept even for free users, just locked.
    func upload(_ raw: Data, kind: String) async {
        guard let uid = SessionStore.shared.userId else { return }
        uploading = true
        defer { uploading = false }
        var data = raw
        var format = ImageInspector.profileFormat(data)
        if format == nil {
            guard let jpg = ImageInspector.jpeg(data, maxPixel: kind == "avatar" ? 1024 : 2400) else {
                message = "That image format isn't supported."
                return
            }
            data = jpg
            format = ("jpg", "image/jpeg")
        }
        guard let fmt = format else { return }
        guard data.count <= AppConfig.maxProfileImageBytes else {
            message = "Images must be 10 MB or smaller."
            return
        }
        let animated = ImageInspector.isAnimated(data)
        let id = UUID().uuidString.lowercased()
        let path = "\(uid.lc)/\(kind)-\(id).\(fmt.ext)"
        var staticPath: String?
        do {
            try await TransferService.upload(bucket: "profile", path: path, data: data, contentType: fmt.mime, id: UUID())
            if animated, let still = ImageInspector.firstFramePNG(data) {
                staticPath = "\(uid.lc)/\(kind)-\(id)-still.png"
                try await TransferService.upload(bucket: "profile", path: staticPath!, data: still, contentType: "image/png", id: UUID())
            }
            struct Body: Encodable { let path: String; let static_path: String?; let kind: String }
            struct Res: Decodable { let asset: ProfileAsset; let is_animated: Bool; let locked: Bool }
            let res: Res = try await supabase.functions.invoke("register-profile-asset",
                                                              options: FunctionInvokeOptions(body: Body(path: path, static_path: staticPath, kind: kind)))
            await ImageLoader.shared.store(data, bucket: "profile", path: path)
            await load()
            if res.locked {
                message = "Saved! Animated artwork is a ReSky Plus feature — it's kept in your uploads and unlocks when you subscribe."
                PlusStore.shared.showPaywall = true
            } else {
                await apply(res.asset)
            }
        } catch {
            message = ReSkyError.message(error)
            SoundManager.shared.play(.error)
        }
    }

    func apply(_ asset: ProfileAsset) async {
        if asset.isAnimated && !PlusStore.shared.requirePlus() { return }
        let column: String
        switch asset.kind {
        case "avatar": column = "avatar_asset_id"
        case "banner": column = "banner_asset_id"
        default: column = "background_asset_id"
        }
        _ = await update([column: .string(asset.id.lc)])
    }

    func clear(_ kind: String) async {
        let column = kind == "avatar" ? "avatar_asset_id" : kind == "banner" ? "banner_asset_id" : "background_asset_id"
        _ = await update([column: .null])
    }

    func delete(_ asset: ProfileAsset) async {
        try? await supabase.from("profile_assets").delete().eq("id", value: asset.id.lc).execute()
        var paths = [asset.path]
        if let s = asset.staticPath, s != asset.path { paths.append(s) }
        _ = try? await supabase.storage.from("profile").remove(paths: paths)
        await load()
        await SessionStore.shared.loadProfile()
    }
}
