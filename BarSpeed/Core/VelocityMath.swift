import Foundation

enum VelocityMath {

    // MARK: LVP 拟合（最小二乘 v = a + b·load）

    static func fit(points: [(load: Double, velocity: Double)]) -> LVPFit {
        let n = Double(points.count)
        guard points.count >= 2 else {
            return LVPFit(slope: 0, intercept: 0, r2: 0, points: points.map { (load: $0.load, velocity: $0.velocity) })
        }
        let sumX = points.reduce(0) { $0 + $1.load }
        let sumY = points.reduce(0) { $0 + $1.velocity }
        let sumXY = points.reduce(0) { $0 + $1.load * $1.velocity }
        let sumXX = points.reduce(0) { $0 + $1.load * $1.load }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 1e-9 else {
            return LVPFit(slope: 0, intercept: 0, r2: 0, points: points.map { (load: $0.load, velocity: $0.velocity) })
        }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n

        let meanY = sumY / n
        var ssRes = 0.0, ssTot = 0.0
        for p in points {
            let pred = intercept + slope * p.load
            ssRes += pow(p.velocity - pred, 2)
            ssTot += pow(p.velocity - meanY, 2)
        }
        let r2 = ssTot > 1e-9 ? max(0, 1 - ssRes / ssTot) : 0

        return LVPFit(slope: slope, intercept: intercept, r2: r2,
                      points: points.map { (load: $0.load, velocity: $0.velocity) })
    }

    /// 由 LVP + 最小速度阈值反推 1RM
    static func estimated1RM(fit: LVPFit, mvt: Double) -> Double? {
        guard fit.isValid else { return nil }
        guard let load = fit.load(atVelocity: mvt), load > 1, load < 600 else { return nil }
        return load
    }

    /// 目标速度对应的训练重量
    static func load(forVelocity v: Double, fit: LVPFit) -> Double? {
        guard fit.isValid else { return nil }
        guard let load = fit.load(atVelocity: v), load > 1, load < 600 else { return nil }
        return load
    }

    /// 按 1RM 百分比取重量
    static func load(forPercent1RM p: Double, oneRM: Double) -> Double {
        max(0, oneRM * p)
    }

    // MARK: 速度区间

    struct Zone {
        var name: String
        var hint: String
        var targetVelocity: ClosedRange<Double>
        var percent1RM: ClosedRange<Double>
    }

    static let zones: [Zone] = [
        Zone(name: "绝对力量", hint: "重、慢、少次数。目标是把 1RM 顶上去。", targetVelocity: 0.10...0.35, percent1RM: 0.85...0.95),
        Zone(name: "力量-速度", hint: "主项常用区。重量大，速度仍要拼。", targetVelocity: 0.35...0.55, percent1RM: 0.75...0.85),
        Zone(name: "速度-力量", hint: "轻中重量，追求加速度。", targetVelocity: 0.55...0.75, percent1RM: 0.60...0.75),
        Zone(name: "爆发力", hint: "轻重量全力加速，练发力率。", targetVelocity: 0.75...0.95, percent1RM: 0.30...0.60),
        Zone(name: "起动速度", hint: "极轻负荷，只练启动。", targetVelocity: 0.95...2.00, percent1RM: 0.00...0.30),
    ]

    static func zone(forVelocity v: Double) -> Zone? {
        zones.first { $0.targetVelocity.contains(v) }
    }

    // MARK: 功率估算（Sayers 式，单位 W）

    static func estimatedPeakPower(loadKG: Double, meanVelocity: Double) -> Double {
        guard loadKG > 0, meanVelocity > 0 else { return 0 }
        return 60.7 * loadKG + 1.3 * loadKG * meanVelocity
    }

    // MARK: 配片

    struct PlateCount: Identifiable, Hashable {
        var id: Double { weight }
        var weight: Double
        var count: Int        // 每边片数
    }

    static func plateBreakdown(totalKG: Double, barKG: Double, available: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]) -> (perSide: [PlateCount], remainder: Double) {
        var perSide = (totalKG - barKG) / 2
        guard perSide > 0 else { return ([], max(0, totalKG)) }
        var counts: [Double: Int] = [:]
        for p in available {
            while perSide >= p - 1e-9 {
                counts[p, default: 0] += 1
                perSide -= p
            }
        }
        let list = counts.keys.sorted(by: >).map { PlateCount(weight: $0, count: counts[$0]!) }
        return (list, max(0, perSide * 2))
    }

    // MARK: 纵跳

    /// 由腾空时间推跳跃高度（m）
    static func jumpHeight(flightTime t: Double) -> Double {
        guard t > 0 else { return 0 }
        return 9.80665 * t * t / 8.0
    }

    static func r(_ v: Double, _ digits: Int = 2) -> Double {
        let m = pow(10.0, Double(digits))
        return (v * m).rounded() / m
    }
}
