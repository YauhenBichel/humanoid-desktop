/// The seven faces, with the same numbers as humanoid-companion's `expressions.json`, so a teammate looks
/// the same on the desktop, on the robot's head display and in its videos.
public enum FaceExpression: String, CaseIterable, Sendable {
    case neutral, happy, thinking, surprised, sad, listening, sleeping

    /// Where the eyes look, in eye widths from the centre.
    public struct Gaze: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        public static let ahead = Gaze(x: 0, y: 0)
    }

    public enum Feature: Sendable {
        case arcEyes, thinkingDots, openMouth, listeningRing, sleepyZs, sadBrows
    }

    /// The shape of a face, in units of a tenth of the screen's shorter side.
    public struct Shape: Equatable, Sendable {
        public var eyeOpen: Double
        public var eyeWidth: Double
        public var mouthCurve: Double  // above 0 a smile, below 0 a frown
        public var mouthWidth: Double
        public var look: Gaze
        public var features: Set<Feature>

        public func has(_ feature: Feature) -> Bool { features.contains(feature) }
    }

    public var shape: Shape {
        switch self {
        case .neutral:
            Shape(eyeOpen: 1.0, eyeWidth: 1.0, mouthCurve: 0.15, mouthWidth: 0.9, look: .ahead, features: [])
        case .happy:
            Shape(eyeOpen: 0.55, eyeWidth: 1.0, mouthCurve: 0.9, mouthWidth: 1.1, look: .ahead, features: [.arcEyes])
        case .thinking:
            Shape(
                eyeOpen: 0.8, eyeWidth: 0.9, mouthCurve: 0, mouthWidth: 0.5, look: Gaze(x: -0.5, y: -0.6),
                features: [.thinkingDots])
        case .surprised:
            Shape(eyeOpen: 1.35, eyeWidth: 1.1, mouthCurve: 0, mouthWidth: 0.45, look: .ahead, features: [.openMouth])
        case .sad:
            Shape(
                eyeOpen: 0.8, eyeWidth: 1.0, mouthCurve: -0.6, mouthWidth: 0.8, look: Gaze(x: 0, y: 0.4),
                features: [.sadBrows])
        case .listening:
            Shape(
                eyeOpen: 1.1, eyeWidth: 1.0, mouthCurve: 0.25, mouthWidth: 0.7, look: .ahead, features: [.listeningRing]
            )
        case .sleeping:
            Shape(
                eyeOpen: 0.06, eyeWidth: 1.0, mouthCurve: 0.1, mouthWidth: 0.6, look: Gaze(x: 0, y: 0.3),
                features: [.sleepyZs])
        }
    }
}
