import SwiftUI
import TeammateKit

extension RGB {
    var color: Color { Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
}

/// The face's moving parts between frames: eased shape values, blinks and wandering gaze. The same
/// easing as humanoid-companion's face page (15 % per 60 Hz frame towards the target expression).
final class FaceMotion {
    var open = 1.0, width = 1.0, curve = 0.15, mouthWidth = 0.9
    var gaze = (x: 0.0, y: 0.0), gazeTarget = (x: 0.0, y: 0.0)
    var mouth = 0.0, nod = 0.0
    private var lastTime: Double?
    private var nextBlink = 2.5, blinkAt = -1.0, nextGaze = 0.0

    func advance(to time: Double, expression: FaceExpression, loudness: Double) -> Double {
        let dt = min(0.1, max(0, time - (lastTime ?? time)))
        lastTime = time
        let shape = expression.shape
        let ease = 1 - pow(0.85, 60 * dt)
        open += (shape.eyeOpen - open) * ease
        width += (shape.eyeWidth - width) * ease
        curve += (shape.mouthCurve - curve) * ease
        mouthWidth += (shape.mouthWidth - mouthWidth) * ease
        if time >= nextBlink {
            blinkAt = time
            nextBlink = time + 2.5 + Double.random(in: 0...3.5)
        }
        if time >= nextGaze {
            gazeTarget = (Double.random(in: -0.2...0.2), Double.random(in: -0.125...0.125))
            nextGaze = time + 1.5 + Double.random(in: 0...2.5)
        }
        let follow = 1 - pow(0.92, 60 * dt)
        gaze.x += (shape.look.x + gazeTarget.x - gaze.x) * follow
        gaze.y += (shape.look.y + gazeTarget.y - gaze.y) * follow
        mouth += (loudness - mouth) * min(1, 0.5 * 60 * dt)
        nod += (mouth - nod) * min(1, 0.3 * 60 * dt)
        return expression == .sleeping ? 0 : max(0, 1 - (time - blinkAt) / 0.15)  // the blink, 1 = closed
    }
}

/// The teammate as a robot bust: shoulders, a head whose screen shows the face, and its accessory.
/// Proportions follow humanoid-companion's character renderer, so the desktop and the clips match.
struct CharacterView: View {
    let teammate: Teammate
    let expression: FaceExpression
    let loudness: () -> Double
    @State private var motion = FaceMotion()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let blink = motion.advance(to: time, expression: expression, loudness: loudness())
                draw(in: &context, size: size, time: time, blink: blink)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double, blink: Double) {
        let unit = min(size.width, size.height * 0.75)
        let headWidth = unit * 0.72, headHeight = unit * 0.56, bezel = max(4, unit * 0.035)
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.40)
        let trim = teammate.trim.color, glow = teammate.glow.color

        // Shoulders and neck, below the head.
        let neckTop = centre.y + headHeight / 2 - bezel
        let shouldersTop = neckTop + headHeight * 0.16
        context.fill(Path(CGRect(x: centre.x - headWidth * 0.09, y: neckTop, width: headWidth * 0.18, height: shouldersTop - neckTop + 4)),
                     with: .color(trim.opacity(0.7)))
        let half = headWidth * 0.62
        context.fill(Path(roundedRect: CGRect(x: centre.x - half, y: shouldersTop, width: 2 * half, height: size.height), cornerRadius: half * 0.5),
                     with: .color(trim))
        let badge = headWidth * 0.05, badgeY = shouldersTop + headHeight * 0.22
        context.fill(Path(ellipseIn: CGRect(x: centre.x - badge, y: badgeY - badge, width: 2 * badge, height: 2 * badge)), with: .color(glow))

