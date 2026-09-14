import SwiftUI
import PawBossCore

enum Destination: Hashable {
    case today, office, dogs, premises, more, customers, staff, recruitment, finance, pricing, loans, business, enquiries, inbox, alerts, bookings, reports, history, community, adviser, settings, help, about, readiness
    case dog(UUID), customer(UUID), employee(UUID), enquiry(UUID), message(UUID), booking(UUID), area(String)
    case dogTask(UUID, DogTask), staffTask(UUID, StaffTask)
}
struct AppPreferences: Codable {
    var appearance = "System"
    var reduceMotion = false
    var adviser = true
    var haptics = true
    var volumes: [String: Double] = ["Music": 0.15, "Ambience": 0.15, "Dogs": 0.25, "Customers": 0.3, "Office": 0.25, "Gameplay": 0.35]
    var notifications: [String: Bool] = ["Enquiries": true, "Medication": true, "Vaccinations": true, "Inspections": true, "Staff": true, "Messages": true, "Reports": true, "Anniversaries": true]
    var notificationEnabled = false
}
@MainActor final class BusinessStore: ObservableObject {
    @Published private(set) var state: BusinessState?
    @Published var preferences: AppPreferences
    @Published var path: [Destination] = []
    @Published var tab = 0
    @Published var inBusiness = false
    @Published var errorMessage: String?
    @Published var status = ""
    @Published var recoveryNeeded = false
    @Published var syncStatus = "Connecting to companion."
    @Published private(set) var outbox = WatchOutbox()
    let catalog: Catalog?
    let repository: FileBusinessRepository
    let feedback = FeedbackController()
    let notificationService = BusinessNotifications()
    private var sync: BusinessSync?
    private let preferencesStore: UserDefaults
    private var receivedSequence: Int64 = 0
    private var pendingLink: BusinessLink?
    private var outboxNeedsRecovery = false
    var isWatch: Bool {
        #if os(watchOS)
        true
        #else
        false
        #endif
    }
    var engine: GameEngine? { guard let state, let catalog else { return nil }; return try? GameEngine(state: state, catalog: catalog) }
    init() {
        var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PawBoss", isDirectory: true)
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        if testing { directory = directory.appendingPathComponent("UITesting") }
        preferencesStore = testing ? UserDefaults(suiteName: "com.sidneytambin.pawboss.uitesting")! : .standard
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-test-game") {
            try? FileManager.default.removeItem(at: directory)
            preferencesStore.removePersistentDomain(forName: "com.sidneytambin.pawboss.uitesting")
        }
        #else
        preferencesStore = .standard
        #endif
        repository = FileBusinessRepository(directory: directory)
        preferences = (preferencesStore.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }) ?? AppPreferences()
        catalog = try? Catalog.bundled()
        do {
            #if os(watchOS)
            let cache = directory.appendingPathComponent("watch-cache.json")
            if FileManager.default.fileExists(atPath: cache.path) {
                do {
                    let snapshot = try JSONDecoder().decode(BusinessSnapshot.self, from: Data(contentsOf: cache))
                    if let catalog { _ = try GameEngine(state: snapshot.state, catalog: catalog) }
                    state = snapshot.state; receivedSequence = snapshot.sequence
                } catch { recoveryNeeded = true; errorMessage = "The Watch's business copy could not be read. Refresh Sync will request a new copy; queued actions are kept separately." }
            }
            let queue = directory.appendingPathComponent("watch-outbox.json")
            if FileManager.default.fileExists(atPath: queue.path) {
                do { outbox = try JSONDecoder().decode(WatchOutbox.self, from: Data(contentsOf: queue)) }
                catch {
                    outboxNeedsRecovery = true; recoveryNeeded = true
                    errorMessage = "Queued Watch actions could not be read. The file has been preserved and new actions are paused to avoid overwriting it. Your iPhone business is unaffected."
                }
            }
            inBusiness = true
            #else
            state = try repository.load()
            #endif
        } catch { recoveryNeeded = true; errorMessage = "Your saved data could not be read. It has not been replaced. \(error.localizedDescription)" }
        if catalog == nil { errorMessage = "PawBoss game content could not be loaded." }
        feedback.update(preferences)
        notificationService.onOpen = { [weak self] link in self?.open(link) }
        sync = BusinessSync(onSnapshot: { [weak self] snapshot in self?.receive(snapshot) }, onCommand: { [weak self] command in self?.receive(command) }, onReceipt: { [weak self] receipt in self?.receive(receipt) }, onStatus: { [weak self] text in self?.syncStatus = text })
        var enableCompanion = true
        #if DEBUG
        enableCompanion = !testing
        #endif
        if enableCompanion {
            sync?.start()
            if !isWatch, let state { sync?.publish(state) }
        }
        #if DEBUG
        if testing && ProcessInfo.processInfo.arguments.contains("--seed-business"), let catalog {
            state = try? catalog.newBusiness(name: "Meadow Care", owner: "Sam", title: "Owner", seed: 42)
            inBusiness = true
        }
        if testing && ProcessInfo.processInfo.arguments.contains("--seed-care-business"), let catalog {
            do {
                let fixture = try UITestBusiness.make(catalog: catalog)
                try repository.save(fixture); state = fixture; inBusiness = true
            } catch { errorMessage = "Test business setup failed: \(error.localizedDescription)" }
        }
        #endif
    }
    func startBusiness(name: String, owner: String, title: String) {
        guard !isWatch, let catalog, !recoveryNeeded else { return }
        do {
            let newState = try catalog.newBusiness(name: name, owner: owner, title: title)
            try repository.save(newState); state = newState; tab = 0; path = []; inBusiness = true
            sync?.publish(newState); announce("\(name) created. Your business starts with savings and no debt.")
        } catch { errorMessage = error.localizedDescription }
    }
    @discardableResult func send(_ action: GameAction) -> Bool {
        guard let state, !recoveryNeeded else { errorMessage = "Business data is not ready yet."; return false }
        let command = GameCommand(businessID: state.id, day: state.day, action: action)
        if isWatch {
            if outbox.pending.contains(where: { $0.action == action && $0.day == state.day && $0.businessID == state.id }) { announce("This action is already waiting for iPhone confirmation."); return false }
            var pending = outbox; pending.enqueue(command)
            do {
                try saveOutbox(pending); outbox = pending; sync?.send(command)
                announce("Action queued for iPhone confirmation."); return true
            } catch { errorMessage = "The action was not queued. \(error.localizedDescription)"; return false }
        }
        return apply(command)?.applied ?? false
    }
    private func apply(_ command: GameCommand) -> Receipt? {
        guard !isWatch, var engine else { return nil }
        if let receipt = engine.state.receipts.first(where: { $0.id == command.id }) { return receipt }
        let old = state
        let receipt = engine.apply(command)
        do {
            try repository.save(engine.state)
            state = engine.state; sync?.publish(engine.state)
            if receipt.applied {
                announce(receipt.message); feedback.play(command.action.feedbackSound)
                notificationService.refresh(old: old, new: engine.state, preferences: preferences)
            } else { errorMessage = receipt.message; feedback.play(.warning) }
            return receipt
        } catch { errorMessage = "Your change was not saved. Previous progress is kept. \(error.localizedDescription)"; return nil }
    }
    func refreshSync() {
        if isWatch { for command in outbox.pending { sync?.send(command) }; sync?.requestSnapshot() }
        else if let state { sync?.publish(state) }
    }
    private func receive(_ command: GameCommand) {
        guard !isWatch else { return }
        if let receipt = apply(command) { sync?.acknowledge(receipt) }
    }
    private func receive(_ receipt: Receipt) {
        guard isWatch, outbox.pending.contains(where: { $0.id == receipt.id }) else { return }
        var updated = outbox; updated.receive(receipt)
        do {
            let sound = outbox.pending.first { $0.id == receipt.id }?.action.feedbackSound ?? .success
            try saveOutbox(updated); outbox = updated; announce(receipt.message)
            feedback.play(receipt.applied ? sound : .warning)
        }
        catch { errorMessage = "The Watch receipt could not be saved. The original action remains queued safely." }
    }
    private func receive(_ snapshot: BusinessSnapshot) {
        guard isWatch, snapshot.sequence > receivedSequence, let catalog else { return }
        do {
            _ = try GameEngine(state: snapshot.state, catalog: catalog)
            try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: repository.directory.appendingPathComponent("watch-cache.json"), options: .atomic)
            state = snapshot.state; receivedSequence = snapshot.sequence
            recoveryNeeded = outboxNeedsRecovery
            if let link = pendingLink { pendingLink = nil; open(link) }
            for receipt in snapshot.state.receipts { receive(receipt) }
            for command in outbox.pending { sync?.send(command) }
            syncStatus = "Business updated from iPhone. \(outbox.pending.count) actions waiting."
        } catch { errorMessage = "The Watch update was not stored. Previous data is kept." }
    }
    private func saveOutbox(_ box: WatchOutbox) throws {
        try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(box).write(to: repository.directory.appendingPathComponent("watch-outbox.json"), options: .atomic)
    }
    func recover() {
        guard !isWatch else { return }
        do {
            var restored = try repository.recoverBackup()
            // A restored timeline is a new authority, invalidating actions queued against discarded history.
            restored.id = UUID(); restored.revision += 1
            try repository.save(restored); state = restored; recoveryNeeded = false
            sync?.publish(restored); announce("Previous backup restored. Review your most recent day before continuing.")
        } catch { errorMessage = "Backup recovery was not possible. Your files have been preserved. \(error.localizedDescription)" }
    }
    func savePreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        preferencesStore.set(data, forKey: "preferences"); feedback.update(preferences)
        if !preferences.notificationEnabled { notificationService.clear() }
        else if let state { notificationService.refresh(old: state, new: state, preferences: preferences) }
    }
    func announce(_ text: String) { status = text; AccessibilityNotification.Announcement(text).post() }
    func navigate(_ destination: Destination) { path.append(destination) }
    func open(_ link: BusinessLink) {
        guard let state else {
            if isWatch { pendingLink = link; refreshSync() }
            else { errorMessage = "Create or restore the business linked to this notification first." }
            return
        }
        guard link.businessID == state.id else { errorMessage = "That notification belongs to a different saved business."; return }
        inBusiness = true; tab = 0; path = []
        switch link.kind {
        case "dog": if let id = link.recordID, state.dogs.contains(where: { $0.id == id }) { path = [.dog(id)] }
        case "medication": if let id = link.recordID, state.dogs.contains(where: { $0.id == id }) { path = [.dogTask(id, .medication)] }
        case "vaccination": if let id = link.recordID, state.dogs.contains(where: { $0.id == id }) { path = [.dogTask(id, .vaccination)] }
        case "enquiry": if let id = link.recordID, state.enquiries.contains(where: { $0.id == id }) { path = [.enquiry(id)] }
        case "message": if let id = link.recordID, state.messages.contains(where: { $0.id == id }) { path = [.message(id)] }
        case "inspection": path = [.readiness]
        case "staff": if let id = link.recordID, state.staff.contains(where: { $0.id == id }) { path = [.staffTask(id, .rota)] }
        case "anniversary": path = [.history]
        default: path = [.reports]
        }
        if path.isEmpty { errorMessage = "This record is no longer available in the current business." }
    }
}
