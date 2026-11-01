import Foundation

// MARK: - 动作

enum Exercise: String, Codable, CaseIterable, Identifiable {
    case backSquat, frontSquat, halfSquat
    case benchPress, deadlift, romanianDeadlift
    case cleanFromFloor, powerClean, snatch
    case strictPress, pushPress, behindNeckPress
    case bentOverRow, midThighPull
    case jumpSquat, halfSquatJump, midThighJump
    case plyoSquat, plyoHalfSquat, thruster, kneeHighPull

    var id: String { rawValue }

    var name: String {
        switch self {
        case .backSquat: return "深蹲"
        case .frontSquat: return "前蹲"
        case .halfSquat: return "半蹲"
        case .benchPress: return "卧推"
        case .deadlift: return "硬拉"
        case .romanianDeadlift: return "罗马尼亚硬拉"
        case .cleanFromFloor: return "翻站"
        case .powerClean: return "高翻"
        case .snatch: return "抓举"
        case .strictPress: return "推举"
        case .pushPress: return "借力推"
        case .behindNeckPress: return "颈后推"
        case .bentOverRow: return "俯身划船"
        case .midThighPull: return "中腿拉"
        case .jumpSquat: return "跳蹲"
        case .halfSquatJump: return "半蹲跳"
        case .midThighJump: return "中腿跳"
        case .plyoSquat: return "增强式深蹲"
        case .plyoHalfSquat: return "增强式半蹲"
        case .thruster: return "推举深蹲"
        case .kneeHighPull: return "高抬腿"
        }
    }

    /// 最小速度阈值（m/s）：该动作在 1RM 附近的平均向心速度经验值。
    /// 用于由 LVP 反推 1RM。数值取自公开的 VBT 文献区间，仅作默认值，用户可在设置里改。
    var mvt: Double {
        switch self {
        case .backSquat: return 0.30
        case .frontSquat: return 0.32
        case .halfSquat: return 0.45
        case .benchPress: return 0.15
        case .deadlift: return 0.15
        case .romanianDeadlift: return 0.20
        case .cleanFromFloor: return 0.50
        case .powerClean: return 0.60
        case .snatch: return 0.80
        case .strictPress: return 0.18
        case .pushPress: return 0.45
        case .behindNeckPress: return 0.20
        case .bentOverRow: return 0.30
        case .midThighPull: return 0.40
        case .jumpSquat: return 0.80
        case .halfSquatJump: return 0.90
        case .midThighJump: return 0.90
        case .plyoSquat: return 0.80
        case .plyoHalfSquat: return 0.85
        case .thruster: return 0.50
        case .kneeHighPull: return 0.70
        }
    }

    var isExplosive: Bool { mvt >= 0.45 }
}

// MARK: - 单次动作 / 单组

struct RepSample: Codable, Identifiable, Hashable {
    var id = UUID()
    var index: Int
    var meanVelocity: Double      // m/s
    var peakVelocity: Double      // m/s
    var displacementM: Double
    var duration: Double          // s

    var displacementCM: Double { displacementM * 100 }
}

struct SetRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var exercise: Exercise
    var loadKG: Double
    var date: Date
    var reps: [RepSample]
    var note: String = ""
    var videoFileName: String? = nil

    var repCount: Int { reps.count }

    var meanVelocity: Double {
        guard !reps.isEmpty else { return 0 }
        return reps.reduce(0) { $0 + $1.meanVelocity } / Double(reps.count)
    }

    var peakVelocity: Double { reps.map(\.peakVelocity).max() ?? 0 }

    var bestMeanVelocity: Double { reps.map(\.meanVelocity).max() ?? 0 }

    var displacementCM: Double { reps.map(\.displacementM).max().map { $0 * 100 } ?? 0 }

    /// 组内速度损失（0...1）
    var velocityLoss: Double {
        guard let first = reps.first?.meanVelocity, first > 0.05 else { return 0 }
        let last = reps.last!.meanVelocity
        return max(0, (first - last) / first)
    }

    var estimatedPeakPower: Double { VelocityMath.estimatedPeakPower(loadKG: loadKG, meanVelocity: meanVelocity) }
}

// MARK: - 实时轨迹（彩色轨迹用）

struct TrailPoint: Identifiable {
    let id = UUID()
    let pos: Double      // 位移（米）
    let v: Double        // 瞬时速度（m/s）
}

// MARK: - LVP

struct LVPPoint: Identifiable, Hashable {
    var id: String { "\(exercise.rawValue)-\(load)" }
    var exercise: Exercise
    var load: Double
    var velocity: Double
    var date: Date
}

struct LVPFit {
    var slope: Double
    var intercept: Double
    var r2: Double
    var points: [(load: Double, velocity: Double)]

    var isValid: Bool { points.count >= 2 && slope < -0.0005 }

    func velocity(atLoad load: Double) -> Double { intercept + slope * load }

    func load(atVelocity v: Double) -> Double? {
        guard abs(slope) > 0.0001 else { return nil }
        let l = (v - intercept) / slope
        return l.isFinite && l > 0 ? l : nil
    }
}

// MARK: - 纵跳

enum JumpKind: String, Codable, CaseIterable, Identifiable {
    case cmj, cmja, sj, dj, pogo, repeatedCMJ
    var id: String { rawValue }
    var name: String {
        switch self {
        case .cmj: return "CMJ 反向跳"
        case .cmja: return "CMJA 摆臂跳"
        case .sj: return "SJ 静蹲跳"
        case .dj: return "DJ 落地跳"
        case .pogo: return "双脚弹跳"
        case .repeatedCMJ: return "连续跳"
        }
    }
}

struct JumpRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: JumpKind
    var date: Date
    var heightCM: Double
    var flightTime: Double
    var note: String = ""
}

// MARK: - 设置

enum VoiceMode: String, Codable, CaseIterable, Identifiable {
    case silent, velocity, velocityAndPower, full
    var id: String { rawValue }
    var name: String {
        switch self {
        case .silent: return "关闭"
        case .velocity: return "只报速度"
        case .velocityAndPower: return "速度 + 功率"
        case .full: return "速度 + 功率 + 次数"
        }
    }
}

struct AppSettings: Codable {
    var voiceMode: VoiceMode = .velocity
    var velocityLossThreshold: Double = 0.20      // 20%
    var minTravelM: Double = 0.08                 // 0.08 - 0.8
    var plateDiameterMM: Double = 450             // 标定用杠铃片直径
    var barWeightKG: Double = 20
    var countdownSeconds: Int = 3
    var showPower: Bool = true
    var hapticsOnLoss: Bool = true
    var customMVT: [String: Double] = [:]
}
