import Foundation
import WatchConnectivity
import PawBossCore

struct BusinessSnapshot: Codable { var sequence: Int64; var state: BusinessState }
@MainActor final class BusinessSync: NSObject, WCSessionDelegate {
    let onSnapshot: (BusinessSnapshot) -> Void
    let onCommand: (GameCommand) -> Void
    let onReceipt: (Receipt) -> Void
    let onStatus: (String) -> Void
    private var latest: BusinessState?
    private var commands: [UUID: GameCommand] = [:]
    init(onSnapshot: @escaping (BusinessSnapshot) -> Void, onCommand: @escaping (GameCommand) -> Void, onReceipt: @escaping (Receipt) -> Void, onStatus: @escaping (String) -> Void) {
        self.onSnapshot = onSnapshot; self.onCommand = onCommand; self.onReceipt = onReceipt; self.onStatus = onStatus
        super.init()
    }
    func start() {
        guard WCSession.isSupported() else { onStatus("Companion sync is unavailable on this device."); return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func publish(_ state: BusinessState) { latest = state; flush() }
    func send(_ command: GameCommand) { commands[command.id] = command; flush() }
    func acknowledge(_ receipt: Receipt) {
        guard WCSession.default.activationState == .activated, let data = try? JSONEncoder().encode(receipt) else { return }
        WCSession.default.transferUserInfo(["receipt": data])
        if WCSession.default.isReachable { WCSession.default.sendMessage(["receipt": data], replyHandler: nil) }
    }
    func requestSnapshot() {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(["refresh": true])
        if WCSession.default.isReachable { WCSession.default.sendMessage(["refresh": true], replyHandler: nil) }
    }
    private func flush() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired && session.isWatchAppInstalled else { onStatus("Pair an Apple Watch and install PawBoss to enable companion management."); return }
        #endif
        onStatus(session.isReachable ? "Live companion connection available." : "Live connection asleep. Background delivery remains available.")
        for command in commands.values {
            guard let data = try? JSONEncoder().encode(command) else { continue }
            let alreadyQueued = session.outstandingUserInfoTransfers.contains { ($0.userInfo["commandID"] as? String) == command.id.uuidString }
            if !alreadyQueued { session.transferUserInfo(["command": data, "commandID": command.id.uuidString]) }
            if session.isReachable { session.sendMessage(["command": data], replyHandler: nil) }
        }
        commands.removeAll()
        #if os(iOS)
        guard let latest else { return }
        let previous = Int64(UserDefaults.standard.integer(forKey: "snapshotSequence"))
        let sequence = max(previous + 1, Int64(Date().timeIntervalSince1970 * 1000))
        UserDefaults.standard.set(sequence, forKey: "snapshotSequence")
        guard let data = try? JSONEncoder().encode(BusinessSnapshot(sequence: sequence, state: latest)) else { return }
        do {
            if data.count < 55000 {
                try session.updateApplicationContext(["snapshot": data])
                if session.isReachable { session.sendMessage(["snapshot": data], replyHandler: nil) }
            } else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("pawboss-\(sequence).json")
                try data.write(to: url, options: .atomic)
                session.transferFile(url, metadata: ["pawbossSnapshot": true])
            }
        } catch { onStatus("Snapshot could not be queued. Use Refresh Sync to retry.") }
        #endif
    }
    private func receive(_ values: [String: Any]) {
        if let data = values["snapshot"] as? Data, let value = try? JSONDecoder().decode(BusinessSnapshot.self, from: data) { onSnapshot(value) }
        if let data = values["command"] as? Data, let value = try? JSONDecoder().decode(GameCommand.self, from: data) { onCommand(value) }
        if let data = values["receipt"] as? Data, let value = try? JSONDecoder().decode(Receipt.self, from: data) { onReceipt(value) }
        if values["refresh"] as? Bool == true { flush() }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.receive(context); self.flush() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.flush() } }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { Task { @MainActor in self.receive(applicationContext) } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { Task { @MainActor in self.receive(message) } }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { Task { @MainActor in self.receive(userInfo) } }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["pawbossSnapshot"] as? Bool == true, let data = try? Data(contentsOf: file.fileURL), let snapshot = try? JSONDecoder().decode(BusinessSnapshot.self, from: data) else { return }
        Task { @MainActor in self.onSnapshot(snapshot) }
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if error == nil, fileTransfer.file.metadata?["pawbossSnapshot"] as? Bool == true { try? FileManager.default.removeItem(at: fileTransfer.file.fileURL) }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.flush() } }
    #endif
}
