import SwiftUI
import WatchConnectivity

@main struct PawBossApp: App {
    @StateObject private var store = BusinessStore()
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .tint(Color.pawGreen)
                .preferredColorScheme(store.preferences.appearance == "Light" ? .light : store.preferences.appearance == "Dark" ? .dark : nil)
                .transaction { transaction in
                    if systemReduceMotion || store.preferences.reduceMotion { transaction.animation = nil; transaction.disablesAnimations = true }
                }
                .onChange(of: store.inBusiness) { _, value in store.feedback.setActive(phase == .active && value) }
                .onChange(of: phase) { _, value in
                    store.feedback.setActive(value == .active && store.inBusiness)
                    if value == .active { store.refreshSync() }
                }
                .alert("PawBoss", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                    Button("OK", role: .cancel) { store.errorMessage = nil }
                } message: { Text(store.errorMessage ?? "") }
        }
        #if os(watchOS)
        .backgroundTask(.watchConnectivity) {
            while !Task.isCancelled && (WCSession.default.activationState != .activated || WCSession.default.hasContentPending) {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            await MainActor.run { }
        }
        #endif
    }
}
extension Color {
    static let pawGreen = Color("BrandAccent")
    static let pawGold = Color(red: 0.96, green: 0.73, blue: 0.15)
    static let pawCoral = Color(red: 0.83, green: 0.28, blue: 0.23)
}
