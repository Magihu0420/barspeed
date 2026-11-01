import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var purchase: PurchaseManager

    var body: some View {
        TabView(selection: $store.selectedTab) {
            TrainView()
                .tabItem { Label("训练", systemImage: "figure.strengthtraining.traditional") }
                .tag(0)
            HistoryView()
                .tabItem { Label("记录", systemImage: "list.bullet.rectangle") }
                .tag(1)
            LVPView()
                .tabItem { Label("LVP", systemImage: "chart.xyaxis.line") }
                .tag(2)
            JumpView()
                .tabItem { Label("纵跳", systemImage: "figure.jumprope") }
                .tag(3)
            SettingsView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(Theme.accent)
        .onAppear {
            store.isPro = purchase.isPro
            #if PERSONAL
            // 自用包：不打商店，直接解锁全部功能（XCUITest/审核版不会编译这段）
            store.isPro = true
            #endif
        }
        .onChange(of: purchase.isPro) { _, newValue in store.isPro = newValue }
    }
}
