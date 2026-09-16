import SwiftUI
import TeammateKit

extension RGB {
    var color: Color { Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
}

/// The bust's layout, as fractions, shared with humanoid-companion's character renderer (character.py) so the
/// desktop and the video clips draw the same robot.
enum BustProportions {
    /// The drawing unit is the frame's width, or three quarters of its height if that is smaller.
    static let unitShareOfHeight = 0.75
    static let headWidth = 0.72  // of the unit
    static let headHeight = 0.56  // of the unit
    static let bezel = 0.035  // of the unit, at least 4 points
    static let headCentreY = 0.40  // of the frame height
    static let headCornerRadius = 0.22  // of the head height
    static let neckLength = 0.16  // of the head height
    static let neckHalfWidth = 0.09  // of the head width
    static let shoulderHalfWidth = 0.62  // of the head width
    static let badgeRadius = 0.05  // of the head width
    static let badgeDrop = 0.22  // of the head height, below the top of the shoulders
}

/// The face's layout on the screen, in face units (a tenth of the screen's shorter side, times the feature scale).
enum FaceLayout {
    static let eyeSpacing = 2.2  // from the centre to each eye
    static let eyeHeightShare = 0.42  // of the screen height, from the top
    static let mouthHeightShare = 0.7  // of the screen height, from the top
    static let eyeWidth = 1.2
    static let eyeHeight = 1.6
    static let mouthWidth = 2.2
    static let glowRadius = 0.35
}

/// The measurements of the head, in the head's own coordinates (its centre is the origin).
struct HeadGeometry {
    let width: Double
    let height: Double
    let bezel: Double
    var frame: CGRect { CGRect(x: -width / 2, y: -height / 2, width: width, height: height) }
    var cornerRadius: Double { height * BustProportions.headCornerRadius }
    var screen: CGRect { frame.insetBy(dx: bezel, dy: bezel) }
}

/// Something worn on the head. Drawn behind the head, in front of it, or both; a new accessory is a new
/// painter, and nothing else changes.
protocol AccessoryPainter {
    func drawBehindHead(in context: inout GraphicsContext, head: HeadGeometry, teammate: Teammate, pose: CharacterPose)
    func drawInFrontOfHead(
        in context: inout GraphicsContext, head: HeadGeometry, teammate: Teammate, pose: CharacterPose)
}

extension AccessoryPainter {
    func drawBehindHead(in context: inout GraphicsContext, head: HeadGeometry, teammate: Teammate, pose: CharacterPose)
    {}
    func drawInFrontOfHead(
        in context: inout GraphicsContext, head: HeadGeometry, teammate: Teammate, pose: CharacterPose
    ) {}
}

struct AntennaPainter: AccessoryPainter {
    func drawBehindHead(in context: inout GraphicsContext, head: HeadGeometry, teammate: Teammate, pose: CharacterPose)
    {
        let length = head.height * 0.2
        let ball = head.height * 0.07
        var stalk = Path()
        stalk.move(to: CGPoint(x: 0, y: head.frame.minY))
        stalk.addLine(to: CGPoint(x: 0, y: head.frame.minY - length))
        context.stroke(stalk, with: .color(teammate.colours.trim.color), lineWidth: head.bezel)
        let pulse = 0.6 + 0.4 * sin(2 * .pi * 0.8 * pose.time)  // a slow blink, like a status light
        let light = CGRect(x: -ball, y: head.frame.minY - length - ball, width: 2 * ball, height: 2 * ball)
        context.fill(Path(ellipseIn: light), with: .color(teammate.colours.glow.color.opacity(pulse)))
    }
}

struct HeadphonesPainter: AccessoryPainter {
    func drawInFrontOfHead(
        in context: inout GraphicsContext, head: HeadGeometry, teammate: Teammate, pose: CharacterPose
    ) {
        let trim = teammate.colours.trim.color
        var band = Path()
        band.addArc(
            center: CGPoint(x: 0, y: head.frame.midY), radius: head.width * 0.56, startAngle: .degrees(195),
            endAngle: .degrees(345), clockwise: false)
        context.stroke(band, with: .color(trim), lineWidth: head.bezel * 1.6)
        let cupWidth = head.width * 0.12
        let cupHeight = head.height * 0.42
        for centreX in [head.frame.minX - cupWidth * 0.55, head.frame.maxX + cupWidth * 0.55] {
            let rectangle = CGRect(x: centreX - cupWidth / 2, y: -cupHeight / 2, width: cupWidth, height: cupHeight)
            let cup = Path(roundedRect: rectangle, cornerRadius: cupWidth * 0.45)
            context.fill(cup, with: .color(trim))
            context.stroke(cup, with: .color(teammate.colours.glow.color), lineWidth: max(2, head.bezel / 2))
        }
    }
}

struct NoAccessoryPainter: AccessoryPainter {}

extension Accessory {
    var painter: any AccessoryPainter {
        switch self {
        case .antenna: AntennaPainter()
        case .headphones: HeadphonesPainter()
        case .noAccessory: NoAccessoryPainter()
        }
    }
}

/// Draws a teammate as a robot bust: shoulders, and a head whose screen shows the face. Pure: the same
/// teammate, expression, pose and size always give the same picture. Proportions follow humanoid-companion's
/// character renderer, so the desktop and the video clips match.
enum CharacterPainter {
    static func draw(
        _ teammate: Teammate,
        expression: FaceExpression,
        pose: CharacterPose,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let unit = min(size.width, size.height * BustProportions.unitShareOfHeight)
        let head = HeadGeometry(
            width: unit * BustProportions.headWidth, height: unit * BustProportions.headHeight,
            bezel: max(4, unit * BustProportions.bezel))
        let centre = CGPoint(x: size.width / 2, y: size.height * BustProportions.headCentreY)
        drawShoulders(teammate, head: head, centre: centre, in: &context, size: size)

        var headContext = context
        headContext.translateBy(x: centre.x, y: centre.y)
        headContext.rotate(by: .degrees(3 * pose.nod * sin(2 * .pi * 1.7 * pose.time)))  // nods with the voice
        let accessory = teammate.accessory.painter
        accessory.drawBehindHead(in: &headContext, head: head, teammate: teammate, pose: pose)
        headContext.fill(
            Path(roundedRect: head.frame, cornerRadius: head.cornerRadius), with: .color(teammate.colours.trim.color))
        headContext.fill(
            Path(roundedRect: head.screen, cornerRadius: max(1, head.cornerRadius - head.bezel)),
            with: .color(teammate.colours.screen.color))
        FacePainter.draw(
            expression.shape, pose: pose, glow: teammate.colours.glow.color, on: head.screen, in: &headContext)
        accessory.drawInFrontOfHead(in: &headContext, head: head, teammate: teammate, pose: pose)
    }

