import Foundation
import TeammateKit

/// Everything that moves in one frame of the character.
struct CharacterPose: Equatable {
    var eyeOpen = 1.0
    var eyeWidth = 1.0
    var mouthCurve = 0.15
    var mouthWidth = 0.9
    var gaze = FaceExpression.Gaze.ahead
    var mouthOpen = 0.0  // 0...1, from the voice
    var nod = 0.0  // 0...1, the voice's loudness smoothed
    var blink = 0.0  // 1 = eyes closed
    var time = 0.0  // seconds, for the blinking antenna, thinking dots and listening ring
}

/// Eases the face towards each expression and adds life: blinks and a wandering gaze. The same easing as
/// humanoid-companion's face page: 15 % of the way per 60 Hz frame.
final class FaceAnimator {
    private var pose = CharacterPose()
    private var lastTime: Double?
    private var nextBlink = 2.5
    private var blinkStarted = -1.0
    private var nextGazeShift = 0.0
    private var gazeWander = FaceExpression.Gaze.ahead

    func pose(at time: Double, expression: FaceExpression, voiceLevel: Double) -> CharacterPose {
        let elapsed = min(0.1, max(0, time - (lastTime ?? time)))
        lastTime = time
        let shape = expression.shape
        let ease = 1 - pow(0.85, 60 * elapsed)
        pose.eyeOpen += (shape.eyeOpen - pose.eyeOpen) * ease
        pose.eyeWidth += (shape.eyeWidth - pose.eyeWidth) * ease
        pose.mouthCurve += (shape.mouthCurve - pose.mouthCurve) * ease
        pose.mouthWidth += (shape.mouthWidth - pose.mouthWidth) * ease

        if time >= nextBlink {
            blinkStarted = time
            nextBlink = time + 2.5 + Double.random(in: 0...3.5)
        }
        if time >= nextGazeShift {
            gazeWander = .init(x: Double.random(in: -0.2...0.2), y: Double.random(in: -0.125...0.125))
            nextGazeShift = time + 1.5 + Double.random(in: 0...2.5)
        }
        let follow = 1 - pow(0.92, 60 * elapsed)
        pose.gaze.x += (shape.look.x + gazeWander.x - pose.gaze.x) * follow
        pose.gaze.y += (shape.look.y + gazeWander.y - pose.gaze.y) * follow
        pose.mouthOpen += (voiceLevel - pose.mouthOpen) * min(1, 30 * elapsed)
        pose.nod += (pose.mouthOpen - pose.nod) * min(1, 18 * elapsed)
        pose.blink = expression == .sleeping ? 0 : max(0, 1 - (time - blinkStarted) / 0.15)
        pose.time = time
        return pose
    }
}
