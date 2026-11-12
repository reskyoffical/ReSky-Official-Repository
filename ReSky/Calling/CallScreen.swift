import SwiftUI
import LiveKit

struct CallScreen: View {
    @EnvironmentObject private var calls: CallManager

    var body: some View {
        ZStack {
            if let inc = calls.incoming, calls.activeCall == nil {
                IncomingCallView(call: inc)
            } else if let call = calls.activeCall {
                ActiveCallView(call: call)
            }
        }
        .ignoresSafeArea()
    }
}

struct IncomingCallView: View {
    let call: CallManager.ActiveCall
    @EnvironmentObject private var calls: CallManager
    @State private var pulse = false

    var body: some View {
        ZStack {
            CloudBackground(dimmed: true)
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    Circle().stroke(Color.white.opacity(0.5), lineWidth: 2).frame(width: 170, height: 170)
                        .scaleEffect(pulse ? 1.25 : 1).opacity(pulse ? 0 : 1)
                    AvatarView(profile: call.peer, size: 130, showStatus: false)
                }
                .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
                Text(call.peer.displayName).font(.resky(.largeTitle, weight: .bold)).foregroundStyle(.white)
                Text(call.isVideo ? "Incoming video call…" : "Incoming call…").font(.resky(.title3)).foregroundStyle(.white.opacity(0.9))
                Spacer()
                HStack(spacing: 70) {
                    CallCircleButton(symbol: "phone.down.fill", color: .reskyDND, label: "Decline") { calls.decline() }
                    CallCircleButton(symbol: call.isVideo ? "video.fill" : "phone.fill", color: .reskyGreen, label: "Answer") { calls.accept() }
                }
                .padding(.bottom, 60)
            }
        }
    }
}

