import Foundation
import StoreKit

/// StoreKit 2 订阅管理。iOS 上的数字功能必须走 IAP（App Store 准则 3.1.1）。
@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    /// 产品 ID，需在 App Store Connect 里建同名商品
    enum Plan: String, CaseIterable, Identifiable {
        case monthly = "com.barspeed.pro.monthly"
        case yearly  = "com.barspeed.pro.yearly"
        case lifetime = "com.barspeed.pro.lifetime"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .monthly: return "月卡"
            case .yearly: return "年卡"
            case .lifetime: return "永久"
            }
        }
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published var purchasing = false
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update {
                    await t.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            let list = try await Product.products(for: Plan.allCases.map(\.rawValue))
            products = list.sorted { a, b in
                order(a.id) < order(b.id)
            }
        } catch {
            message = "商品加载失败：\(error.localizedDescription)"
        }
    }

    private func order(_ id: String) -> Int {
        Plan.allCases.firstIndex { $0.rawValue == id } ?? 99
    }

    func priceText(_ plan: Plan) -> String {
        if let p = products.first(where: { $0.id == plan.rawValue }) {
            return p.displayPrice
        }
        // 未拿到商品信息时的兜底展示（不含金额，避免误导）
        return "—"
    }

    func purchase(_ plan: Plan) async {
        guard let product = products.first(where: { $0.id == plan.rawValue }) else {
            message = "尚未加载到商品，请稍后重试"
            return
        }
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                    message = "开通成功"
                } else {
                    message = "交易校验失败"
                }
            case .userCancelled:
                break
            case .pending:
                message = "等待支付确认"
            @unknown default:
                break
            }
        } catch {
            message = "购买失败：\(error.localizedDescription)"
        }
    }

    func restore() async {
        do {
            try await StoreKit.AppStore.sync()
            await refreshEntitlement()
            message = isPro ? "已恢复" : "没有找到可恢复的订阅"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    func refreshEntitlement() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, Plan.allCases.contains(where: { $0.rawValue == t.productID }) {
                active = true
            }
        }
        isPro = active
    }
}
