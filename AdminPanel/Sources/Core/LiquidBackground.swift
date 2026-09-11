import SwiftUI

/// Full-bleed animated backdrop: a soft white → gray50 gradient with four large,
/// slowly drifting blurred blobs in desaturated jewel tones. Place as the back
/// layer of a ZStack so Liquid Glass surfaces above it have something to refract.
struct LiquidBackground: View {

    private struct Blob {
        let color: Color
        let diameter: CGFloat
        /// Resting position as a fraction of the container size.
        let anchor: CGPoint
        /// Drift amplitude as a fraction of the container size.
        let amplitude: CGSize
        /// Radians per second — keep tiny for organic motion.
        let speedX: Double
        let speedY: Double
        let phase: Double
    }

    private let blobs: [Blob] = [
        Blob(
            color: Color(hex: 0xE8DCC8), // champagne gold
            diameter: 560,
            anchor: CGPoint(x: 0.18, y: 0.22),
            amplitude: CGSize(width: 0.14, height: 0.10),
            speedX: 0.06, speedY: 0.05, phase: 0.0
        ),
        Blob(
            color: Color(hex: 0xD6E2EA), // slate blue
            diameter: 500,
            anchor: CGPoint(x: 0.85, y: 0.30),
            amplitude: CGSize(width: 0.12, height: 0.13),
            speedX: 0.08, speedY: 0.10, phase: 1.7
        ),
        Blob(
            color: Color(hex: 0xEAD9E4), // blush
            diameter: 440,
            anchor: CGPoint(x: 0.30, y: 0.82),
            amplitude: CGSize(width: 0.13, height: 0.11),
            speedX: 0.11, speedY: 0.07, phase: 3.4
        ),
        Blob(
            color: Color(hex: 0xDDE8DC), // sage
            diameter: 380,
            anchor: CGPoint(x: 0.78, y: 0.75),
            amplitude: CGSize(width: 0.10, height: 0.14),
            speedX: 0.09, speedY: 0.12, phase: 5.1
        )
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                LinearGradient(
                    colors: [Color.white, Color.gray50],
                    startPoint: .top,
                    endPoint: .bottom
                )

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate

                    ZStack {
                        ForEach(blobs.indices, id: \.self) { index in
                            let blob = blobs[index]
                            Circle()
                                .fill(blob.color)
                                .frame(width: blob.diameter, height: blob.diameter)
                                .opacity(0.55)
                                .blur(radius: 70)
                                .position(
                                    x: size.width * (blob.anchor.x
                                        + blob.amplitude.width * CGFloat(sin(t * blob.speedX + blob.phase))),
                                    y: size.height * (blob.anchor.y
                                        + blob.amplitude.height * CGFloat(cos(t * blob.speedY + blob.phase)))
                                )
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    LiquidBackground()
}