        // The head nods a little with the voice.
        var head = context
        head.translateBy(x: centre.x, y: centre.y)
        head.rotate(by: .degrees(3 * motion.nod * sin(2 * .pi * 1.7 * time)))
        let frame = CGRect(x: -headWidth / 2, y: -headHeight / 2, width: headWidth, height: headHeight)
        let radius = headHeight * 0.22
        if teammate.accessory == .antenna {
            let length = headHeight * 0.2, ball = headHeight * 0.07
            var antenna = Path()
            antenna.move(to: CGPoint(x: 0, y: frame.minY))
            antenna.addLine(to: CGPoint(x: 0, y: frame.minY - length))
            head.stroke(antenna, with: .color(trim), lineWidth: bezel)
            let pulse = 0.6 + 0.4 * sin(2 * .pi * 0.8 * time)
            head.fill(Path(ellipseIn: CGRect(x: -ball, y: frame.minY - length - ball, width: 2 * ball, height: 2 * ball)),
                      with: .color(glow.opacity(pulse)))
        }
        head.fill(Path(roundedRect: frame, cornerRadius: radius), with: .color(trim))
        let screen = frame.insetBy(dx: bezel, dy: bezel)
        head.fill(Path(roundedRect: screen, cornerRadius: max(1, radius - bezel)), with: .color(teammate.background.color))
        drawFace(in: &head, screen: screen, blink: blink, time: time)
        if teammate.accessory == .headphones {
            var band = Path()
            band.addArc(center: CGPoint(x: 0, y: frame.midY), radius: headWidth * 0.56, startAngle: .degrees(195), endAngle: .degrees(345), clockwise: false)
            head.stroke(band, with: .color(trim), lineWidth: bezel * 1.6)
            let cupWidth = headWidth * 0.12, cupHeight = headHeight * 0.42
            for x in [frame.minX - cupWidth * 0.55, frame.maxX + cupWidth * 0.55] {
                let cup = Path(roundedRect: CGRect(x: x - cupWidth / 2, y: -cupHeight / 2, width: cupWidth, height: cupHeight), cornerRadius: cupWidth * 0.45)
                head.fill(cup, with: .color(trim))
                head.stroke(cup, with: .color(glow), lineWidth: max(2, bezel / 2))
            }
        }
    }

    private func drawFace(in context: inout GraphicsContext, screen: CGRect, blink: Double, time: Double) {
        let shape = expression.shape
        let u = min(screen.width, screen.height) / 10 * 1.35
        let glow = teammate.glow.color
        var face = context
        face.clip(to: Path(roundedRect: screen, cornerRadius: u))
        face.addFilter(.shadow(color: glow.opacity(0.9), radius: u * 0.35))
        let eyeWidth = u * 1.2 * motion.width, eyeHeight = max(u * 0.08, u * 1.6 * motion.open * (1 - blink))
        for side in [-1.0, 1.0] {
            let x = screen.midX + side * u * 2.2 + motion.gaze.x * u
            let y = screen.minY + screen.height * 0.42 + motion.gaze.y * u
            if shape.arcEyes {
                var arc = Path()
                arc.addArc(center: CGPoint(x: x, y: y + u * 0.3), radius: eyeWidth * 0.55, startAngle: .degrees(207), endAngle: .degrees(333), clockwise: false)
                face.stroke(arc, with: .color(glow), style: StrokeStyle(lineWidth: u * 0.35, lineCap: .round))
            } else {
                let eye = CGRect(x: x - eyeWidth / 2, y: y - eyeHeight / 2, width: eyeWidth, height: eyeHeight)
                face.fill(Path(roundedRect: eye, cornerRadius: min(eyeWidth, eyeHeight) / 2), with: .color(glow))
            }
            if shape.sadBrows {
                var brow = Path()
                brow.move(to: CGPoint(x: x - side * eyeWidth * 0.6, y: y - u * 1.45))
                brow.addLine(to: CGPoint(x: x + side * eyeWidth * 0.6, y: y - u * 1.05))
                face.stroke(brow, with: .color(glow), style: StrokeStyle(lineWidth: u * 0.22, lineCap: .round))
            }
        }
        let mouthX = screen.midX, mouthY = screen.minY + screen.height * 0.7, mouthWidth = u * 2.2 * motion.mouthWidth
        if motion.mouth > 0.04 || shape.openMouth {
            let (rx, ry) = shape.openMouth ? (u * 0.55, u * 0.45) : (mouthWidth / 2, u * (0.15 + 1.3 * motion.mouth) / 2)
            face.fill(Path(ellipseIn: CGRect(x: mouthX - rx, y: mouthY - ry, width: 2 * rx, height: 2 * ry)), with: .color(glow))
        } else {
            var smile = Path()
            smile.move(to: CGPoint(x: mouthX - mouthWidth / 2, y: mouthY))
            smile.addQuadCurve(to: CGPoint(x: mouthX + mouthWidth / 2, y: mouthY), control: CGPoint(x: mouthX, y: mouthY + motion.curve * u * 1.2))
            face.stroke(smile, with: .color(glow), style: StrokeStyle(lineWidth: u * 0.28, lineCap: .round))
        }
        var extras = context
        extras.clip(to: Path(roundedRect: screen, cornerRadius: u))
        if shape.thinkingDots {
            for index in 0..<3 {
                let lit = Int(time / 0.3) % 3 == index
                let dot = CGRect(x: screen.midX + u * 3.6 + Double(index) * u * 0.5 - u * 0.13, y: screen.minY + screen.height * 0.2 - u * 0.13, width: u * 0.26, height: u * 0.26)
                extras.fill(Path(ellipseIn: dot), with: .color(glow.opacity(lit ? 1 : 0.3)))
            }
        }
        if shape.listeningRing {
            let radius = u * 3.7
            let ring = CGRect(x: screen.midX - radius, y: screen.minY + screen.height * 0.52 - radius, width: 2 * radius, height: 2 * radius)
            extras.stroke(Path(ellipseIn: ring), with: .color(glow.opacity(0.35 + 0.25 * sin(time / 0.25))), lineWidth: max(1, u * 0.08))
        }
        if shape.sleepyZs {
            let alpha = 0.5 + 0.5 * sin(time / 0.6)
            extras.draw(Text("z").font(.system(size: u * 0.7)).foregroundColor(glow.opacity(alpha)),
                        at: CGPoint(x: screen.midX + u * 3.5, y: screen.minY + screen.height * 0.25))
        }
    }
}
