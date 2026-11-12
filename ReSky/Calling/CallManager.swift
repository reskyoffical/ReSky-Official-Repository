import Foundation
import LiveKit
import Supabase
import AVFoundation

/// Call signalling runs through the `calls` table (Realtime); audio/video flows through LiveKit (WebRTC).
@MainActor
final class CallManager: ObservableObject {
    static let shared = CallManager()

    enum Phase: Equatable { case outgoing, incoming, connecting, active, ended(String) }

    struct ActiveCall: Equatable {
        let id: UUID
        let peer: ProfileCard
        let isVideo: Bool
        let isCaller: Bool
    }

    @Published var activeCall: ActiveCall?
    @Published var incoming: ActiveCall?
    @Published var phase: Phase = .outgoing
    @Published var room: Room?
    @Published var micMuted = false
    @Published var cameraOn = true
    @Published var speakerOn = false
    @Published var connectedAt: Date?
    @Published var errorText: String?

    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    struct TokenResponse: Decodable { let token: String; let url: String }

    func start() {
        guard channel == nil, let me = SessionStore.shared.userId else { return }
        Task {
            let ch = supabase.channel("calls-\(me.lc)")
            let changes = ch.postgresChange(AnyAction.self, schema: "public", table: "calls")
            await ch.subscribe()
            channel = ch
            listenTask = Task { [weak self] in
                for await change in changes {
                    guard let self else { return }
                    switch change {
                    case .insert(let a):
                        if let c = try? a.decodeRecord(as: CallRecord.self, decoder: JSONDecoder()) { await self.handleInsert(c) }
                    case .update(let a):
                        if let c = try? a.decodeRecord(as: CallRecord.self, decoder: JSONDecoder()) { await self.handleUpdate(c) }
                    default: break
                    }
                }
            }
        }
    }

    func stop() {
        listenTask?.cancel()
        if let channel { Task { await supabase.removeChannel(channel) } }
        channel = nil
        Task { await teardown(reason: "") }
    }

    // MARK: Outgoing

    func startCall(to peer: ProfileCard, video: Bool) {
        guard activeCall == nil else { return }
        if SessionStore.shared.isSuspended { SessionStore.shared.banner = "Your account is suspended."; return }
        Task {
            do {
                struct P: Encodable { let callee: UUID; let call_kind: String }
                let id: UUID = try await supabase.rpc("start_call", params: P(callee: peer.id, call_kind: video ? "video" : "voice")).execute().value
                activeCall = ActiveCall(id: id, peer: peer, isVideo: video, isCaller: true)
                cameraOn = video
                phase = .outgoing
                SoundManager.shared.startLoop(.ringOutgoing)
                Haptics.medium()
                try await connect(callId: id, video: video)
                timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: 45_000_000_000)
                    if !Task.isCancelled, self.phase == .outgoing { await self.hangUp(note: "No answer") }
                }
            } catch {
                errorText = ReSkyError.message(error)
                SessionStore.shared.banner = "Couldn't start the call: \(ReSkyError.message(error))"
                SoundManager.shared.play(.error)
                await teardown(reason: "")
            }
        }
    }

    // MARK: Incoming

    private func handleInsert(_ c: CallRecord) async {
        guard c.calleeId == SessionStore.shared.userId, c.status == "ringing" else { return }
        guard activeCall == nil, incoming == nil else {
            struct P: Encodable { let call: UUID }
            try? await supabase.rpc("decline_call", params: P(call: c.id)).execute() // busy
            return
        }
        if SessionStore.shared.me?.status == .dnd { return } // shows as missed
        let cards = (try? await ContactsStore.shared.loadProfiles([c.callerId])) ?? []
        guard let peer = cards.first else { return }
        incoming = ActiveCall(id: c.id, peer: peer, isVideo: c.isVideo, isCaller: false)
        phase = .incoming
        SoundManager.shared.startLoop(.ringIncoming)
        Haptics.medium()
    }

    func accept() {
        guard let call = incoming else { return }
        SoundManager.shared.stopLoop()
        Task {
            do {
                struct P: Encodable { let call: UUID }
                try await supabase.rpc("answer_call", params: P(call: call.id)).execute()
                activeCall = call
                incoming = nil
                cameraOn = call.isVideo
                phase = .connecting
                try await connect(callId: call.id, video: call.isVideo)
                markConnected()
            } catch {
                SessionStore.shared.banner = ReSkyError.message(error)
                await teardown(reason: "")
            }
        }
    }

    func decline() {
        guard let call = incoming else { return }
        SoundManager.shared.stopLoop()
        incoming = nil
        Task {
            struct P: Encodable { let call: UUID }
            try? await supabase.rpc("decline_call", params: P(call: call.id)).execute()
        }
    }

    private func handleUpdate(_ c: CallRecord) async {
        if let inc = incoming, inc.id == c.id, c.status != "ringing" {
            SoundManager.shared.stopLoop()
            incoming = nil
            return
        }
        guard let call = activeCall, call.id == c.id else { return }
        switch c.status {
        case "active" where call.isCaller:
            markConnected()
        case "declined":
            await teardown(reason: "\(call.peer.displayName) declined the call")
        case "ended", "missed":
            await teardown(reason: "Call ended")
        default: break
        }
    }

    private func markConnected() {
        timeoutTask?.cancel()
        SoundManager.shared.stopLoop()
        SoundManager.shared.play(.callConnected)
        phase = .active
        connectedAt = Date()
        Haptics.success()
    }

    // MARK: Media

    private func connect(callId: UUID, video: Bool) async throws {
        struct Body: Encodable { let call_id: UUID }
        let res: TokenResponse = try await supabase.functions.invoke("livekit-token", options: FunctionInvokeOptions(body: Body(call_id: callId)))
        let r = Room()
        room = r
        try await r.connect(url: res.url, token: res.token)
        try await r.localParticipant.setMicrophone(enabled: true)
        if video { try await r.localParticipant.setCamera(enabled: true) }
        AudioManager.shared.isSpeakerOutputPreferred = video
        speakerOn = video
    }

    func toggleMute() {
        micMuted.toggle()
        Task { try? await room?.localParticipant.setMicrophone(enabled: !micMuted) }
        Haptics.tap()
    }

    func toggleCamera() {
        cameraOn.toggle()
        Task { try? await room?.localParticipant.setCamera(enabled: cameraOn) }
        Haptics.tap()
    }

    func switchCamera() {
        Task {
            if let track = room?.localParticipant.firstCameraVideoTrack as? LocalVideoTrack,
               let capturer = track.capturer as? CameraCapturer {
                _ = try? await capturer.switchCameraPosition()
            }
        }
        Haptics.tap()
    }

    func toggleSpeaker() {
        speakerOn.toggle()
        AudioManager.shared.isSpeakerOutputPreferred = speakerOn
        Haptics.tap()
    }

    func hangUp(note: String = "Call ended") async {
        if let call = activeCall {
            struct P: Encodable { let call: UUID }
            try? await supabase.rpc("end_call", params: P(call: call.id)).execute()
        }
        await teardown(reason: note)
    }

    private func teardown(reason: String) async {
        timeoutTask?.cancel()
        SoundManager.shared.stopLoop()
        let hadCall = activeCall != nil
        if let r = room { await r.disconnect() }
        room = nil
        if hadCall {
            SoundManager.shared.play(.callEnded)
            phase = .ended(reason)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
        activeCall = nil
        connectedAt = nil
        micMuted = false
        speakerOn = false
        if incoming == nil { phase = .outgoing }
    }
}
