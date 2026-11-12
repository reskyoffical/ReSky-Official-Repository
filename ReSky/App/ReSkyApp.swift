import SwiftUI
import SwiftData

@main
struct ReSkyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionStore.shared
    @StateObject private var calls = CallManager.shared
    @StateObject private var plus = PlusStore.shared
    @StateObject private var transfers = TransferCenter.shared
    @StateObject private var outbox = Outbox.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(calls)
                .environmentObject(plus)
                .environmentObject(transfers)
                .environmentObject(outbox)
                .onOpenURL { url in Task { await session.handleDeepLink(url) } }
        }
        .modelContainer(LocalStore.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.appBecameActive() }
        }
    }
}
