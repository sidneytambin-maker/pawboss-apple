import SwiftUI
import AVFoundation
import PawBossCore
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

enum FeedbackSound: String, CaseIterable {
    case success, warning, payment, enquiry, construction, inspection, dog, arrival, office, ambience, music
    var category: String {
        switch self { case .dog: return "Dogs"; case .arrival: return "Customers"; case .office: return "Office"; case .ambience: return "Ambience"; case .music: return "Music"; default: return "Gameplay" }
    }
    var title: String {
        switch self { case .dog: return "Dog greeting"; case .arrival: return "Customer arrival"; case .office: return "Office notification"; default: return rawValue.capitalized }
    }
}
extension GameAction {
    var feedbackSound: FeedbackSound {
        switch self {
        case .checkIn: return .arrival
        case .checkOut: return .payment
        case .build, .buildBoundary, .floorRoom, .maintain, .expandLand: return .construction
        case .requestInspection, .applyLicence: return .inspection
        case .decideEnquiry: return .enquiry
        case .respond, .contactOwner: return .office
        case .care: return .dog
        default: return .success
        }
    }
}
@MainActor final class FeedbackController {
    private var players: [FeedbackSound: AVAudioPlayer] = [:]
    private var preferences = AppPreferences()
    private var active = false
    func update(_ preferences: AppPreferences) {
        self.preferences = preferences
        for (sound, player) in players { player.volume = volume(sound) }
        if active { background() }
    }
    private func volume(_ sound: FeedbackSound) -> Float {
        #if os(iOS)
        let duck = UIAccessibility.isVoiceOverRunning ? 0.22 : 1.0
        #else
        let duck = WKAccessibilityIsVoiceOverRunning() ? 0.22 : 1.0
        #endif
        return Float(min(1, max(0, preferences.volumes[sound.category, default: 0.3])) * duck)
    }
    func play(_ sound: FeedbackSound) {
        if preferences.haptics && ![.music, .ambience].contains(sound) {
            #if os(watchOS)
            WKInterfaceDevice.current().play(sound == .warning ? .failure : .success)
            #else
            UINotificationFeedbackGenerator().notificationOccurred(sound == .warning ? .warning : .success)
            #endif
        }
        guard volume(sound) > 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let player: AVAudioPlayer
            if let existing = players[sound] { player = existing }
            else {
                guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else { return }
                player = try AVAudioPlayer(contentsOf: url); players[sound] = player
            }
            player.volume = volume(sound); player.currentTime = 0
            player.numberOfLoops = [.music, .ambience].contains(sound) && active ? -1 : 0
            player.play()
        } catch { /* Sound never prevents saving or replaces the action's accessible result. */ }
    }
    func setActive(_ value: Bool) {
        active = value
        if value { background() } else { for player in players.values { player.stop() } }
    }
    private func background() {
        #if os(iOS)
        for sound: FeedbackSound in [.music, .ambience] {
            if volume(sound) == 0 { players[sound]?.stop() }
            else if players[sound]?.isPlaying != true { play(sound) }
        }
        #endif
    }
}
