import AVFoundation

/// 语音播报 + 触感。用系统 TTS，不依赖第三方。
final class VoiceCoach {

    private let synth = AVSpeechSynthesizer()
    private var lastSpoken = Date.distantPast
    private var lastText = ""

    @discardableResult
    func speak(_ text: String, force: Bool = false) -> Bool {
        guard !text.isEmpty else { return false }
        let now = Date()
        if !force {
            if now.timeIntervalSince(lastSpoken) < 0.7 { return false }
            if text == lastText, now.timeIntervalSince(lastSpoken) < 1.6 { return false }
        }
        lastSpoken = now
        lastText = text
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.52
        u.pitchMultiplier = 1.0
        u.volume = 1.0
        synth.speak(u)
        return true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    func sayVelocity(_ v: Double, mode: VoiceMode, power: Double, repIndex: Int) {
        switch mode {
        case .silent:
            return
        case .velocity:
            speak(String(format: "%.2f", v))
        case .velocityAndPower:
            speak(String(format: "%.2f, %.0f 瓦", v, power))
        case .full:
            speak(String(format: "第%d个, %.2f, %.0f 瓦", repIndex, v, power))
        }
    }
}
