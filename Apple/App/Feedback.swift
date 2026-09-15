import SwiftUI
import AVFoundation
import PawBossCore
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

struct AudioAsset: Codable, Identifiable {
    var id: String; var title: String; var category: String; var kind: String
    var file: String; var duration: Double; var source: String
}
struct AudioSource: Codable, Identifiable {
    var id: String; var title: String; var author: String; var page: String
    var license: String; var licenseURL: String
}
struct AudioLibrary: Codable {
    var assets: [AudioAsset]; var sources: [AudioSource]
    static func bundled() -> AudioLibrary {
        guard let url = Bundle.main.url(forResource: "audio-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url), let library = try? JSONDecoder().decode(Self.self, from: data) else { return .init(assets: [], sources: []) }
        return library
    }
}
enum FeedbackSound: String {
    case success, warning, payment, enquiry, construction, inspection, dog, arrival, office, gate
}
extension GameAction {
    var feedbackSound: FeedbackSound {
        switch self {
        case .checkIn: return .arrival
        case .checkOut: return .payment
        case .buildBoundary: return .gate
        case .build, .floorRoom, .maintain, .expandLand: return .construction
        case .requestInspection, .applyLicence: return .inspection
        case .decideEnquiry: return .enquiry
        case .respond, .contactOwner: return .office
        case .care: return .dog
        default: return .success
        }
    }
}
@MainActor final class FeedbackController: NSObject, AVAudioPlayerDelegate {
    let library = AudioLibrary.bundled()
    private var preferences = AppPreferences()
    private var effects: [String: AVAudioPlayer] = [:]
    private var music: AVAudioPlayer?
    private var scenePlayer: AVAudioPlayer?
    private var previewPlayer: AVAudioPlayer?
    private var musicID: String?
    private var sceneID: String?
    private var previewID: String?
    private var rotation = MusicRotation()
    private var previousDog: String?
    private var active = false
    private var scene = Soundscape.office
    private var hasDogs = false
    private var idleTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var retiring: [AVAudioPlayer] = []

    private func asset(_ id: String?) -> AudioAsset? { library.assets.first { $0.id == id } }
    private func volume(_ id: String?) -> Float {
        guard let asset = asset(id) else { return 0 }
        return Float(AudioMix.gain(asset.category, volumes: preferences.volumes))
    }
    private func player(_ id: String) -> AVAudioPlayer? {
        guard let entry = asset(id), let url = Bundle.main.url(forResource: entry.file, withExtension: nil) else { return nil }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let value = try AVAudioPlayer(contentsOf: url)
            value.delegate = self; value.volume = volume(id); value.prepareToPlay()
            return value
        } catch { return nil }
    }
    func update(_ preferences: AppPreferences) {
        self.preferences = preferences
        for (id, player) in effects { player.volume = volume(id) }
        music?.volume = volume(musicID); scenePlayer?.volume = volume(sceneID)
        previewPlayer?.volume = volume(previewID)
        if active { background() }
    }
    func configure(scene: Soundscape, hasDogs: Bool) {
        let changed = self.scene != scene
        self.scene = scene; self.hasDogs = hasDogs
        if changed { idleTask?.cancel(); idleTask = nil }
        if active { background() }
    }
    func play(_ sound: FeedbackSound) {
        guard active else { return }
        if preferences.haptics {
            #if os(watchOS)
            WKInterfaceDevice.current().play(sound == .warning ? .failure : .success)
            #else
            UINotificationFeedbackGenerator().notificationOccurred(sound == .warning ? .warning : .success)
            #endif
        }
        var id = sound.rawValue
        if sound == .dog {
            let options: [String] = ["dog-1", "dog-2", "dog-3"].filter { $0 != previousDog }
            id = options.randomElement() ?? "dog-1"; previousDog = id
        }
        effect(id)
    }
    private func effect(_ id: String) {
        guard volume(id) > 0 else { return }
        let value = effects[id] ?? player(id)
        effects[id] = value; value?.volume = volume(id); value?.currentTime = 0; value?.play()
    }
    func preview(_ id: String) {
        stopPreview(resume: false)
        music?.pause(); scenePlayer?.pause()
        for player in retiring { player.stop() }; retiring.removeAll()
        previewID = id; previewPlayer = player(id); previewPlayer?.play()
        previewTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.stopPreview()
        }
    }
    func stopPreview(resume: Bool = true) {
        previewTask?.cancel(); previewTask = nil
        previewPlayer?.stop(); previewPlayer = nil; previewID = nil
        if resume && active { background() }
    }
    func setActive(_ value: Bool) {
        active = value
        if value { background() }
        else {
            idleTask?.cancel(); idleTask = nil
            stopPreview(resume: false)
            music?.pause(); scenePlayer?.pause()
            for player in effects.values { player.stop() }
            for player in retiring { player.stop() }; retiring.removeAll()
        }
    }
    private func nextMusic() {
        guard let id = rotation.next(from: library.assets.filter { $0.kind == "music" }.map(\.id)) else { return }
        musicID = id; music = player(id); music?.play()
    }
    private func background() {
        guard active, previewPlayer == nil else { return }
        if AudioMix.gain("Music", volumes: preferences.volumes) == 0 { music?.pause() }
        else if music == nil { nextMusic() }
        else if music?.isPlaying != true { music?.play() }
        let id: String? = scene == .office ? "office-room" : scene == .outdoors ? "outdoor-garden" : scene == .rain ? "outdoor-rain" : nil
        if id != sceneID {
            if let old = scenePlayer {
                old.setVolume(0, fadeDuration: 0.8); retiring.append(old)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    old.stop(); self?.retiring.removeAll { $0 === old }
                }
            }
            sceneID = id; scenePlayer = id.flatMap { player($0) }
            scenePlayer?.numberOfLoops = -1
            scenePlayer?.volume = 0; scenePlayer?.play()
            scenePlayer?.setVolume(volume(id), fadeDuration: 0.8)
        } else if volume(id) == 0 { scenePlayer?.pause() }
        else if scenePlayer?.isPlaying != true { scenePlayer?.play() }
        if idleTask == nil {
            idleTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(Int.random(in: 35...75))) } catch { return }
                    guard let self, self.active else { return }
                    if self.previewPlayer == nil && self.hasDogs && self.scene != .office {
                        self.effect(Bool.random() ? "care-movement" : ["dog-1","dog-2","dog-3"].randomElement()!)
                    }
                }
            }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if player === self.previewPlayer { self.stopPreview() }
            else if player === self.music && self.active && self.previewPlayer == nil { self.nextMusic() }
        }
    }
}
