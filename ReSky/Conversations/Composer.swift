import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVKit

/// Movie picked from Photos, copied to a file we own.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

struct Composer: View {
    @Binding var text: String
    @Binding var replyTo: ChatMessage?
    @Binding var editing: ChatMessage?
    @ObservedObject var store: ChatStore
    var otherName: String?

    @Environment(\.palette) private var palette
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showEmoji = false
    @FocusState private var focused: Bool

    private let emojis = ["😀", "😂", "😊", "😍", "😎", "🤔", "😢", "😡", "👍", "👎", "👏", "🙏", "🎉", "❤️", "🔥", "☁️",
                          "🌈", "☀️", "🍕", "☕️", "🎮", "🎵", "📞", "💬", "😴", "🤣", "😇", "🥳", "😅", "🙌", "💯", "✨"]

    var body: some View {
        VStack(spacing: 0) {
            if let replyTo { contextBar(icon: "arrowshape.turn.up.left.fill", title: "Replying", text: replyTo.body ?? "Attachment") { self.replyTo = nil } }
            if let editing { contextBar(icon: "pencil", title: "Editing message", text: editing.body ?? "") { self.editing = nil; text = "" } }
            if showEmoji {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(emojis, id: \.self) { e in
                            Button(e) { text += e; Haptics.selection() }.font(.title2)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .background(palette.panel)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button { showPhotos = true } label: { Label("Photos & videos", systemImage: "photo.on.rectangle") }
                    Button { showFiles = true } label: { Label("Files & audio", systemImage: "doc") }
                } label: {
                    Image(systemName: "paperclip.circle.fill").font(.system(size: 28)).foregroundStyle(palette.primary)
                }
                .disabled(editing != nil)

                Button { withAnimation(.spring(response: 0.3)) { showEmoji.toggle() } } label: {
                    Image(systemName: showEmoji ? "keyboard" : "face.smiling").font(.system(size: 22)).foregroundStyle(palette.primary)
                }
                .padding(.bottom, 3)

                TextField(otherName.map { "Type a message to \($0)" } ?? "Type a message", text: $text, axis: .vertical)
                    .font(.resky(.body))
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 18).fill(palette.panel))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.border))
                    .onChange(of: text) { _, v in if !v.isEmpty { store.userIsTyping() } }

                Button { Task { await send() } } label: {
                    Image(systemName: editing != nil ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.reskyOffline : Color.reskyGreen)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                LinearGradient(colors: [palette.panel, palette.background], startPoint: .top, endPoint: .bottom)
                    .overlay(Rectangle().fill(palette.border).frame(height: 1), alignment: .top)
            )
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await sendPhotos(items) }
            photoItems = []
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        await store.sendAttachment(data: data, filename: url.lastPathComponent,
                                                   contentType: UTType(filenameExtension: url.pathExtension))
                    }
                }
            }
        }
    }

    private func contextBar(icon: String, title: String, text: String, onClose: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(palette.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.resky(.caption, weight: .bold)).foregroundStyle(palette.primary)
                Text(text).font(.resky(.caption)).foregroundStyle(palette.secondaryText).lineLimit(1)
            }
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondaryText) }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(palette.panel)
    }

    private func send() async {
        let value = text
        text = ""
        if let editing {
            self.editing = nil
            do { try await store.edit(editing, to: value) } catch { SessionStore.shared.banner = ReSkyError.message(error) }
            return
        }
        let reply = replyTo?.id
        replyTo = nil
        await store.sendText(value, replyTo: reply)
    }

    private func sendPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                if let movie = try? await item.loadTransferable(type: PickedMovie.self),
                   let data = try? Data(contentsOf: movie.url) {
                    await store.sendAttachment(data: data, filename: movie.url.lastPathComponent, contentType: .mpeg4Movie)
                    try? FileManager.default.removeItem(at: movie.url)
                }
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                // Keep GIFs/PNGs as-is; convert HEIC etc. to JPEG for compatibility
                let isGIF = ImageInspector.profileFormat(data)?.ext == "gif"
                let upload = isGIF ? data : (ImageInspector.jpeg(data) ?? data)
                let img = UIImage(data: upload)
                await store.sendAttachment(data: upload, filename: isGIF ? "image.gif" : "photo.jpg",
                                           contentType: isGIF ? .gif : .jpeg,
                                           width: img.map { Double($0.size.width) }, height: img.map { Double($0.size.height) })
            }
        }
    }
}

/// Full-screen viewer for images (pinch to zoom, save) and video/file playback.
struct MediaViewer: View {
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var fileURL: URL?
    @State private var player: AVPlayer?
    @State private var saved = false
    @State private var error: String?
    @EnvironmentObject private var transfers: TransferCenter

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                switch message.kind {
                case "image":
                    RemoteImage(bucket: "media", path: message.attachmentPath, contentMode: .fit)
                        .scaleEffect(scale)
                        .gesture(MagnificationGesture().onChanged { scale = max(1, $0) }.onEnded { _ in withAnimation { scale = 1 } })
                case "video":
                    if let player { VideoPlayer(player: player).onAppear { player.play() } } else { ProgressView().tint(.white) }
                default:
                    VStack(spacing: 14) {
                        Image(systemName: "doc.fill").font(.system(size: 60)).foregroundStyle(.white)
                        Text(message.attachmentMeta?.name ?? "File").foregroundStyle(.white)
                        if let p = transfers.progress[message.id] { ProgressView(value: p).tint(.white).frame(width: 200) }
                        if let fileURL { ShareLink(item: fileURL) { Label("Open / Share", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent) }
                    }
                }
                if let error { Text(error).foregroundStyle(.white).padding().background(Color.reskyDND.cornerRadius(8)) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(.white) }
                ToolbarItem(placement: .primaryAction) {
                    if message.kind == "image" || message.kind == "video" {
                        Button(saved ? "Saved" : "Save") { Task { await save() } }.disabled(saved).tint(.white)
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .task { await prepare() }
        }
    }

    private func prepare() async {
        guard let path = message.attachmentPath else { return }
        if message.kind == "video" {
            if let url = try? await StorageURLs.url(bucket: "media", path: path) { player = AVPlayer(url: url) }
        } else if message.kind != "image" {
            do { fileURL = try await TransferService.download(bucket: "media", path: path, id: message.id) }
            catch { self.error = "Download failed. Check your connection." }
        }
    }

    private func save() async {
        guard let path = message.attachmentPath else { return }
        do {
            if message.kind == "image" {
                let data = try await ImageLoader.shared.data(bucket: "media", path: path)
                guard let img = UIImage(data: data) else { return }
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            } else {
                let url = try await TransferService.download(bucket: "media", path: path, id: message.id)
                UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
            }
            saved = true
            Haptics.success()
        } catch {
            self.error = "Couldn't save. Check your connection."
        }
    }
}

struct ForwardSheet: View {
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss
    @StateObject private var inbox = InboxStore.shared
    @StateObject private var contacts = ContactsStore.shared
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List(inbox.conversations) { c in
                Button {
                    Task {
                        do { try await ChatStore.forward(message, to: c.id); Haptics.success(); dismiss() }
                        catch { self.error = ReSkyError.message(error) }
                    }
                } label: { ConversationRow(summary: c, other: contacts.profile(c.otherUserId)) }
                .buttonStyle(.plain)
            }
            .overlay(alignment: .bottom) { if let error { Text(error).padding().background(.thinMaterial) } }
            .navigationTitle("Forward to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
