import SwiftUI
import AVFoundation

final class JumpSession: ObservableObject {
    let camera = CameraController()
    let analyzer = JumpAnalyzer()
    let voice = VoiceCoach()

    @Published var measuring = false
    @Published var result: JumpAnalyzer.Result?
    @Published var status = "把手机横放或竖放对准起跳区域"

    init() {
        camera.onFrame = { [weak self] pb, time in
            self?.analyzer.process(pixelBuffer: pb, time: CMTimeGetSeconds(time))
        }
    }

    func start() {
        analyzer.reset()
        result = nil
        measuring = true
        status = "测量中：跳一次"
        voice.speak("准备", force: true)
    }

    func stop() {
        measuring = false
        if let r = analyzer.analyze() {
            result = r
            status = String(format: "跳跃高度 %.1f cm", r.heightCM)
            voice.speak(String(format: "%.0f 厘米", r.heightCM), force: true)
        } else {
            status = "没识别到完整的起跳-落地，再试一次"
        }
    }
}

struct JumpView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var session = JumpSession()
    @State private var kind: JumpKind = .cmj
    @State private var saved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                ZStack {
                    CameraPreview(session: session.camera.session) { _ in }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack {
                        HStack {
                            Pill(text: kind.name, color: Theme.accent)
                            Spacer()
                            if session.measuring {
                                Pill(text: "● 测量中", color: Theme.danger)
                            }
                        }
                        .padding(12)
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)

                if let r = session.result {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: "%.1f cm", r.heightCM))
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                            Text(String(format: "腾空 %.3f s · 起跳 %.2fs · 落地 %.2fs",
                                        r.flightTime, r.takeoffTime, r.landingTime))
                                .font(.system(size: 12)).foregroundStyle(Theme.sub)
                            Button {
                                store.add(JumpRecord(kind: kind, date: Date(),
                                                     heightCM: r.heightCM, flightTime: r.flightTime))
                                saved = true
                            } label: {
                                Text(saved ? "已保存" : "保存这次跳跃")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(saved ? Theme.cardAlt : Theme.accent.opacity(0.18))
                                    .foregroundStyle(saved ? Theme.sub : Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(saved)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Text(session.status)
                    .font(.system(size: 12)).foregroundStyle(Theme.sub)

                Button {
                    if session.measuring { session.stop() } else { session.start(); saved = false }
                } label: {
                    Text(session.measuring ? "结束测量" : "开始测量")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(session.measuring ? Theme.danger : Theme.accent)
                        .foregroundStyle(session.measuring ? .white : .black)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 16)

                Picker("跳跃类型", selection: $kind) {
                    ForEach(JumpKind.allCases) { k in Text(k.name).tag(k) }
                }
                .pickerStyle(.menu)
                .tint(Theme.sub)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(Theme.bg)
            .navigationTitle("纵跳")
            .task {
                let ok = await session.camera.requestAccess()
                guard ok else { return }
                session.camera.configure(position: .back)
                session.camera.start()
            }
            .onDisappear { session.camera.stop() }
        }
    }
}
