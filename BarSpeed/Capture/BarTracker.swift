import Foundation
import CoreGraphics
import CoreVideo

struct TrackSample {
    var time: Double
    var position: Double      // 米，向上为正
    var velocity: Double      // m/s
    var repIndex: Int
    var event: RepEvent?
    var lost: Bool
    var confidence: Float
}

enum RepEvent {
    case started
    case finished(RepSample)
}

/// 纯摄像头杠铃跟踪器（v1，无机器学习模型）
///
/// 1) 标定：用户点选杠铃片，给出直径像素 -> 米/像素；同时把该区域沿运动轴的一维亮度剖面存为模板。
/// 2) 跟踪：每帧沿运动轴做大范围一维归一化互相关（ZNCC），峰值 + 抛物线亚像素。
/// 3) 平滑：位置 EMA，速度中心差分，死区抑制抖动。
/// 4) 分段：速度过零 + 迟滞 + 最小行程，切出每次向心动作。
final class BarTracker {

    enum Axis { case x, y }

    struct Calibration {
        var metersPerPixel: Double
        var center: CGPoint        // 像素坐标（左上原点）
        var radiusPixels: Double   // 杠铃片半径（像素）
        var axis: Axis
        var sign: Double           // 世界向上 = 图像轴 +1 或 -1
    }

    private let templateLen = 200
    private let searchFactor = 1.7
    private let minScore: Float = 0.28
    private let deadband = 0.035

    private var cal: Calibration?
    private var template: [Float] = []
    private var tMean: Float = 0
    private var tNorm: Float = 1
    private var profileStep: Double = 1
    private var searchLen: Int = 0
    private var referenceCenter: Double = 0
    private var crossSamples: [Int] = []

    private var lastCenter: Double?
    private var smoothedPos: Double = 0
    private var history: [(t: Double, y: Double)] = []
    private var lastTime: Double = 0

    private var phase = 0
    private var repStartY: Double = 0
    private var repStartT: Double = 0
    private var repPeakV: Double = 0
    private var repCount = 0
    private var quiet = 0

    var minTravel: Double = 0.08

    // MARK: - 标定

    func calibrate(pixelBuffer: CVPixelBuffer, center: CGPoint, diameterPixels: Double,
                   plateDiameterMM: Double, axis: Axis, sign: Double) -> Bool {
        let W = Double(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        let H = Double(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))
        guard diameterPixels > 8 else { return false }

        let radius = diameterPixels / 2
        var c = center
        c.x = min(max(c.x, radius), W - radius)
        c.y = min(max(c.y, radius), H - radius)

        cal = Calibration(metersPerPixel: (plateDiameterMM / 1000.0) / diameterPixels,
                          center: c, radiusPixels: radius, axis: axis, sign: sign)

        referenceCenter = axis == .x ? Double(c.x) : Double(c.y)
        profileStep = (2 * radius) / Double(templateLen)
        searchLen = Int(Double(templateLen) * (1 + 2 * searchFactor))

        let crossStart: Int, crossEnd: Int
        if axis == .x {
            crossStart = Int(max(0, c.y - radius)); crossEnd = Int(min(H, c.y + radius))
        } else {
            crossStart = Int(max(0, c.x - radius)); crossEnd = Int(min(W, c.x + radius))
        }
        let span = max(1, crossEnd - crossStart)
        crossSamples = stride(from: crossStart, to: crossEnd, by: max(1, span / 70)).map { $0 }

        let startCenter = referenceCenter - Double(templateLen) * profileStep / 2
        guard let prof = buildProfile(pixelBuffer, start: startCenter, length: templateLen) else { return false }
        template = normalize(prof)
        guard template.contains(where: { abs($0) > 0.05 }) else { return false }

        tMean = 0
        for v in template { tMean += v }
        tMean /= Float(template.count)
        var varSum: Float = 0
        for v in template { varSum += (v - tMean) * (v - tMean) }
        tNorm = sqrt(varSum)
        guard tNorm > 1e-5 else { return false }

        reset()
        lastCenter = referenceCenter
        smoothedPos = 0
        hasPos = true
        return true
    }

    private var hasPos = false

    func reset() {
        phase = 0; repCount = 0; repPeakV = 0; quiet = 0
        history.removeAll()
    }

    // MARK: - 每帧

