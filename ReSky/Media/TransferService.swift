import Foundation
import Supabase

/// Uploads/downloads Storage objects over HTTPS with progress reporting.
@MainActor
final class TransferCenter: ObservableObject {
    static let shared = TransferCenter()
    /// Progress 0...1 keyed by message id (or any transfer id).
    @Published var progress: [UUID: Double] = [:]
    @Published var failed: Set<UUID> = []
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (Double) -> Void
    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

enum TransferService {
    private static func authorizedRequest(_ url: URL, method: String) async throws -> URLRequest {
        let token = try await supabase.auth.session.accessToken
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        return req
    }

    /// Uploads `data` to bucket/path. `id` is used to publish progress.
    static func upload(bucket: String, path: String, data: Data, contentType: String, id: UUID) async throws {
        let url = AppConfig.supabaseURL.appendingPathComponent("storage/v1/object/\(bucket)/\(path)")
        var req = try await authorizedRequest(url, method: "POST")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.setValue("3600", forHTTPHeaderField: "cache-control")
        await MainActor.run {
            TransferCenter.shared.progress[id] = 0
            TransferCenter.shared.failed.remove(id)
        }
        let delegate = UploadProgressDelegate { p in
            Task { @MainActor in TransferCenter.shared.progress[id] = p }
        }
        do {
            let (body, resp) = try await URLSession.shared.upload(for: req, from: data, delegate: delegate)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let text = String(data: body, encoding: .utf8) ?? "Upload failed"
                throw NSError(domain: "ReSkyUpload", code: (resp as? HTTPURLResponse)?.statusCode ?? 0,
                              userInfo: [NSLocalizedDescriptionKey: text])
            }
            await MainActor.run { TransferCenter.shared.progress[id] = nil }
        } catch {
            await MainActor.run {
                TransferCenter.shared.progress[id] = nil
                TransferCenter.shared.failed.insert(id)
            }
            throw error
        }
    }

    /// Downloads an object to a file in Caches, reporting progress.
    static func download(bucket: String, path: String, id: UUID) async throws -> URL {
        let dest = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReSkyDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let file = dest.appendingPathComponent((path as NSString).lastPathComponent)
        if FileManager.default.fileExists(atPath: file.path) { return file }

        let url = try await StorageURLs.url(bucket: bucket, path: path)
        let (bytes, resp) = try await URLSession.shared.bytes(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let expected = max(resp.expectedContentLength, 1)
        var data = Data()
        data.reserveCapacity(Int(max(expected, 0)))
        var last = 0
        await MainActor.run { TransferCenter.shared.progress[id] = 0 }
        for try await byte in bytes {
            data.append(byte)
            if data.count - last > 65_536 {
                last = data.count
                let p = Double(data.count) / Double(expected)
                await MainActor.run { TransferCenter.shared.progress[id] = min(p, 1) }
            }
        }
        try data.write(to: file)
        await MainActor.run { TransferCenter.shared.progress[id] = nil }
        return file
    }

    /// Server-side copy (used for forwarding attachments into another conversation).
    static func copy(bucket: String, from: String, to: String) async throws {
        let url = AppConfig.supabaseURL.appendingPathComponent("storage/v1/object/copy")
        var req = try await authorizedRequest(url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["bucketId": bucket, "sourceKey": from, "destinationKey": to])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
}
