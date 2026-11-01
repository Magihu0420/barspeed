import SwiftUI
import AVFoundation
import UIKit

// MARK: - 会话

final class TrainSession: ObservableObject {

    let camera = CameraController()
    let voice = VoiceCoach()
    private let tracker = BarTracker()

    @Published var velocity: Double = 0
    @Published var position: Double = 0
    @Published var reps: [RepSample] = []
    @Published var isTracking = false
    @Published var isCalibrated = false
    @Published var lost = false
    @Published var status = "点两下杠铃片：先上沿，后下沿"
    @Published var tapPoints: [CGPoint] = []      // 归一化坐标，用于画辅助点
    @Published var vlPercent: Double = 0
    @Published var warning = false
    @Published var trail: [TrailPoint] = []

    var exercise: Exercise = .backSquat
    var loadKG: Double = 60
    var voiceMode: VoiceMode = .velocity
    var vlThreshold: Double = 0.20
    var minTravel: Double = 0.08
    var plateMM: Double = 450
    var axis: BarTracker.Axis = .x
    var sign: Double = -1

    private var pendingTaps: [CGPoint] = []

    init() {
        camera.onFrame = { [weak self] pb, time in
            self?.handle(pb, time)
        }
    }

    func addTap(_ p: CGPoint) {
        guard !isTracking else { return }
        if pendingTaps.count >= 2 { pendingTaps.removeAll(); tapPoints.removeAll() }
        pendingTaps.append(p)
        DispatchQueue.main.async { self.tapPoints = self.pendingTaps }
    }

    private func handle(_ pb: CVPixelBuffer, _ time: CMTime) {
        if pendingTaps.count == 2, !isCalibrated {
            let taps = pendingTaps
            pendingTaps.removeAll()
            let W = Double(CVPixelBufferGetWidthOfPlane(pb, 0))
            let H = Double(CVPixelBufferGetHeightOfPlane(pb, 0))
            let a = CGPoint(x: taps[0].x * W, y: taps[0].y * H)
            let b = CGPoint(x: taps[1].x * W, y: taps[1].y * H)
            let diameter = hypot(a.x - b.x, a.y - b.y)
            let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            tracker.minTravel = minTravel
            let ok = tracker.calibrate(pixelBuffer: pb, center: center, diameterPixels: diameter,
                                       plateDiameterMM: plateMM, axis: axis, sign: sign)
            DispatchQueue.main.async {
                self.isCalibrated = ok
                self.status = ok ? "已标定，点击开始记录" : "标定失败：请对准杠铃片，或在设置里调换方向"
                if ok { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            }
            if !ok { return }
        }

        guard isCalibrated, isTracking else { return }
        guard let s = tracker.process(pixelBuffer: pb, time: CMTimeGetSeconds(time)) else { return }
        let v = s.velocity
        let lostFlag = s.lost
        var finished: RepSample?
        if case .finished(let rep)? = s.event { finished = rep }
        let repCount = s.repIndex
        _ = repCount

        DispatchQueue.main.async {
            self.velocity = v
            self.position = s.position
            self.lost = lostFlag
            self.trail.append(TrailPoint(pos: s.position, v: v))
            if self.trail.count > 90 { self.trail.removeFirst(self.trail.count - 90) }
            if let rep = finished {
                self.reps.append(rep)
                let power = VelocityMath.estimatedPeakPower(loadKG: self.loadKG, meanVelocity: rep.meanVelocity)
                self.voice.sayVelocity(rep.meanVelocity, mode: self.voiceMode, power: power, repIndex: rep.index)
                if let first = self.reps.first?.meanVelocity, first > 0.05 {
                    let vl = max(0, (first - rep.meanVelocity) / first)
                    self.vlPercent = vl
                    if vl >= self.vlThreshold {
                        self.warning = true
                        self.voice.speak("速度损失过大", force: true)
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    }
                }
            }
        }
    }

    func start() {
        guard isCalibrated else { return }
        tracker.minTravel = minTravel
        tracker.reset()
        reps.removeAll()
        trail.removeAll()
        vlPercent = 0
        warning = false
        isTracking = true
        status = "记录中…"
        voice.speak("开始", force: true)
    }

    func stop() -> SetRecord? {
        isTracking = false
        status = "本组结束"
        voice.speak("结束", force: true)
        guard !reps.isEmpty else { return nil }
        return SetRecord(exercise: exercise, loadKG: loadKG, date: Date(), reps: reps)
    }

    func resetAll() {
        tracker.reset()
        reps.removeAll()
        isCalibrated = false
        isTracking = false
        pendingTaps.removeAll()
        tapPoints.removeAll()
        trail.removeAll()
        velocity = 0
        position = 0
        vlPercent = 0
        warning = false
        status = "点两下杠铃片：先上沿，后下沿"
    }
}

// MARK: - 页面

struct TrainView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var purchase: PurchaseManager
    @StateObject private var session = TrainSession()