    private static func drawShoulders(
        _ teammate: Teammate,
        head: HeadGeometry,
        centre: CGPoint,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let trim = teammate.colours.trim.color
        let neckTop = centre.y + head.height / 2 - head.bezel
        let shouldersTop = neckTop + head.height * BustProportions.neckLength
        let neck = CGRect(
            x: centre.x - head.width * BustProportions.neckHalfWidth, y: neckTop,
            width: 2 * head.width * BustProportions.neckHalfWidth, height: shouldersTop - neckTop + 4)
        context.fill(Path(neck), with: .color(trim.opacity(0.7)))
        let halfWidth = head.width * BustProportions.shoulderHalfWidth
        let shoulders = CGRect(x: centre.x - halfWidth, y: shouldersTop, width: 2 * halfWidth, height: size.height)
        context.fill(Path(roundedRect: shoulders, cornerRadius: halfWidth * 0.5), with: .color(trim))
        let badge = head.width * BustProportions.badgeRadius
        let badgeCentreY = shouldersTop + head.height * BustProportions.badgeDrop
        let badgeRectangle = CGRect(x: centre.x - badge, y: badgeCentreY - badge, width: 2 * badge, height: 2 * badge)
        context.fill(Path(ellipseIn: badgeRectangle), with: .color(teammate.colours.glow.color))
    }
}

/// The face on the head's screen: eyes, mouth, brows and the expression's extras.
enum FacePainter {
    /// Eyes and mouth are 35 % larger than on humanoid-companion's full-screen face, so they read at desktop size.
    private static let featureScale = 1.35

    static func draw(
        _ shape: FaceExpression.Shape,
        pose: CharacterPose,
        glow: Color,
        on screen: CGRect,
        in context: inout GraphicsContext
    ) {
        let unit = min(screen.width, screen.height) / 10 * featureScale
        var face = context
        face.clip(to: Path(roundedRect: screen, cornerRadius: unit))
        var glowing = face
        glowing.addFilter(.shadow(color: glow.opacity(0.9), radius: unit * FaceLayout.glowRadius))
        drawEyes(shape, pose: pose, glow: glow, screen: screen, unit: unit, in: &glowing)
        drawMouth(shape, pose: pose, glow: glow, screen: screen, unit: unit, in: &glowing)
        drawExtras(shape, pose: pose, glow: glow, screen: screen, unit: unit, in: &face)
    }

