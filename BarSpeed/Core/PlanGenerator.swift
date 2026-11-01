import Foundation

/// 训练目标：决定组数、次数、强度与目标速度带
enum PlanGoal: String, CaseIterable, Identifiable, Codable {
    case maxStrength, power, hypertrophy, speedStrength
    var id: String { rawValue }
    var name: String {
        switch self {
        case .maxStrength: return "最大力量"
        case .power: return "爆发力"
        case .hypertrophy: return "增肌"
        case .speedStrength: return "速度力量"
        }
    }
    /// 目标速度区间（m/s）
    var velocityBand: ClosedRange<Double> {
        switch self {
        case .maxStrength: return 0.20...0.40
        case .power: return 0.75...1.00
        case .hypertrophy: return 0.45...0.65
        case .speedStrength: return 0.55...0.80
        }
    }
    /// 1RM 百分比（无 LVP 时的兜底）
    var percent1RM: Double {
        switch self {
        case .maxStrength: return 0.88
        case .power: return 0.45
        case .hypertrophy: return 0.72
        case .speedStrength: return 0.65
        }
    }
    var sets: Int {
        switch self {
        case .maxStrength: return 5
        case .power: return 6
        case .hypertrophy: return 4
        case .speedStrength: return 4
        }
    }
    var reps: Int {
        switch self {
        case .maxStrength: return 4
        case .power: return 3
        case .hypertrophy: return 9
        case .speedStrength: return 5
        }
    }
    var restSeconds: Int {
        switch self {
        case .maxStrength: return 240
        case .power: return 120
        case .hypertrophy: return 120
        case .speedStrength: return 150
        }
    }
    var note: String {
        switch self {
        case .maxStrength: return "每组都在 0.20–0.40 m/s，慢但必须发力。速度掉出区间就停。"
        case .power: return "轻重量全力加速，组间充分休息，宁可少做也别疲劳。"
        case .hypertrophy: return "中重量，控制离心，最后一组允许速度损失到 30%。"
        case .speedStrength: return "力量与速度的中间地带，主项常用。"
        }
    }
}

struct TrainingPlan: Identifiable {
    var id = UUID()
    var exercise: Exercise
    var goal: PlanGoal
    var sets: Int
    var reps: Int
    var loadKG: Double
    var band: ClosedRange<Double>
    var restSeconds: Int
    var note: String
    /// 没有足够 LVP 数据时的降级说明
    var basis: String
}

enum PlanGenerator {

    /// 优先级：有 LVP 曲线 → 用目标速度反推重量；没有 → 用最近一次重量 × 目标百分比。
    static func make(fit: LVPFit,
                     exercise: Exercise,
                     mvt: Double,
                     lastLoad: Double?,
                     goal: PlanGoal) -> TrainingPlan {
        let vTarget = (goal.velocityBand.lowerBound + goal.velocityBand.upperBound) / 2

        if fit.isValid, let lvpLoad = fit.load(atVelocity: vTarget), lvpLoad > 1, lvpLoad < 600 {
            return TrainingPlan(
                exercise: exercise, goal: goal,
                sets: goal.sets, reps: goal.reps,
                loadKG: roundTo2_5(lvpLoad),
                band: goal.velocityBand,
                restSeconds: goal.restSeconds,
                note: goal.note,
                basis: "依据你的 LVP 曲线：目标 \(String(format: "%.2f", vTarget)) m/s"
            )
        }

        if let rm = VelocityMath.estimated1RM(fit: fit, mvt: mvt) {
            let l = roundTo2_5(rm * goal.percent1RM)
            return TrainingPlan(
                exercise: exercise, goal: goal,
                sets: goal.sets, reps: goal.reps, loadKG: l,
                band: goal.velocityBand, restSeconds: goal.restSeconds,
                note: goal.note,
                basis: "依据 1RM 估算 \(String(format: "%.0f", rm)) kg"
            )
        }

        let base = lastLoad ?? 60
        return TrainingPlan(
            exercise: exercise, goal: goal,
            sets: goal.sets, reps: goal.reps,
            loadKG: roundTo2_5(base),
            band: goal.velocityBand, restSeconds: goal.restSeconds,
            note: goal.note,
            basis: "数据还不够，先用上次的重量。测 4–6 个重量后会给精确建议"
        )
    }

    /// 按 2.5 kg 取整，并保证不低于空杆
    static func roundTo2_5(_ x: Double, bar: Double = 20) -> Double {
        max(bar, (x / 2.5).rounded() * 2.5)
    }
}
