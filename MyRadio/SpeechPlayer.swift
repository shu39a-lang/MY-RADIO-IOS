import AVFoundation
import Foundation

@MainActor
final class SpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(_ program: RadioProgram, style: String) {
        synthesizer.stopSpeaking(at: .immediate)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 音声出力の設定に失敗しても読み上げ自体を試みる。
            print("Audio session warning: \(error.localizedDescription)")
        }
        let utterance = AVSpeechUtterance(string: program.script)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = style == "落ち着いた解説" ? 0.47 : 0.51
        utterance.pitchMultiplier = style == "元気なDJ" ? 1.11 : 1.0
        utterance.preUtteranceDelay = 0.15
        synthesizer.speak(utterance)
        isSpeaking = true
        isPaused = false
    }

    func togglePause() {
        if isPaused {
            if synthesizer.continueSpeaking() { isPaused = false }
        } else if synthesizer.pauseSpeaking(at: .word) {
            isPaused = true
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
        }
    }
}
