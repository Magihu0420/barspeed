import Foundation

@MainActor
final class AppStore: ObservableObject {

    static let shared = AppStore()

    @Published var settings: AppSettings { didSet { persistSettings() } }
    @Published private(set) var sets: [SetRecord] = []
    @Published private(set) var jumps: [JumpRecord] = []
    @Published var isPro: Bool = false
    /// 底部 Tab 选中项（0=训练）
    @Published var selectedTab: Int = 0
    /// 「自动计划」点「用这个重量开始」后传给训练页的计划
    @Published var pendingPlan: TrainingPlan?

    /// 免费额度：LVP 只开放一个动作
    let freeExercise: Exercise = .backSquat
    /// 免费额度：记录保留天数
    let freeHistoryDays: Int = 7

    private let dir: URL
    private let setsURL: URL
    private let jumpsURL: URL
    private let settingsURL: URL
    private let mediaDir: URL

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = support.appendingPathComponent("BarSpeed", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        mediaDir = dir.appendingPathComponent("Video", isDirectory: true)
        try? fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        setsURL = dir.appendingPathComponent("sets.json")
        jumpsURL = dir.appendingPathComponent("jumps.json")
        settingsURL = dir.appendingPathComponent("settings.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        settings = (try? decoder.decode(AppSettings.self, from: (try? Data(contentsOf: settingsURL)) ?? Data())) ?? AppSettings()
        sets = (try? decoder.decode([SetRecord].self, from: (try? Data(contentsOf: setsURL)) ?? Data())) ?? []
        jumps = (try? decoder.decode([JumpRecord].self, from: (try? Data(contentsOf: jumpsURL)) ?? Data())) ?? []
        sets.sort { $0.date > $1.date }
        jumps.sort { $0.date > $1.date }
    }

    // MARK: - 写入

    func add(_ set: SetRecord) {
        sets.insert(set, at: 0)
        persistSets()
    }

    func delete(_ set: SetRecord) {
        sets.removeAll { $0.id == set.id }
        if let name = set.videoFileName {
            try? FileManager.default.removeItem(at: mediaDir.appendingPathComponent(name))
        }
        persistSets()
    }

    func update(_ set: SetRecord) {
        if let i = sets.firstIndex(where: { $0.id == set.id }) {
            sets[i] = set
            persistSets()
        }
    }

    func add(_ jump: JumpRecord) {
        jumps.insert(jump, at: 0)
        persistJumps()
    }

    func delete(_ jump: JumpRecord) {
        jumps.removeAll { $0.id == jump.id }
        persistJumps()
    }

    func mvt(for ex: Exercise) -> Double {
        settings.customMVT[ex.rawValue] ?? ex.mvt
    }

    func mediaURL(_ name: String) -> URL { mediaDir.appendingPathComponent(name) }
    func newMediaURL() -> (name: String, url: URL) {
        let name = UUID().uuidString + ".mov"
        return (name, mediaDir.appendingPathComponent(name))
    }

    private func persistSets() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(sets) { try? data.write(to: setsURL) }
    }

    private func persistJumps() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(jumps) { try? data.write(to: jumpsURL) }
    }

    private func persistSettings() {
        let enc = JSONEncoder()
        if let data = try? enc.encode(settings) { try? data.write(to: settingsURL) }
    }

    // MARK: - 查询

    var recentSets: [SetRecord] {
        isPro ? sets : sets.filter { Date().timeIntervalSince($0.date) <= Double(freeHistoryDays) * 86_400 }
    }

    func sets(for ex: Exercise) -> [SetRecord] { sets.filter { $0.exercise == ex } }

    func canViewLVP(_ ex: Exercise) -> Bool { isPro || ex == freeExercise }

    /// 最近 90 天、按重量取最好成绩，作为 LVP 采样点
    func lvpPoints(for ex: Exercise, days: Int = 180) -> [LVPPoint] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let relevant = sets.filter { $0.exercise == ex && $0.date >= cutoff && !$0.reps.isEmpty }
        var best: [Double: (v: Double, d: Date)] = [:]
        for s in relevant {
            let key = (s.loadKG * 2).rounded() / 2
            let v = s.bestMeanVelocity
            if let cur = best[key] {
                if v > cur.v { best[key] = (v, s.date) }
            } else {
                best[key] = (v, s.date)
            }
        }
        return best.keys.sorted().compactMap { k in
            guard let e = best[k] else { return nil }
            return LVPPoint(exercise: ex, load: k, velocity: e.v, date: e.d)
        }
    }

    func lvpFit(for ex: Exercise) -> LVPFit {
        VelocityMath.fit(points: lvpPoints(for: ex).map { (load: $0.load, velocity: $0.velocity) })
    }

    var exercisesWithData: [Exercise] {
        Exercise.allCases.filter { ex in sets.contains { $0.exercise == ex } }
    }

    // MARK: - 演示数据（审核用：审核员不会有杠铃）

    /// 造 5 组深蹲样本，让 LVP 曲线、1RM、趋势页在没有训练数据时也能展示。
    func loadDemoData() {
        let plan: [(kg: Double, v: Double)] = [(60, 1.05), (80, 0.88), (100, 0.72), (120, 0.58), (140, 0.45)]
        let now = Date()
        for (i, item) in plan.enumerated() {
            var reps: [RepSample] = []
            for r in 1...5 {
                let v = item.v * (1 - Double(r - 1) * 0.05)
                reps.append(RepSample(index: r, meanVelocity: v, peakVelocity: v * 1.35,
                                      displacementM: 0.55, duration: 1.2))
            }
            let rec = SetRecord(exercise: .backSquat, loadKG: item.kg,
                                date: now.addingTimeInterval(-Double(i) * 86_400), reps: reps,
                                note: "演示数据")
            add(rec)
        }
    }

    // MARK: - 汇总

    func weeklyVolume(days: Int = 28) -> [(date: Date, volume: Double)] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date().addingTimeInterval(-Double(days) * 86_400))
        var buckets: [Date: Double] = [:]
        for s in sets where s.date >= start {
            let day = cal.startOfDay(for: s.date)
            buckets[day, default: 0] += s.loadKG * Double(s.repCount)
        }
        return buckets.keys.sorted().map { (date: $0, volume: buckets[$0]!) }
    }
}