struct ActiveCallView: View {
    let call: CallManager.ActiveCall
    @EnvironmentObject private var calls: CallManager

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#0A2E4A"), Color(hex: "#0B1724")], startPoint: .top, endPoint: .bottom)
            if let room = calls.room, call.isVideo {
                CallVideoLayer(room: room, cameraOn: calls.cameraOn)
            }
            VStack(spacing: 10) {
                if !call.isVideo || calls.phase != .active {
                    Spacer()
                    AvatarView(profile: call.peer, size: 120, showStatus: false)
                }
                Text(call.peer.displayName).font(.resky(.title, weight: .bold)).foregroundStyle(.white)
                    .shadow(radius: 4)
                statusText.font(.resky(.headline)).foregroundStyle(.white.opacity(0.85)).shadow(radius: 4)
                Spacer()
                HStack(spacing: 22) {
                    CallCircleButton(symbol: calls.micMuted ? "mic.slash.fill" : "mic.fill",
                                     color: calls.micMuted ? .white : Color.white.opacity(0.2),
                                     iconColor: calls.micMuted ? .black : .white, label: "Mute") { calls.toggleMute() }
                    if call.isVideo {
                        CallCircleButton(symbol: calls.cameraOn ? "video.fill" : "video.slash.fill",
                                         color: Color.white.opacity(0.2), label: "Camera") { calls.toggleCamera() }
                        CallCircleButton(symbol: "arrow.triangle.2.circlepath.camera.fill",
                                         color: Color.white.opacity(0.2), label: "Flip") { calls.switchCamera() }
                    }
                    CallCircleButton(symbol: calls.speakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                                     color: calls.speakerOn ? .white : Color.white.opacity(0.2),
                                     iconColor: calls.speakerOn ? .black : .white, label: "Speaker") { calls.toggleSpeaker() }
                }
                CallCircleButton(symbol: "phone.down.fill", color: .reskyDND, label: "End") {
                    Task { await calls.hangUp() }
                }
                .padding(.top, 8)
                .padding(.bottom, 50)
            }
            .padding(.top, 70)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch calls.phase {
        case .outgoing: Text("Calling…")
        case .incoming, .connecting: Text("Connecting…")
        case .active:
            if let start = calls.connectedAt {
                TimelineView(.periodic(from: start, by: 1)) { ctx in
                    Text(Self.duration(ctx.date.timeIntervalSince(start)))
                }
            }
        case .ended(let reason): Text(reason)
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Remote video full screen with a draggable local preview.
struct CallVideoLayer: View {
    @ObservedObject var room: Room
    var cameraOn: Bool
    @State private var previewOffset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                if let remote = room.remoteParticipants.values.first {
                    ParticipantVideo(participant: remote, mirror: false)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                if cameraOn {
                    ParticipantVideo(participant: room.localParticipant, mirror: true)
                        .frame(width: 110, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.7), lineWidth: 1.5))
                        .shadow(radius: 8)
                        .padding(.top, 60).padding(.trailing, 16)
                        .offset(x: previewOffset.width + drag.width, y: previewOffset.height + drag.height)
                        .gesture(DragGesture()
                            .updating($drag) { v, s, _ in s = v.translation }
                            .onEnded { v in previewOffset.width += v.translation.width; previewOffset.height += v.translation.height })
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Observes a participant so the view updates when its camera track is published/subscribed.
struct ParticipantVideo: View {
    @ObservedObject var participant: Participant
    var mirror: Bool
    var body: some View {
        if let track = participant.firstCameraVideoTrack {
            SwiftUIVideoView(track, layoutMode: .fill, mirrorMode: mirror ? .mirror : .off)
        } else {
            Color.black.opacity(0.4)
        }
    }
}

struct CallCircleButton: View {
    let symbol: String
    let color: Color
    var iconColor: Color = .white
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(color)
                    Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(iconColor)
                }
                .frame(width: 66, height: 66)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                Text(label).font(.resky(.caption)).foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct CallHistoryView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var calls: CallManager
    @StateObject private var contacts = ContactsStore.shared
    @Environment(\.palette) private var palette
    @State private var records: [CallRecord] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && records.isEmpty {
                Text("No calls yet").font(.resky(.subheadline)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear)
            }
            ForEach(records) { r in
                let outgoing = r.callerId == session.userId
                let peer = contacts.profile(outgoing ? r.calleeId : r.callerId)
                let missed = !outgoing && (r.status == "missed" || r.status == "declined")
                HStack(spacing: 12) {
                    AvatarView(profile: peer, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer?.displayName ?? "Unknown").font(.resky(.body, weight: .semibold))
                            .foregroundStyle(missed ? Color.reskyDND : palette.text)
                        HStack(spacing: 4) {
                            Image(systemName: outgoing ? "arrow.up.right" : "arrow.down.left")
                            Image(systemName: r.isVideo ? "video.fill" : "phone.fill")
                            Text(describe(r, outgoing: outgoing))
                        }
                        .font(.resky(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(DateParser.shortTime(DateParser.parse(r.createdAt))).font(.resky(.caption)).foregroundStyle(.secondary)
                        Text(DateParser.parse(r.createdAt).formatted(date: .omitted, time: .shortened)).font(.resky(.caption2)).foregroundStyle(.secondary)
                    }
                    if let peer {
                        Button { calls.startCall(to: peer, video: r.isVideo) } label: {
                            Image(systemName: r.isVideo ? "video.circle.fill" : "phone.circle.fill").font(.title2).foregroundStyle(Color.reskyGreen)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("Calls")
        .classicNavBar()
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: calls.activeCall == nil) { _, _ in Task { await load() } }
    }

    private func describe(_ r: CallRecord, outgoing: Bool) -> String {
        switch r.status {
        case "missed": return outgoing ? "No answer" : "Missed"
        case "declined": return "Declined"
        case "ringing": return "Ringing"
        case "active": return "In progress"
        default:
            if let d = r.durationSeconds { return ActiveCallView.duration(TimeInterval(d)) }
            return "Ended"
        }
    }

    private func load() async {
        records = (try? await supabase.from("calls").select().order("created_at", ascending: false).limit(100).execute().value) ?? []
        loaded = true
        await contacts.ensureProfiles(records.flatMap { [$0.callerId, $0.calleeId] })
    }
}