    private static func drawEyes(
        _ shape: FaceExpression.Shape, pose: CharacterPose, glow: Color, screen: CGRect, unit: Double,
        in context: inout GraphicsContext
    ) {
        let eyeWidth = unit * FaceLayout.eyeWidth * pose.eyeWidth
        let eyeHeight = max(unit * 0.08, unit * FaceLayout.eyeHeight * pose.eyeOpen * (1 - pose.blink))
        for side in [-1.0, 1.0] {
            let centre = CGPoint(
                x: screen.midX + side * unit * FaceLayout.eyeSpacing + pose.gaze.x * unit,
                y: screen.minY + screen.height * FaceLayout.eyeHeightShare + pose.gaze.y * unit)
            if shape.has(.arcEyes) {
                var arc = Path()
                arc.addArc(
                    center: CGPoint(x: centre.x, y: centre.y + unit * 0.3), radius: eyeWidth * 0.55,
                    startAngle: .degrees(207), endAngle: .degrees(333), clockwise: false)
                context.stroke(arc, with: .color(glow), style: StrokeStyle(lineWidth: unit * 0.35, lineCap: .round))
            } else {
                let eye = CGRect(
                    x: centre.x - eyeWidth / 2, y: centre.y - eyeHeight / 2, width: eyeWidth, height: eyeHeight)
                context.fill(Path(roundedRect: eye, cornerRadius: min(eyeWidth, eyeHeight) / 2), with: .color(glow))
            }
            if shape.has(.sadBrows) {
                // The inner end high and the outer end low; the other way round reads as angry.
                var brow = Path()
                brow.move(to: CGPoint(x: centre.x - side * eyeWidth * 0.6, y: centre.y - unit * 1.45))
                brow.addLine(to: CGPoint(x: centre.x + side * eyeWidth * 0.6, y: centre.y - unit * 1.05))
                context.stroke(brow, with: .color(glow), style: StrokeStyle(lineWidth: unit * 0.22, lineCap: .round))
            }
        }
    }

    private static func drawMouth(
        _ shape: FaceExpression.Shape, pose: CharacterPose, glow: Color, screen: CGRect, unit: Double,
        in context: inout GraphicsContext
    ) {
        let centre = CGPoint(x: screen.midX, y: screen.minY + screen.height * FaceLayout.mouthHeightShare)
        let width = unit * FaceLayout.mouthWidth * pose.mouthWidth
        if pose.mouthOpen > 0.04 || shape.has(.openMouth) {
            let radiusX = shape.has(.openMouth) ? unit * 0.55 : width / 2
            let radiusY = shape.has(.openMouth) ? unit * 0.45 : unit * (0.15 + 1.3 * pose.mouthOpen) / 2
            let oval = CGRect(x: centre.x - radiusX, y: centre.y - radiusY, width: 2 * radiusX, height: 2 * radiusY)
            context.fill(Path(ellipseIn: oval), with: .color(glow))
        } else {
            var smile = Path()
            smile.move(to: CGPoint(x: centre.x - width / 2, y: centre.y))
            smile.addQuadCurve(
                to: CGPoint(x: centre.x + width / 2, y: centre.y),
                control: CGPoint(x: centre.x, y: centre.y + pose.mouthCurve * unit * 1.2))
            context.stroke(smile, with: .color(glow), style: StrokeStyle(lineWidth: unit * 0.28, lineCap: .round))
        }
    }

    private static func drawExtras(
        _ shape: FaceExpression.Shape, pose: CharacterPose, glow: Color, screen: CGRect, unit: Double,
        in context: inout GraphicsContext
    ) {
        if shape.has(.thinkingDots) {
            for index in 0..<3 {
                let isLit = Int(pose.time / 0.3) % 3 == index
                let centre = CGPoint(
                    x: screen.midX + unit * 3.6 + Double(index) * unit * 0.5, y: screen.minY + screen.height * 0.2)
                let dot = CGRect(
                    x: centre.x - unit * 0.13, y: centre.y - unit * 0.13, width: unit * 0.26, height: unit * 0.26)
                context.fill(Path(ellipseIn: dot), with: .color(glow.opacity(isLit ? 1 : 0.3)))
            }
        }
        if shape.has(.listeningRing) {
            let radius = unit * 3.7
            let centreY = screen.minY + screen.height * 0.52
            let ring = CGRect(x: screen.midX - radius, y: centreY - radius, width: 2 * radius, height: 2 * radius)
            let strength = 0.35 + 0.25 * sin(pose.time / 0.25)
            context.stroke(Path(ellipseIn: ring), with: .color(glow.opacity(strength)), lineWidth: max(1, unit * 0.08))
        }
        if shape.has(.sleepyZs) {
            let strength = 0.5 + 0.5 * sin(pose.time / 0.6)
            let letter = Text("z").font(.system(size: unit * 0.7)).foregroundColor(glow.opacity(strength))
            context.draw(letter, at: CGPoint(x: screen.midX + unit * 3.5, y: screen.minY + screen.height * 0.25))
        }
    }
}
