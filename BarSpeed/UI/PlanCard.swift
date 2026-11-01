import SwiftUI

/// 「自动计划」卡片：把你的 LVP 曲线翻译成今天该做几组、多重、多重一个速度
struct PlanCard: View {
    let fit: LVPFit
    let exercise: Exercise
    let mvt: Double
    let lastLoad: Double?
    var onStart: (TrainingPlan) -> Void

    @State private var goal: PlanGoal = .maxStrength

    private var plan: TrainingPlan {
        PlanGenerator.make(fit: fit, exercise: exercise, mvt: mvt, lastLoad: lastLoad, goal: goal)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(Theme.accent)
                    Text("今日计划").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Pill(text: "VIP", color: Theme.accent)
                }

                Picker("目标", selection: $goal) {
                    ForEach(PlanGoal.allCases) { g in Text(g.name).tag(g) }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(plan.sets)").font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("组 ×").font(.system(size: 12)).foregroundStyle(Theme.sub)
                    Text("\(plan.reps)").font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("次 @").font(.system(size: 12)).foregroundStyle(Theme.sub)
                    Text(String(format: "%.1f", plan.loadKG)).font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("kg").font(.system(size: 12)).foregroundStyle(Theme.sub)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Pill(text: String(format: "目标 %.2f–%.2f m/s", plan.band.lowerBound, plan.band.upperBound), color: Theme.warn)
                    Pill(text: "组间 \(plan.restSeconds / 60) 分", color: Theme.sub)
                }

                Text(plan.note).font(.system(size: 12)).foregroundStyle(Theme.sub)
                Text(plan.basis).font(.system(size: 11)).foregroundStyle(Theme.sub.opacity(0.8))

                Button {
                    onStart(plan)
                } label: {
                    Text("用这个重量开始")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accent.opacity(0.16))
                        .foregroundStyle(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

/// 彩色轨迹：把刚才 2 秒的杠铃位置按瞬时速度上色画出来
struct TrajectoryView: View {
    var points: [TrailPoint]

    var body: some View {
        Canvas { ctx, size in
            guard points.count > 1 else { return }
            let lo = points.map(\.pos).min() ?? 0
            let hi = points.map(\.pos).max() ?? 0
            let span = max(hi - lo, 0.25)
            let x = size.width * 0.16

            func y(_ p: Double) -> CGFloat {
                let t = (p - lo) / span
                return size.height * (1 - CGFloat(t))
            }

            for i in 1..<points.count {
                var path = Path()
                path.move(to: CGPoint(x: x, y: y(points[i - 1].pos)))
                path.addLine(to: CGPoint(x: x, y: y(points[i].pos)))
                let age = Double(points.count - i) / Double(max(points.count, 1))
                let color = Theme.zoneColor(points[i].v).opacity(1 - age * 0.9)
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            }

            // 当前点
            if let last = points.last {
                let r: CGFloat = 6
                let rect = CGRect(x: x - r, y: y(last.pos) - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Theme.zoneColor(last.v)))
            }
        }
        .allowsHitTesting(false)
    }
}
