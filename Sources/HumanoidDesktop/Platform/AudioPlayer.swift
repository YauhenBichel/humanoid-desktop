import AVFoundation
import TeammateKit

/// Plays the teammate's voice with AVAudioPlayer and meters its loudness about 30 times a second.
@MainActor
final class AudioPlayer: NSObject, AudioPlaying {
    private var player: AVAudioPlayer?
    private var meter: Timer?
    private var reportLevel: ((Double) -> Void)?
    private var finished: CheckedContinuation<Void, Never>?

    func play(_ wav: Data, level: @escaping @MainActor (Double) -> Void) async throws {
        stop()
        let player = try AVAudioPlayer(data: wav)
        player.isMeteringEnabled = true
        player.delegate = self
        self.player = player
        reportLevel = level
        let meter = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.measure() }
        }
        // The common modes keep the mouth moving while a menu is open.
        RunLoop.main.add(meter, forMode: .common)
        self.meter = meter
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                finished = continuation
                player.play()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    func stop() {
        meter?.invalidate()
        meter = nil
        player?.stop()
        player = nil
        reportLevel?(0)
        reportLevel = nil
        finished?.resume()
        finished = nil
    }

    private func measure() {
        guard let player else { return }
        player.updateMeters()
        let amplitude = pow(10.0, Double(player.averagePower(forChannel: 0)) / 20.0)
        reportLevel?(min(1.0, amplitude * 6.0))  // the same scale as humanoid-companion's face
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