    func process(pixelBuffer: CVPixelBuffer, time: Double) -> TrackSample? {
        guard let c = cal, !template.isEmpty else { return nil }
        if lastTime > 0, time - lastTime > 0.5 { reset() }
        lastTime = time

        let predicted = lastCenter ?? referenceCenter
        let start = predicted - Double(searchLen) * profileStep / 2
        guard let prof = buildProfile(pixelBuffer, start: start, length: searchLen) else { return nil }

        let n = template.count
        let limit = searchLen - n
        guard limit > 2 else { return nil }

        var bestD = 0
        var bestScore = -Float.greatestFiniteMagnitude
        var scores = [Float](repeating: 0, count: limit)
        for d in 0..<limit {
            var mean: Float = 0
            for i in 0..<n { mean += prof[d + i] }
            mean /= Float(n)
            var num: Float = 0
            var vsum: Float = 0
            for i in 0..<n {
                let a = prof[d + i] - mean
                num += a * (template[i] - tMean)
                vsum += a * a
            }
            let den = sqrt(vsum) * tNorm
            let s: Float = den > 1e-6 ? num / den : 0
            scores[d] = s
            if s > bestScore { bestScore = s; bestD = d }
        }

        guard bestScore > minScore else {
            return TrackSample(time: time, position: smoothedPos, velocity: 0,
                               repIndex: repCount, event: nil, lost: true, confidence: bestScore)
        }

        var refined = Double(bestD)
        if bestD > 0, bestD < limit - 1 {
            let a = Double(scores[bestD - 1]), b = Double(scores[bestD]), c2 = Double(scores[bestD + 1])
            let den = a - 2 * b + c2
            if abs(den) > 1e-7 {
                let delta = 0.5 * (a - c2) / den
                if abs(delta) < 1 { refined += delta }
            }
        }

        let center = start + (refined + Double(n) / 2) * profileStep
        lastCenter = center
        let raw = (referenceCenter - center) * c.metersPerPixel * c.sign

        if !hasPos { hasPos = true; smoothedPos = raw }
        else { smoothedPos += (raw - smoothedPos) * 0.45 }

        history.append((time, smoothedPos))
        if history.count > 12 { history.removeFirst() }

        var v = 0.0
        if let f = history.first, let l = history.last, l.t - f.t > 0.001 {
            v = (l.y - f.y) / (l.t - f.t)
        }
        if abs(v) < deadband { v = 0 }

        var event: RepEvent?
        if phase == 0 {
            if v > deadband {
                phase = 1; repStartY = smoothedPos; repStartT = time; repPeakV = v; quiet = 0
                event = .started
            }
        } else {
            repPeakV = max(repPeakV, v)
            quiet = v <= 0 ? quiet + 1 : 0
            if time - repStartT > 4.0 || quiet >= 3 {
                let travel = smoothedPos - repStartY
                let duration = max(1e-3, time - repStartT)
                if travel >= minTravel {
                    repCount += 1
                    event = .finished(RepSample(index: repCount,
                                                meanVelocity: travel / duration,
                                                peakVelocity: repPeakV,
                                                displacementM: travel,
                                                duration: duration))
                }
                phase = 0; quiet = 0; repPeakV = 0
            }
        }

        return TrackSample(time: time, position: smoothedPos, velocity: v,
                           repIndex: repCount, event: event, lost: false, confidence: bestScore)
    }

    // MARK: - 剖面

    private func buildProfile(_ pb: CVPixelBuffer, start: Double, length: Int) -> [Float]? {
        guard let c = cal, !crossSamples.isEmpty else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return nil }
        let bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let W = Int(CVPixelBufferGetWidthOfPlane(pb, 0))
        let H = Int(CVPixelBufferGetHeightOfPlane(pb, 0))
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var out = [Float](repeating: 0, count: length)
        let cnt = Float(crossSamples.count)
        for i in 0..<length {
            let pos = Int(start + Double(i) * profileStep)
            var acc: Float = 0
            if c.axis == .x {
                if pos < 0 || pos >= W { out[i] = 0; continue }
                for y in crossSamples where y >= 0 && y < H { acc += Float(ptr[y * bpr + pos]) }
            } else {
                if pos < 0 || pos >= H { out[i] = 0; continue }
                let row = pos * bpr
                for x in crossSamples where x >= 0 && x < W { acc += Float(ptr[row + x]) }
            }
            out[i] = acc / cnt
        }
        return out
    }

    private func normalize(_ a: [Float]) -> [Float] {
        guard !a.isEmpty else { return a }
        let mean = a.reduce(0, +) / Float(a.count)
        var res = a.map { $0 - mean }
        let norm = sqrt(res.reduce(0) { $0 + $1 * $1 })
        if norm > 1e-6 { res = res.map { $0 / norm } }
        return res
    }
}
