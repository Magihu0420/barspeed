import SwiftUI
import Charts

struct LVPView: View {
    @EnvironmentObject var store: AppStore
    @State private var exercise: Exercise = .backSquat
    @State private var targetVelocity: Double = 0.60
    @State private var showPaywall = false

    private struct LinePoint: Identifiable {
        let id = UUID()
        let load: Double
        let velocity: Double
    }

    /// 拟合直线采样点（0.05 步长），避免用两根 LineMark 硬连线
    private var linePoints: [LinePoint] {
        guard fit.isValid, let first = points.first, let last = points.last else { return [] }
        let x0 = first.load
        let x1 = last.load * 1.15
        return stride(from: 0.0, through: 1.0, by: 0.05).map { t in
            let x = x0 + (x1 - x0) * t
            return LinePoint(load: x, velocity: fit.velocity(atLoad: x))
        }
    }

    private var points: [LVPPoint] { store.lvpPoints(for: exercise) }
    private var fit: LVPFit { store.lvpFit(for: exercise) }
    private var oneRM: Double? { VelocityMath.estimated1RM(fit: fit, mvt: store.mvt(for: exercise)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    exercisePicker
                    if store.canViewLVP(exercise) {
                        content
                    } else {
                        locked
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("LVP")
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private var exercisePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.exercisesWithData.isEmpty ? [Exercise.backSquat] : store.exercisesWithData) { ex in
                    Button {
                        exercise = ex
                    } label: {
                        Text(ex.name)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(ex == exercise ? Theme.accent : Theme.card)
                            .foregroundStyle(ex == exercise ? .black : Theme.text)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("负重-速度曲线").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub)
                        Spacer()
                        if fit.isValid {
                            Pill(text: String(format: "R² %.2f", fit.r2), color: fit.r2 > 0.9 ? Theme.accent : Theme.warn)
                        }
                    }
                    if points.count >= 2 {
                        Chart {
                            ForEach(points) { p in
                                PointMark(x: .value("负重", p.load), y: .value("速度", p.velocity))
                                    .symbolSize(60)
                                    .foregroundStyle(Theme.accent)
                            }
                            ForEach(linePoints) { p in
                                LineMark(x: .value("负重", p.load), y: .value("速度", p.velocity))
                                    .foregroundStyle(Theme.accent.opacity(0.75))
                            }
                        }
                        .chartXAxisLabel("kg")
                        .chartYAxisLabel("m/s")
                        .frame(height: 200)
                    } else {
                        Text("至少需要 2 个不同重量的训练记录才能拟合曲线。")
                            .font(.system(size: 13)).foregroundStyle(Theme.sub)
                    }
                }
            }

            HStack(spacing: 12) {
                Card {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("估算 1RM").font(.system(size: 12)).foregroundStyle(Theme.sub)
                        Text(oneRM.map { String(format: "%.1f kg", $0) } ?? "—")
                            .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(String(format: "阈值速度 %.2f m/s", store.mvt(for: exercise)))
                            .font(.system(size: 10)).foregroundStyle(Theme.sub)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("采样点").font(.system(size: 12)).foregroundStyle(Theme.sub)
                        Text("\(points.count)")
                            .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(fit.isValid ? "曲线可用" : "点太少或斜率异常")
                            .font(.system(size: 10)).foregroundStyle(Theme.sub)
                    }
                }
            }

            PlanCard(fit: fit,
                     exercise: exercise,
                     mvt: store.mvt(for: exercise),
                     lastLoad: store.sets(for: exercise).max(by: { $0.date < $1.date })?.loadKG) { plan in
                store.pendingPlan = plan
                store.selectedTab = 0
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("今日负重推荐").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub)
                    HStack {
                        Text("目标速度").font(.system(size: 13)).foregroundStyle(Theme.sub)
                        Spacer()
                        Text(String(format: "%.2f m/s", targetVelocity))
                            .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    }
                    Slider(value: $targetVelocity, in: 0.15...1.2, step: 0.01)
                        .tint(Theme.accent)
                    if let load = VelocityMath.load(forVelocity: targetVelocity, fit: fit) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", load))
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                            Text("kg").font(.system(size: 13)).foregroundStyle(Theme.sub)
                            Spacer()
                            if let rm = oneRM {
                                Pill(text: String(format: "%.0f%% 1RM", load / rm * 100), color: Theme.warn)
                            }
                        }
                        if let zone = VelocityMath.zone(forVelocity: targetVelocity) {
                            Text("\(zone.name)：\(zone.hint)").font(.system(size: 12)).foregroundStyle(Theme.sub)
                        }
                    } else {
                        Text("曲线不够，无法给出推荐。").font(.system(size: 13)).foregroundStyle(Theme.sub)
                    }
                }
            }
        }
    }

    private var locked: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
                    Text("LVP 档案是会员功能").font(.system(size: 15, weight: .semibold))
                }
                Text("免费版只开放「\(store.freeExercise.name)」的 LVP。开通后解锁全部动作的 LVP 档案、1RM 预测、推荐负重与长期趋势。")
                    .font(.system(size: 13)).foregroundStyle(Theme.sub)
                Button { showPaywall = true } label: {
                    Text("查看会员方案")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.accent).foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}
