import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var purchase: PurchaseManager
    @State private var showPaywall = false
    @State private var mvtExercise: Exercise = .backSquat
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                membership

                Section("语音播报") {
                    Picker("模式", selection: $store.settings.voiceMode) {
                        ForEach(VoiceMode.allCases) { m in Text(m.name).tag(m) }
                    }
                }

                Section("速度损失") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("疲劳阈值")
                            Spacer()
                            Text("\(Int(store.settings.velocityLossThreshold * 100))%")
                                .monospacedDigit().foregroundStyle(Theme.accent)
                        }
                        Slider(value: $store.settings.velocityLossThreshold, in: 0.05...0.5, step: 0.01)
                            .tint(Theme.accent)
                        Text("本组最快速下降超过该比例时提示，常见取值 10%–30%（力量 20%、爆发力 10%）。")
                            .font(.system(size: 11)).foregroundStyle(Theme.sub)
                    }
                    Toggle("到阈值时触感提醒", isOn: $store.settings.hapticsOnLoss)
                }

                Section("动作行程") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("最小行程")
                            Spacer()
                            Text(String(format: "%.2f m", store.settings.minTravelM))
                                .monospacedDigit().foregroundStyle(Theme.accent)
                        }
                        Slider(value: $store.settings.minTravelM, in: 0.05...0.8, step: 0.01)
                            .tint(Theme.accent)
                        Text("行程小于该值时不计次数，避免抖动误判。")
                            .font(.system(size: 11)).foregroundStyle(Theme.sub)
                    }
                }

                Section("器材") {
                    Picker("杠铃片直径", selection: $store.settings.plateDiameterMM) {
                        Text("450 mm（标准 45 磅片）").tag(450.0)
                        Text("400 mm").tag(400.0)
                        Text("325 mm").tag(325.0)
                        Text("228 mm（10 kg 片）").tag(228.0)
                    }
                    Stepper("杠铃杆 \(Int(store.settings.barWeightKG)) kg",
                            value: $store.settings.barWeightKG, in: 5...30, step: 2.5)
                    Toggle("HUD 显示功率", isOn: $store.settings.showPower)
                }

                Section("动作 MVT（最小速度阈值）") {
                    Picker("动作", selection: $mvtExercise) {
                        ForEach(Exercise.allCases) { ex in Text(ex.name).tag(ex) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("阈值速度")
                            Spacer()
                            Text(String(format: "%.2f m/s", store.mvt(for: mvtExercise)))
                                .monospacedDigit().foregroundStyle(Theme.accent)
                        }
                        Slider(value: Binding(
                            get: { store.mvt(for: mvtExercise) },
                            set: { store.settings.customMVT[mvtExercise.rawValue] = $0 }
                        ), in: 0.10...0.90, step: 0.01)
                        .tint(Theme.accent)
                        Text("用于 1RM 估算。不同动作的真实 MVT 不同，建议先做一次 1RM 测试校准。")
                            .font(.system(size: 11)).foregroundStyle(Theme.sub)
                    }
                }

                Section("数据") {
                    Button {
                        exportURL = makeCSV()
                    } label: {
                        Label("导出全部记录 CSV", systemImage: "square.and.arrow.up")
                    }
                    if let url = exportURL {
                        ShareLink(item: url) { Text("保存文件") }
                    }
                    if !store.isPro {
                        Text("免费版仅显示最近 \(store.freeHistoryDays) 天记录，导出需开通会员。")
                            .font(.system(size: 11)).foregroundStyle(Theme.sub)
                    }
                }

                Section("演示与支持") {
                    Button {
                        store.loadDemoData()
                    } label: {
                        Label("载入演示数据", systemImage: "wand.and.stars")
                    }
                    Text("没有杠铃也能看到完整的 LVP 曲线与趋势，便于体验或截图。")
                        .font(.system(size: 11)).foregroundStyle(Theme.sub)
                }

                Section("关于") {
                    HStack { Text("版本"); Spacer(); Text("1.0.0").foregroundStyle(Theme.sub) }
                    Link("隐私政策", destination: URL(string: "https://example.com/privacy")!)
                    Link("用户协议", destination: URL(string: "https://example.com/terms")!)
                    NavigationLink("训练原理说明") { AboutView() }
                }

                Section {
                    Text("本应用提供的速度与负荷分析仅用于训练参考，不构成医疗建议。请在安全环境下训练，必要时请教练协助。")
                        .font(.system(size: 11)).foregroundStyle(Theme.sub)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("我的")
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private var membership: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(store.isPro ? "BarSpeed Pro" : "免费版")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(store.isPro ? Theme.accent : Theme.text)
                    Spacer()
                    if store.isPro { Pill(text: "已开通", color: Theme.accent) }
                }
                Text(store.isPro
                     ? "全部动作 LVP、1RM 预测、推荐负重、长期趋势与导出已解锁。"
                     : "免费版可无限测速、保留 \(store.freeHistoryDays) 天记录、查看 1 个动作的 LVP。")
                    .font(.system(size: 12)).foregroundStyle(Theme.sub)
                if !store.isPro {
                    Button { showPaywall = true } label: {
                        Text("解锁 Pro")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent).foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                } else {
                    Button("恢复购买") { Task { await purchase.restore() } }
                        .font(.system(size: 13))
                }
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(Theme.card)
    }

    private func makeCSV() -> URL? {
        guard store.isPro else { return nil }
        var csv = "date,exercise,load_kg,reps,mean_velocity,peak_velocity,displacement_m\n"
        let f = ISO8601DateFormatter()
        for s in store.sets {
            let reps = s.reps.map { String(format: "%.3f", $0.meanVelocity) }.joined(separator: "|")
            csv += "\(f.string(from: s.date)),\(s.exercise.name),\(s.loadKG),\(s.repCount),"
            csv += "\(String(format: "%.3f", s.meanVelocity)),\(String(format: "%.3f", s.peakVelocity)),"
            csv += "\(String(format: "%.3f", s.displacementM))\n"
            _ = reps
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BarSpeed-\(Int(Date().timeIntervalSince1970)).csv")
        do { try csv.data(using: .utf8)?.write(to: url); return url } catch { return nil }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("为什么用速度而不是次数").font(.system(size: 17, weight: .bold))
                Text("同样的 5 次，用 80% 1RM 做和用 70% 做，疲劳程度完全不同。杠铃平均速度反映的是神经系统当下的输出能力，比次数更能说明「这一组还有没有价值」。")
                    .font(.system(size: 14)).foregroundStyle(Theme.sub)

                Text("速度损失怎么用").font(.system(size: 17, weight: .bold))
                Text("本组最快速记为基准。当某一次的平均速度相对基准下降超过阈值（如 20%），说明已经进入明显疲劳区，继续做只会增加恢复成本，对力量增长帮助有限。")
                    .font(.system(size: 14)).foregroundStyle(Theme.sub)

                Text("LVP 与 1RM").font(.system(size: 17, weight: .bold))
                Text("负重-速度曲线是近似线性的：重量越大，能推起的速度越慢。采集至少 4–6 个不同重量的最好成绩后，可以拟合出直线，再用该动作的最小速度阈值（MVT）反推 1RM，或者反过来用目标速度算今天该上多少 kg。")
                    .font(.system(size: 14)).foregroundStyle(Theme.sub)

                Text("测量原理").font(.system(size: 17, weight: .bold))
                Text("手机固定在杠铃正前方，用摄像头追踪杠铃（或杠铃片中心）在画面中的位移。标定时输入杠铃片直径换算像素与实际长度的比例，之后逐帧计算位移与速度。")
                    .font(.system(size: 14)).foregroundStyle(Theme.sub)
            }
            .padding(20)
        }
        .background(Theme.bg)
        .navigationTitle("训练原理")
    }
}
