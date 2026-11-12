import SwiftUI
import AVKit

/// Classic Skype-style message: small name/time header, rounded bubble, reactions below.
struct MessageBubble: View {
    let message: ChatMessage
    let sender: ProfileCard?
    let isMine: Bool
    let showHeader: Bool
    let replied: ChatMessage?
    let reactions: [Reaction]
    let pending: Bool
    let seen: Bool
    var onReact: (String) -> Void
    var onOpenMedia: () -> Void

    @Environment(\.palette) private var palette
    @EnvironmentObject private var transfers: TransferCenter
    @EnvironmentObject private var outbox: Outbox

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isMine { Spacer(minLength: 40) }
            if !isMine {
                AvatarView(profile: sender, size: 30, showStatus: false).opacity(showHeader ? 1 : 0)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if showHeader {
                    HStack(spacing: 6) {
                        Text(isMine ? "You" : (sender?.displayName ?? "")).font(.resky(.caption, weight: .bold))
                            .foregroundStyle(isMine ? palette.primary : palette.text)
                        Text(message.date.formatted(date: .omitted, time: .shortened))
                            .font(.resky(.caption2)).foregroundStyle(palette.secondaryText)
                    }
                }
                bubble
                if !reactions.isEmpty { reactionRow }
                statusLine
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.forwardedFrom != nil {
                Label("Forwarded", systemImage: "arrowshape.turn.up.right.fill")
                    .font(.resky(.caption2)).foregroundStyle(palette.secondaryText)
            }
            if let replied {
                HStack(spacing: 6) {
                    Rectangle().fill(palette.primary).frame(width: 3)
                    Text(replied.isDeleted ? "Deleted message" : (replied.body ?? "Attachment"))
                        .font(.resky(.caption)).foregroundStyle(palette.secondaryText).lineLimit(2)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if message.isDeleted {
                Text("This message was deleted").font(.resky(.subheadline)).italic().foregroundStyle(palette.secondaryText)
            } else if message.isMedia {
                AttachmentView(message: message, onOpen: onOpenMedia)
            } else {
                Text(message.body ?? "").font(.resky(.body)).foregroundStyle(palette.text)
                    .textSelection(.enabled)
            }
            if let p = transfers.progress[message.id] {
                ProgressView(value: p).tint(palette.primary).frame(minWidth: 120)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isMine ? palette.ownBubble : palette.otherBubble)
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
        .opacity(pending ? 0.75 : 1)
    }

    private var reactionRow: some View {
        let grouped = Dictionary(grouping: reactions, by: \.emoji).sorted { $0.value.count > $1.value.count }
        return HStack(spacing: 4) {
            ForEach(grouped, id: \.key) { emoji, list in
                Button { onReact(emoji) } label: {
                    Text("\(emoji) \(list.count)").font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(palette.panel))
                        .overlay(Capsule().stroke(palette.border))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if pending {
            HStack(spacing: 4) {
                if transfers.failed.contains(message.id) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.reskyDND)
                    Button("Retry") { Task { await outbox.retry(message.id) } }.font(.resky(.caption2, weight: .bold))
                } else {
                    Image(systemName: "clock").foregroundStyle(palette.secondaryText)
                    Text("Sending…")
                }
            }
            .font(.resky(.caption2)).foregroundStyle(palette.secondaryText)
        } else if message.editedAt != nil || seen {
            HStack(spacing: 4) {
                if message.editedAt != nil { Text("Edited") }
                if seen { Image(systemName: "eye.fill"); Text("Seen") }
            }
            .font(.resky(.caption2)).foregroundStyle(palette.secondaryText)
        }
    }
}

struct AttachmentView: View {
    let message: ChatMessage
    var onOpen: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        switch message.kind {
        case "image":
            Button(action: onOpen) {
                RemoteImage(bucket: "media", path: message.attachmentPath, contentMode: .fill)
                    .frame(width: 220, height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        case "video":
            Button(action: onOpen) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.85))
                    Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white)
                }
                .frame(width: 220, height: 140)
            }
            .buttonStyle(.plain)
        default:
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: message.kind == "audio" ? "waveform.circle.fill" : "doc.fill")
                        .font(.title2).foregroundStyle(palette.primary)
                    VStack(alignment: .leading) {
                        Text(message.attachmentMeta?.name ?? "File").font(.resky(.subheadline, weight: .semibold)).lineLimit(1)
                        if let size = message.attachmentMeta?.size {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                .font(.resky(.caption)).foregroundStyle(palette.secondaryText)
                        }
                    }
                    Image(systemName: "arrow.down.circle").foregroundStyle(palette.primary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var imageHeight: CGFloat {
        guard let w = message.attachmentMeta?.width, let h = message.attachmentMeta?.height, w > 0 else { return 180 }
        return min(max(220 * h / w, 90), 320)
    }
}
