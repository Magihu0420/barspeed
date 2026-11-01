import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var purchase: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    private struct Feature: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        Feature(title: "全部动作的 LVP 档案", detail: "不止一个动作，所有动作的负重-速度曲线都能看"),
        Feature(title: "1RM 预测与更新", detail: "每组速度自动估算 1RM，不再靠猜"),
        Feature(title: "下一组推荐重量", detail: "按目标速度直接给出该上多少 kg"),
        Feature(title: "速度损失与疲劳区间", detail: "组内实时判断该不该停"),
        Feature(title: "长期趋势与导出", detail: "动作历史、月趋势、CSV 导出"),
        Feature(title: "纵跳看板", detail: "CMJ / DJ / SJ 高度趋势"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("BarSpeed Pro").font(.system(size: 26, weight: .heavy))
                        Text("解锁完整的速度训练分析").font(.system(size: 13)).foregroundStyle(Theme.sub)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 0) {
                        ForEach(features) { f in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent)
                                    .font(.system(size: 15))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.system(size: 14, weight: .semibold))
                                    Text(f.detail).font(.system(size: 12)).foregroundStyle(Theme.sub)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            if f.id != features.last?.id { Divider().overlay(Theme.line) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(spacing: 10) {
                        ForEach(PurchaseManager.Plan.allCases) { plan in
                            Button {
                                Task { await purchase.purchase(plan) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(plan.title).font(.system(size: 16, weight: .semibold))
                                        Text(subtitle(plan)).font(.system(size: 11)).foregroundStyle(Theme.sub)
                                    }
                                    Spacer()
                                    Text(purchase.priceText(plan))
                                        .font(.system(size: 17, weight: .bold))
                                        .monospacedDigit()
                                }
                                .padding(16)
                                .background(plan == .yearly ? Theme.accent.opacity(0.15) : Theme.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(plan == .yearly ? Theme.accent.opacity(0.6) : Theme.line, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(purchase.purchasing)
                        }
                    }

                    if let msg = purchase.message {
                        Text(msg).font(.system(size: 12)).foregroundStyle(Theme.warn)
                    }

                    Button {
                        Task { await purchase.restore() }
                    } label: {
                        Text("恢复购买").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.sub)

                    Text("订阅通过 App Store 结算，可在系统设置中随时取消。价格以 App Store 显示为准。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.sub)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }

    private func subtitle(_ plan: PurchaseManager.Plan) -> String {
        switch plan {
        case .monthly: return "按月续订，随时取消"
        case .yearly: return "最划算，约等于月卡的 4 折"
        case .lifetime: return "一次买断，永久可用"
        }
    }
}
