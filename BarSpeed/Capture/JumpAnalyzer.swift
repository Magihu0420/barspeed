import Foundation
import Vision
import CoreVideo

/// 纵跳分析：Vision 人体姿态取足部纵向轨迹 -> 起跳/落地 -> 由腾空时间算高度。
final class JumpAnalyzer {

    struct Frame {
        var time: Double
        var feetY: Double?
        var hipY: Double?
    }

    private let request = VNDetectHumanBodyPoseRequest()
    private(set) var frames: [Frame] = []
    private var lastProcessed: Double = -1
    private let minInterval = 1.0 / 30.0

    func reset() {
        frames.removeAll()
        lastProcessed = -1
    }

    func process(pixelBuffer: CVPixelBuffer, time: Double) {
        guard time - lastProcessed >= minInterval else { return }
        lastProcessed = time
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            guard let obs = request.results?.first else {
                frames.append(Frame(time: time, feetY: nil, hipY: nil))
                return
            }
            let pts = try obs.recognizedPoints(.all)
            let ankles = [pts[.leftAnkle]?.y, pts[.rightAnkle]?.y].compactMap { $0 }
            let feet = ankles.min()
            let hip = pts[.root]?.y
            frames.append(Frame(time: time, feetY: feet, hipY: hip))
        } catch {
            frames.append(Frame(time: time, feetY: nil, hipY: nil))
        }
    }

    struct Result {
        var flightTime: Double
        var heightCM: Double
        var takeoffTime: Double
        var landingTime: Double
        var peakHipVelocity: Double
    }

    func analyze(baselineWindow: Double = 0.6) -> Result? {
        let valid: [(t: Double, y: Double)] = frames.compactMap { f in
            guard let y = f.feetY else { return nil }
            return (f.time, y)
        }
        guard valid.count > 10 else { return nil }

        let start = valid[0].t
        let baseVals = valid.filter { $0.t <= start + baselineWindow }.map { $0.y }.sorted()
        guard !baseVals.isEmpty else { return nil }
        let baseline = baseVals[baseVals.count / 2]
        let lift = 0.015

        var takeoff: (t: Double, y: Double)?
        var landing: (t: Double, y: Double)?
        for p in valid {
            if takeoff == nil {
                if p.y - baseline > lift { takeoff = p }
            } else if let to = takeoff, p.y - baseline <= lift * 0.5, p.t > to.t + 0.05 {
                landing = p
                break
            }
        }
        guard let to = takeoff, let la = landing, la.t > to.t else { return nil }
        let flight = la.t - to.t
        guard flight > 0.12, flight < 1.5 else { return nil }

        var vmax = 0.0
        let hips: [(t: Double, y: Double)] = frames.compactMap { f in
            guard let y = f.hipY else { return nil }
            return (f.time, y)
        }
        if hips.count > 4 {
            for i in 1..<hips.count where hips[i].t < to.t {
                let dt = hips[i].t - hips[i - 1].t
                if dt > 0.001 { vmax = max(vmax, (hips[i].y - hips[i - 1].y) / dt) }
            }
        }

        return Result(flightTime: flight,
                      heightCM: VelocityMath.jumpHeight(flightTime: flight) * 100,
                      takeoffTime: to.t,
                      landingTime: la.t,
                      peakHipVelocity: vmax)
    }
}
