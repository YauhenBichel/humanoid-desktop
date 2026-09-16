/// The seven faces, with the same numbers as humanoid-companion's expressions.json, so a teammate looks
/// the same on the desktop, on the robot's head display and in its videos.
public enum FaceExpression: String, CaseIterable, Equatable {
    case neutral, happy, thinking, surprised, sad, listening, sleeping

    /// Shape of the face, in units of a tenth of the screen's shorter side.
    public struct Shape: Equatable {
        public var eyeOpen: Double  // eye height factor
        public var eyeWidth: Double  // eye width factor
        public var eyeTilt: Double  // radians
        public var mouthCurve: Double  // + smile, - frown
        public var mouthWidth: Double  // factor
        public var look: (x: Double, y: Double)  // gaze offset, in eye units
        public var arcEyes = false  // happy: upturned arcs
        public var thinkingDots = false
        public var openMouth = false  // surprised
        public var listeningRing = false
        public var sleepyZs = false
        public var sadBrows = false

        public static func == (lhs: Shape, rhs: Shape) -> Bool {
            lhs.eyeOpen == rhs.eyeOpen && lhs.eyeWidth == rhs.eyeWidth && lhs.eyeTilt == rhs.eyeTilt
                && lhs.mouthCurve == rhs.mouthCurve && lhs.mouthWidth == rhs.mouthWidth && lhs.look == rhs.look
                && lhs.arcEyes == rhs.arcEyes && lhs.thinkingDots == rhs.thinkingDots && lhs.openMouth == rhs.openMouth
                && lhs.listeningRing == rhs.listeningRing && lhs.sleepyZs == rhs.sleepyZs && lhs.sadBrows == rhs.sadBrows
        }
    }

    public var shape: Shape {
        switch self {
        case .neutral: Shape(eyeOpen: 1.0, eyeWidth: 1.0, eyeTilt: 0, mouthCurve: 0.15, mouthWidth: 0.9, look: (0, 0))
        case .happy: Shape(eyeOpen: 0.55, eyeWidth: 1.0, eyeTilt: 0, mouthCurve: 0.9, mouthWidth: 1.1, look: (0, 0), arcEyes: true)
        case .thinking:
            Shape(eyeOpen: 0.8, eyeWidth: 0.9, eyeTilt: 0, mouthCurve: 0, mouthWidth: 0.5, look: (-0.5, -0.6), thinkingDots: true)
        case .surprised:
            Shape(eyeOpen: 1.35, eyeWidth: 1.1, eyeTilt: 0, mouthCurve: 0, mouthWidth: 0.45, look: (0, 0), openMouth: true)
        case .sad: Shape(eyeOpen: 0.8, eyeWidth: 1.0, eyeTilt: 0.35, mouthCurve: -0.6, mouthWidth: 0.8, look: (0, 0.4), sadBrows: true)
        case .listening:
            Shape(eyeOpen: 1.1, eyeWidth: 1.0, eyeTilt: 0, mouthCurve: 0.25, mouthWidth: 0.7, look: (0, 0), listeningRing: true)
        case .sleeping: Shape(eyeOpen: 0.06, eyeWidth: 1.0, eyeTilt: 0, mouthCurve: 0.1, mouthWidth: 0.6, look: (0, 0.3), sleepyZs: true)
        }
    }
}
