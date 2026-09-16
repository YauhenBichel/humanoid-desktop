import SwiftUI
import TeammateKit

/// The animated character: a pose per display frame, painted by CharacterPainter.
struct CharacterView: View {
    let teammate: Teammate
    let expression: FaceExpression
    /// Read once per frame; the session does not publish every change of the voice's loudness.
    let voiceLevel: () -> Double
    @State private var animator = FaceAnimator()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let pose = animator.pose(
                    at: timeline.date.timeIntervalSinceReferenceDate, expression: expression, voiceLevel: voiceLevel())
                CharacterPainter.draw(teammate, expression: expression, pose: pose, in: &context, size: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(teammate.name), looking \(expression.rawValue)")
    }
}
