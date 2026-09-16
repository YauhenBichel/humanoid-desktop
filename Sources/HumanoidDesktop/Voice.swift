import AVFoundation
import Foundation

/// Plays the teammate's voice and reports how loud it is, about 30 times a second, for the mouth.
@MainActor
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var meter: Timer?
    private var finished: (() -> Void)?

    /// `level` gets 0...1 while speaking (loudness x 6, like the companion's face) and 0 at the end.
    func play(_ wav: Data, level: @escaping (Double) -> Void, finished: @escaping () -> Void) throws {
        stop()
        let player = try AVAudioPlayer(data: wav)
        player.isMeteringEnabled = true
        player.delegate = self
        self.player = player
        self.finished = { level(0); finished() }
        player.play()
        meter = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let player = self?.player else { return }
                player.updateMeters()
                let amplitude = pow(10.0, Double(player.averagePower(forChannel: 0)) / 20.0)
                level(min(1.0, amplitude * 6.0))
            }
        }
    }

    func stop() {
        meter?.invalidate()
        meter = nil
        player?.stop()
        player = nil
        let done = finished
        finished = nil
        done?()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

/// Records from the microphone while the talk shortcut is held, as 16 kHz mono WAV for transcription.
@MainActor
final class VoiceRecorder {
    private var recorder: AVAudioRecorder?
    private let file = FileManager.default.temporaryDirectory.appendingPathComponent("humanoid-desktop-speech.wav")

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    var isRecording: Bool { recorder?.isRecording ?? false }

    func start() throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: file, settings: settings)
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder
    }

    /// The recording, or nil when it was too short to hold a word (a tap on the shortcut).
    func stop() -> Data? {
        guard let recorder else { return nil }
        let seconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        defer { try? FileManager.default.removeItem(at: file) }
        guard seconds >= 0.3 else { return nil }
        return try? Data(contentsOf: file)
    }

    enum RecorderError: Error { case couldNotStart }
}
