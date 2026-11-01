import SwiftUI

@main
struct BarSpeedApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var purchase = PurchaseManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(purchase)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
