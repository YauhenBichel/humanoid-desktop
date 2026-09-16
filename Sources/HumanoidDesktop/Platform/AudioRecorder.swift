import AVFoundation
import TeammateKit

/// Records 16 kHz mono WAV from the microphone while the talk shortcut is held.
@MainActor
final class AudioRecorder: AudioRecording {
    /// A tap on the shortcut, not a word.
    private static let shortestRecording: TimeInterval = 0.3

    private var recorder: AVAudioRecorder?
    private let file = FileManager.default.temporaryDirectory.appendingPathComponent("humanoid-desktop-speech.wav")

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    func start() throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: file, settings: settings)
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder
    }

    func stop() -> Data? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        defer { try? FileManager.default.removeItem(at: file) }  // recordings never stay on disk
        guard duration >= Self.shortestRecording else { return nil }
        return try? Data(contentsOf: file)
    }

    enum RecorderError: Error, CustomStringConvertible {
        case couldNotStart
        var description: String { "the microphone did not start recording" }
    }
}
