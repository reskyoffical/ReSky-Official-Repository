import AVFoundation
import SwiftUI

/// Plays ReSky's original sound set (all sounds in Audio/ were created for ReSky).
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    enum Sound: String, CaseIterable, Identifiable {
        case startup = "resky_startup_chime"
        case messageIn = "resky_message_in"
        case messageOut = "resky_message_out"
        case ringIncoming = "resky_ring_incoming"
        case ringOutgoing = "resky_ring_outgoing"
        case callConnected = "resky_call_connected"
        case callEnded = "resky_call_ended"
        case contactOnline = "resky_contact_online"
        case contactOffline = "resky_contact_offline"
        case notification = "resky_notification"
        case error = "resky_error"
        case click = "resky_click"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .startup: return "App startup (intro)"
            case .messageIn: return "Incoming message"
            case .messageOut: return "Outgoing message"
            case .ringIncoming: return "Incoming call"
            case .ringOutgoing: return "Outgoing call"
            case .callConnected: return "Call connected"
            case .callEnded: return "Call ended"
            case .contactOnline: return "Contact comes online"
            case .contactOffline: return "Contact goes offline"
            case .notification: return "Notification"
            case .error: return "Error"
            case .click: return "Button clicks"
            }
        }
        enum Channel { case notification, call, ui }
        var channel: Channel {
            switch self {
            case .ringIncoming, .ringOutgoing, .callConnected, .callEnded: return .call
            case .click, .error, .startup: return .ui
            default: return .notification
            }
        }
        var enabledKey: String { "sound.enabled.\(rawValue)" }
    }

    private var players: [Sound: AVAudioPlayer] = [:]
    private var loopPlayer: AVAudioPlayer?

    private init() {
        configureSession()
    }

    /// "Play sounds in silent mode" (on by default). Off = sounds follow the ring/silent switch.
    var playInSilentMode: Bool {
        UserDefaults.standard.object(forKey: "sound.ignoreSilentSwitch") as? Bool ?? true
    }

    /// Sets up the audio session for app sounds, unless a call (LiveKit) currently owns it.
    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playAndRecord else { return }
        let category: AVAudioSession.Category = playInSilentMode ? .playback : .ambient
        if session.category != category {
            try? session.setCategory(category, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)
    }

    private func volume(for channel: Sound.Channel) -> Float {
        let d = UserDefaults.standard
        let master = d.object(forKey: "sound.master") as? Double ?? 0.8
        let ch: Double
        switch channel {
        case .notification: ch = d.object(forKey: "sound.notification") as? Double ?? 1
        case .call: ch = d.object(forKey: "sound.call") as? Double ?? 1
        case .ui: ch = d.object(forKey: "sound.ui") as? Double ?? 0.6
        }
        return Float(master * ch)
    }

    func isEnabled(_ s: Sound) -> Bool {
        UserDefaults.standard.object(forKey: s.enabledKey) as? Bool ?? true
    }

    private func player(_ s: Sound) -> AVAudioPlayer? {
        if let p = players[s] { return p }
        guard let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay()
        players[s] = p
        return p
    }

    func play(_ s: Sound) {
        guard isEnabled(s), let p = player(s) else { return }
        configureSession()
        p.volume = volume(for: s.channel)
        p.currentTime = 0
        p.play()
    }

    func startLoop(_ s: Sound) {
        stopLoop()
        guard isEnabled(s), let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        configureSession()
        p.numberOfLoops = -1
        p.volume = volume(for: s.channel)
        p.play()
        loopPlayer = p
    }

    func stopLoop() {
        loopPlayer?.stop()
        loopPlayer = nil
    }

}