    @State private var exercise: Exercise = .backSquat
    @State private var loadKG: Double = 60
    @State private var showSummary = false
    @State private var summary: SetRecord?
    @State private var showPaywall = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ZStack {
                    CameraPreview(session: session.camera.session) { p in
                        session.addTap(p)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if store.isPro {
                        TrajectoryView(points: session.trail)
                            .padding(.horizontal, 10)
                    }
                    tapMarkers
                    hud
                }
                .overlay(alignment: .top) {
                    if session.lost && session.isTracking {
                        Text("跟踪丢失 · 请让杠铃片留在画面内")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.danger.opacity(0.85))
                            .clipShape(Capsule())
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 12)

                bottomBar
            }
        }
        .onAppear { configure() }
        .onDisappear { session.camera.stop() }
        .onChange(of: store.pendingPlan?.id.uuidString) { _, _ in applyPlan() }
        .sheet(isPresented: $showSummary) {
            if let s = summary { SetSummaryView(record: s) { showSummary = false } }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func applyPlan() {
        guard let plan = store.pendingPlan else { return }
        exercise = plan.exercise
        session.exercise = plan.exercise
        loadKG = plan.loadKG
        session.loadKG = plan.loadKG
        store.pendingPlan = nil
    }

    private func configure() {
        session.exercise = exercise
        session.loadKG = loadKG
        session.voiceMode = store.settings.voiceMode
        session.vlThreshold = store.settings.velocityLossThreshold
        session.minTravel = store.settings.minTravelM
        session.plateMM = store.settings.plateDiameterMM
        Task {
            let ok = await session.camera.requestAccess()
            guard ok else { return }
            session.camera.configure(position: .back)
            session.camera.start()
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(Exercise.allCases) { ex in
                    Button(ex.name) {
                        exercise = ex
                        session.exercise = ex
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(exercise.name).font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.text)
            }

            Spacer()

            Button {
                loadKG = max(store.settings.barWeightKG, loadKG - 2.5)
                session.loadKG = loadKG
            } label: { Image(systemName: "minus.circle") }

            Text(String(format: "%.1f kg", loadKG))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .frame(width: 82)

            Button {
                loadKG += 2.5
                session.loadKG = loadKG
            } label: { Image(systemName: "plus.circle") }

            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
        .font(.system(size: 18))
        .foregroundStyle(Theme.sub)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: 叠加层

    private var tapMarkers: some View {
        GeometryReader { geo in
            ForEach(session.tapPoints.indices, id: \.self) { i in
                let p = session.tapPoints[i]
                Circle()
                    .stroke(Theme.warn, lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.2f", session.velocity))
                        .font(.system(size: 58, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.zoneColor(session.velocity))
                    Text("m/s")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.sub)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Pill(text: "第 \(session.reps.count) 次", color: Theme.accent)
                    if store.settings.showPower {
                        Pill(text: String(format: "%.0f W", VelocityMath.estimatedPeakPower(loadKG: loadKG, meanVelocity: session.velocity)),
                             color: Color(red: 0.55, green: 0.72, blue: 1.0))
                    }
                    Pill(text: String(format: "位移 %.0f cm", session.position * 100),
                         color: Theme.warn)
                    if session.vlPercent > 0 {
                        Pill(text: String(format: "VL %.0f%%", session.vlPercent * 100),
                             color: session.warning ? Theme.danger : Theme.sub)
                    }
                }
            }
            Spacer()
            if !session.isCalibrated {
                Text(session.status)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.bottom, 10)
            }
        }
        .padding(14)
        .allowsHitTesting(false)
    }

    // MARK: 底部

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if session.isTracking {
                Button {
                    if let s = session.stop() {
                        summary = s
                        store.add(s)
                        showSummary = true
                    }
                } label: {
                    Text("结束本组")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.danger)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            } else {
                Button {
                    session.start()
                } label: {
                    Text(session.isCalibrated ? "开始记录" : "需要先标定")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(session.isCalibrated ? Theme.accent : Theme.cardAlt)
                        .foregroundStyle(session.isCalibrated ? .black : Theme.sub)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!session.isCalibrated)
            }

            HStack {
                Button {
                    session.resetAll()
                } label: {
                    Label("重新标定", systemImage: "scope")
                }
                Spacer()
                Button {
                    session.camera.flip()
                } label: {
                    Label("切镜头", systemImage: "arrow.triangle.2.circlepath.camera")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.sub)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

// MARK: - 单组结算

struct SetSummaryView: View {
    let record: SetRecord
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(record.exercise.name).font(.system(size: 20, weight: .bold))
                            Text(String(format: "%.1f kg · %d 次 · %@", record.loadKG, record.repCount,
                                        record.date.formatted(date: .abbreviated, time: .shortened)))
                                .font(.system(size: 13)).foregroundStyle(Theme.sub)
                        }
                    }
                    HStack(spacing: 12) {
                        metric("均速", String(format: "%.2f", record.meanVelocity), "m/s")
                        metric("峰速", String(format: "%.2f", record.peakVelocity), "m/s")
                        metric("速度损失", String(format: "%.0f%%", record.velocityLoss * 100), "")
                    }
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("次数").frame(width: 44, alignment: .leading)
                                Text("均速").frame(maxWidth: .infinity, alignment: .trailing)
                                Text("峰速").frame(maxWidth: .infinity, alignment: .trailing)
                                Text("行程").frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.sub)
                            .padding(.horizontal, 16).padding(.vertical, 10)

                            ForEach(record.reps) { r in
                                Divider().overlay(Theme.line)
                                HStack {
                                    Text("\(r.index)").frame(width: 44, alignment: .leading)
                                    Text(String(format: "%.2f", r.meanVelocity)).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(String(format: "%.2f", r.peakVelocity)).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(String(format: "%.0f", r.displacementCM)).frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .font(.system(size: 14, weight: .medium))
                                .monospacedDigit()
                                .padding(.horizontal, 16).padding(.vertical, 9)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("本组结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成", action: onClose) }
            }
        }
        .presentationDetents([.large])
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12)).foregroundStyle(Theme.sub)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                    if !unit.isEmpty {
                        Text(unit).font(.system(size: 11)).foregroundStyle(Theme.sub)
                    }
                }
            }
        }
    }
}
